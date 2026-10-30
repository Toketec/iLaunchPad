import AppKit
import Carbon
import SwiftUI

extension Notification.Name {
    static let launchpadEscape = Notification.Name("iLaunchPad.escape")
    static let launchpadPreviousPage = Notification.Name("iLaunchPad.previousPage")
    static let launchpadNextPage = Notification.Name("iLaunchPad.nextPage")
    static let launchpadPageScroll = Notification.Name("iLaunchPad.pageScroll")
    static let launchpadPageScrollEnded = Notification.Name("iLaunchPad.pageScrollEnded")
    static let launchpadNavigate = Notification.Name("iLaunchPad.navigate")
    static let launchpadActivate = Notification.Name("iLaunchPad.activate")
    static let launchpadPresented = Notification.Name("iLaunchPad.presented")
    static let launchpadWillPresent = Notification.Name("iLaunchPad.willPresent")
    static let launchpadDismissed = Notification.Name("iLaunchPad.dismissed")
}

final class LaunchpadWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

@MainActor
final class LaunchpadWindowController: NSObject {
    static let shared = LaunchpadWindowController()
    private var window: LaunchpadWindow?
    private var transitionGeneration = 0
    private var closingMagnification: CGFloat = 0
    private var revealing = false
    private var previousPresentationOptions: NSApplication.PresentationOptions?
    var isVisible: Bool { window?.isVisible == true }
    func owns(_ candidate: NSWindow?) -> Bool { candidate != nil && candidate === window }

    private func prepareWindow() -> LaunchpadWindow? {
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
        guard let screen else { return nil }
        let result: LaunchpadWindow
        if let window { result = window }
        else {
            result = LaunchpadWindow(contentRect: screen.frame, styleMask: [.borderless], backing: .buffered, defer: false)
            result.level = .normal
            result.isOpaque = false
            result.backgroundColor = .clear
            result.hasShadow = false
            result.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
            result.contentView = NSHostingView(rootView: LaunchpadRootView())
            window = result
        }
        result.setFrame(screen.frame, display: true)
        return result
    }

    private func preparePresentation(in window: NSWindow) {
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            LaunchpadPresentation.shared.progress = 0
            let page = LaunchpadOpeningPage.resolve(
                returnToFirstPage: UserDefaults.standard.object(forKey: "returnToFirstPage") as? Bool ?? true,
                lastPage: UserDefaults.standard.integer(forKey: "lastPage"), count: LayoutStore.shared.pageCount)
            UserDefaults.standard.set(page, forKey: "lastPage")
            NotificationCenter.default.post(name: .launchpadWillPresent, object: NSNumber(value: page))
        }
        window.contentView?.layoutSubtreeIfNeeded()
    }

    func show(restartingReveal: Bool = true) {
        guard let window = prepareWindow() else { return }
        if restartingReveal { preparePresentation(in: window) }
        LayoutStore.shared.refreshApplicationsOnPresentation()
        transitionGeneration += 1
        LaunchpadPresentation.shared.closing = false
        if previousPresentationOptions == nil {
            previousPresentationOptions = NSApp.presentationOptions
        }
        var options = NSApp.presentationOptions
        options.remove(.autoHideDock)
        options.insert(.hideDock)
        NSApp.presentationOptions = options
        window.alphaValue = 1
        window.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        NotificationCenter.default.post(name: .launchpadPresented, object: nil)
        withAnimation(LaunchpadPresentation.shared.reducedMotion ? .easeOut(duration: 0.15) : LaunchpadMotion.reveal) {
            LaunchpadPresentation.shared.progress = 1
        }
    }

    func prepareInBackground() {
        // Construct the reusable view tree without ordering a window or changing focus.
        _ = prepareWindow()
        Task(priority: .utility) {
            let store = LayoutStore.shared
            let page = UserDefaults.standard.bool(forKey: "returnToFirstPage") ? 0 : UserDefaults.standard.integer(forKey: "lastPage")
            let pages = Array(store.layout.pages.indices).sorted { abs($0 - page) < abs($1 - page) }
            await ApplicationIconCache.shared.warm(pages.flatMap { store.groups(on: $0).flatMap(\.apps) })
        }
    }

    func hide(immediately: Bool = false) {
        guard let window, isVisible else { return }
        if LaunchpadPresentation.shared.closing && !immediately { return }
        transitionGeneration += 1
        let generation = transitionGeneration
        LaunchpadPresentation.shared.closing = true
        if let sheet = window.attachedSheet { window.endSheet(sheet, returnCode: .cancel) }
        NotificationCenter.default.post(name: .launchpadDismissed, object: nil)
        if immediately {
            window.orderOut(nil)
            LaunchpadPresentation.shared.progress = 0
            LaunchpadPresentation.shared.closing = false
            restorePresentationOptions()
            return
        }
        withAnimation(.smooth(duration: 0.23)) { LaunchpadPresentation.shared.progress = 0 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.24) { [weak self] in
            guard self?.transitionGeneration == generation else { return }
            window.orderOut(nil)
            self?.restorePresentationOptions()
            LaunchpadPresentation.shared.closing = false
        }
    }

    func restorePresentationOptions() {
        guard let options = previousPresentationOptions else { return }
        NSApp.presentationOptions = options
        previousPresentationOptions = nil
    }

    func toggle() {
        isVisible && !LaunchpadPresentation.shared.closing ? hide() : show()
    }

    func beginInteractiveReveal() {
        guard !isVisible, let window = prepareWindow() else { return }
        preparePresentation(in: window)
        revealing = true
        transitionGeneration += 1
        LaunchpadPresentation.shared.progress = 0.01
        // Leave focus with the source app until the gesture is committed.
        window.orderFrontRegardless()
    }

    func updateInteractiveReveal(progress: CGFloat) {
        guard revealing else { return }
        LaunchpadPresentation.shared.progress = min(max(progress, 0), 1)
    }

    func endInteractiveReveal(complete: Bool) {
        guard revealing else { return }
        revealing = false
        complete ? show(restartingReveal: false) : hide()
    }

    func magnify(_ event: NSEvent) {
        guard isVisible, !revealing else { return }
        if event.phase == .began { closingMagnification = 0 }
        closingMagnification += event.magnification
        let progress = min(max(closingMagnification / 0.42, 0), 1)
        LaunchpadPresentation.shared.progress = 1 - progress
        if event.phase == .ended || event.phase == .cancelled {
            if event.phase != .cancelled && closingMagnification > 0.18 { hide() }
            else {
                withAnimation(LaunchpadMotion.reveal) { LaunchpadPresentation.shared.progress = 1 }
            }
            closingMagnification = 0
        }
    }
}

private let hotKeyHandler: EventHandlerUPP = { _, _, _ in
    DispatchQueue.main.async {
        MainActor.assumeIsolated { LaunchpadWindowController.shared.toggle() }
    }
    return noErr
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var hotKey: EventHotKeyRef?
    private var f4HotKey: EventHotKeyRef?
    private var hotKeyHandlerRef: EventHandlerRef?
    private var inputMonitor: Any?
    private var scrollMonitor: Any?
    private var scrollEndWorkItem: DispatchWorkItem?
    private var lastWheelTime: TimeInterval = 0
    private var lastScrollTime: TimeInterval = 0
    private var scrollVelocity: CGFloat = 0
    private var gestureScrolling = false
    private var scrollUsesHorizontal: Bool?

    func applicationDidFinishLaunching(_ notification: Notification) {
        UserDefaults.standard.register(defaults: ["returnToFirstPage": true, "appIconStyle": AppIconCatalog.defaultID])
        let savedIconID = UserDefaults.standard.string(forKey: "appIconStyle")
        let iconID = AppIconCatalog.normalizedID(savedIconID)
        if iconID != savedIconID { UserDefaults.standard.set(iconID, forKey: "appIconStyle") }
        AppIconCatalog.apply(iconID)
        let loginLaunch = LoginItemController.isLoginLaunch(NSAppleEventManager.shared().currentAppleEvent)
        NSApp.setActivationPolicy(.regular)
        configureMenu()
        registerHotKey()
        registerInput()
        registerScrollPaging()
        if CommandLine.arguments.contains("--import-only") {
            let store = LayoutStore.shared
            Task {
                await store.waitForApplicationScan()
                print("Imported \(store.layout.pages.count) pages, \(store.allApps().count) apps")
                NSApp.terminate(nil)
            }
            return
        }
        LoginItemController.shared.refresh()
        if loginLaunch { LaunchpadWindowController.shared.prepareInBackground() }
        else { LaunchpadWindowController.shared.show() }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        LaunchpadWindowController.shared.toggle()
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        LayoutStore.shared.stopApplicationMonitoring()
        LaunchpadWindowController.shared.restorePresentationOptions()
        if let hotKey { UnregisterEventHotKey(hotKey) }
        if let f4HotKey { UnregisterEventHotKey(f4HotKey) }
        if let hotKeyHandlerRef { RemoveEventHandler(hotKeyHandlerRef) }
        if let inputMonitor { NSEvent.removeMonitor(inputMonitor) }
        if let scrollMonitor { NSEvent.removeMonitor(scrollMonitor) }
        scrollEndWorkItem?.cancel()
    }

    func applicationDidResignActive(_ notification: Notification) {
        // Switching to an existing app must dismiss the pad just like launching one.
        LaunchpadWindowController.shared.hide(immediately: true)
    }

    @objc private func toggleLaunchpad() { LaunchpadWindowController.shared.toggle() }

    @objc private func restoreLayout() {
        let alert = NSAlert()
        alert.messageText = "从 LaunchOS 恢复布局？"
        alert.informativeText = "这会用 LaunchOS 中的排序覆盖当前布局。"
        alert.addButton(withTitle: "恢复")
        alert.addButton(withTitle: "取消")
        if alert.runModal() == .alertFirstButtonReturn { LayoutStore.shared.restoreLaunchOSLayout() }
    }

    @objc private func refreshApplications() {
        ApplicationIconCache.shared.clear()
        LayoutStore.shared.refreshInstalledApplications()
    }
    @objc private func showHiddenApplications() { LayoutStore.shared.showAllHiddenApps() }

    private func configureMenu() {
        let menu = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "显示/隐藏 iLaunchPad", action: #selector(toggleLaunchpad), keyEquivalent: " ")
        appMenu.items.last?.keyEquivalentModifierMask = [.option]
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "从 LaunchOS 恢复布局…", action: #selector(restoreLayout), keyEquivalent: "")
        appMenu.addItem(withTitle: "刷新应用列表", action: #selector(refreshApplications), keyEquivalent: "r")
        appMenu.addItem(withTitle: "显示全部隐藏应用", action: #selector(showHiddenApplications), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "退出 iLaunchPad", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        for item in appMenu.items where item.action != #selector(NSApplication.terminate(_:)) { item.target = self }
        appItem.submenu = appMenu
        menu.addItem(appItem)
        NSApp.mainMenu = menu
    }

    private func registerHotKey() {
        var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), hotKeyHandler, 1, &type, nil, &hotKeyHandlerRef)
        RegisterEventHotKey(UInt32(kVK_Space), UInt32(optionKey), EventHotKeyID(signature: 0x694C5079, id: 1), GetApplicationEventTarget(), 0, &hotKey)
        RegisterEventHotKey(UInt32(kVK_F4), 0, EventHotKeyID(signature: 0x694C5079, id: 2), GetApplicationEventTarget(), 0, &f4HotKey)
    }

    private func registerInput() {
        inputMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .magnify]) { event in
            guard LaunchpadWindowController.shared.owns(event.window), NSApp.modalWindow == nil else { return event }
            if event.type == .magnify {
                LaunchpadWindowController.shared.magnify(event)
                return nil
            }
            if let editor = event.window?.firstResponder as? NSTextView, editor.hasMarkedText() { return event }
            if event.keyCode == 53 {
                NotificationCenter.default.post(name: .launchpadEscape, object: nil)
                return nil
            }
            if event.modifierFlags.contains(.command) {
                if event.keyCode == 123 || event.keyCode == 124 {
                    NotificationCenter.default.post(name: event.keyCode == 123 ? .launchpadPreviousPage : .launchpadNextPage, object: nil)
                    return nil
                }
                return event
            }
            if [123,124,125,126].contains(Int(event.keyCode)) {
                // Left and right still move the insertion point while editing a search or name.
                if let editor = event.window?.firstResponder as? NSTextView,
                   !editor.string.isEmpty, event.keyCode == 123 || event.keyCode == 124 { return event }
                NotificationCenter.default.post(name: .launchpadNavigate, object: NSNumber(value: event.keyCode))
                return nil
            }
            if event.keyCode == 36 || event.keyCode == 76 {
                if let editor = event.window?.firstResponder as? NSTextView,
                   editor.delegate is NSTextField, !(editor.delegate is NSSearchField) { return event }
                NotificationCenter.default.post(name: .launchpadActivate, object: nil)
                return nil
            }
            return event
        }
    }

    private func registerScrollPaging() {
        scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            guard let self, LaunchpadWindowController.shared.owns(event.window),
                  LaunchpadPresentation.shared.pagingEnabled, NSApp.modalWindow == nil else { return event }
            // One physical gesture settles once. Momentum cannot start a second page transition.
            if !event.momentumPhase.isEmpty { return nil }
            var delta = abs(event.scrollingDeltaX) >= abs(event.scrollingDeltaY)
                ? event.scrollingDeltaX : event.scrollingDeltaY
            if !event.hasPreciseScrollingDeltas {
                if abs(delta) > 0.1, event.timestamp - self.lastWheelTime > 0.22 {
                    self.lastWheelTime = event.timestamp
                    NotificationCenter.default.post(name: delta > 0 ? .launchpadPreviousPage : .launchpadNextPage, object: nil)
                }
                return nil
            }
            if event.phase == .began || !self.gestureScrolling {
                self.gestureScrolling = true
                self.scrollUsesHorizontal = nil
                self.scrollVelocity = 0
                self.lastScrollTime = event.timestamp
                self.scrollEndWorkItem?.cancel()
            }
            // Lock one axis for the entire gesture. Comparing X/Y anew on every
            // event causes diagonal trackpad movements to reverse/jitter mid-page.
            if self.scrollUsesHorizontal == nil, abs(delta) > 0.1 {
                self.scrollUsesHorizontal = abs(event.scrollingDeltaX) >= abs(event.scrollingDeltaY)
            }
            if let horizontal = self.scrollUsesHorizontal {
                delta = horizontal ? event.scrollingDeltaX : event.scrollingDeltaY
            }
            let elapsed = event.timestamp - self.lastScrollTime
            if abs(delta) > 0.01 {
                if elapsed > 0 && elapsed < 0.12 {
                    self.scrollVelocity = self.scrollVelocity * 0.35 + min(6000, max(-6000, delta / elapsed)) * 0.65
                }
                self.lastScrollTime = event.timestamp
                NotificationCenter.default.post(name: .launchpadPageScroll, object: NSNumber(value: Double(delta)))
            }
            if event.phase == .ended || event.phase == .cancelled {
                self.finishScroll(cancelled: event.phase == .cancelled)
            } else if event.phase.isEmpty {
                self.scrollEndWorkItem?.cancel()
                let end = DispatchWorkItem { [weak self] in self?.finishScroll(cancelled: false) }
                self.scrollEndWorkItem = end
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.14, execute: end)
            }
            return nil
        }
    }

    private func finishScroll(cancelled: Bool) {
        scrollEndWorkItem?.cancel()
        let velocity = ProcessInfo.processInfo.systemUptime - lastScrollTime < 0.12 ? scrollVelocity : 0
        NotificationCenter.default.post(name: .launchpadPageScrollEnded, object: nil,
                                        userInfo: ["velocity": velocity, "cancelled": cancelled])
        scrollVelocity = 0
        gestureScrolling = false
        scrollUsesHorizontal = nil
    }
}

@main
struct ILaunchPadApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    var body: some Scene { Settings { LaunchpadSettingsView() } }
}

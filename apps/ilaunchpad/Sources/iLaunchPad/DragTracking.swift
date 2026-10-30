import AppKit
import SwiftUI

/// A window (not a disappearing source cell) owns the display timing domain.
@MainActor
final class WindowDragClock: NSObject {
    private weak var window: NSWindow?
    private var link: CADisplayLink?
    private var action: (() -> Void)?
    private(set) var isRunning = false
    private var maximumFPS = 0

    func start(window: NSWindow, action: @escaping () -> Void) {
        stop()
        self.window = window
        self.action = action
        let link = window.displayLink(target: self, selector: #selector(tick(_:)))
        self.link = link
        isRunning = true
        updateRate()
        link.add(to: .main, forMode: .common)
    }

    func stop() {
        link?.invalidate()
        link = nil
        action = nil
        window = nil
        maximumFPS = 0
        isRunning = false
    }

    private func updateRate() {
        let rate = max(30, window?.screen?.maximumFramesPerSecond ?? 60)
        guard rate != maximumFPS else { return }
        maximumFPS = rate
        link?.preferredFrameRateRange = CAFrameRateRange(minimum: Float(min(30, rate)),
                                                        maximum: Float(rate), preferred: Float(rate))
    }

    @objc private func tick(_ sender: CADisplayLink) {
        guard isRunning else { return }
        updateRate()
        action?()
    }
}

extension Notification.Name {
    static let launchpadDragGeometry = Notification.Name("iLaunchPad.dragGeometry")
    static let launchpadDragFinished = Notification.Name("iLaunchPad.dragFinished")
}

enum DragDestination: Equatable {
    case page(Int), folder(String), merge(String)
}

struct NativeDragIdentity {
    let sessionID: UUID
    let sequenceNumber: Int
    let payload: DragPayload

    func matches(sessionID: UUID, sequenceNumber: Int, token: String?) -> Bool {
        guard self.sessionID == sessionID, self.sequenceNumber == sequenceNumber else { return false }
        switch payload {
        case .group(let id), .folderApp(let id, _): return token == id
        }
    }
}

@MainActor protocol NativeDragSessionOwner: AnyObject {
    var nativeDragIdentity: NativeDragIdentity? { get }
}

/// One ordered position update: container transitions first, then grid placement.
@MainActor enum DragTracking {
    private static weak var lastUpdatedStore: LayoutStore?
    private static var lastUpdatedSession: UUID?
    private static var lastUpdatedPoint = CGPoint.zero
    private static var lastUpdateTime: TimeInterval = 0

    static func updateFromDisplay(_ point: CGPoint, store: LayoutStore, maximumFPS: Int) {
        // Native drag events already delivered this position during this frame.
        // Do not repeat the geometry/layout work; stationary dwell still advances
        // on later frames, and final drop always bypasses this gate.
        let elapsed = ProcessInfo.processInfo.systemUptime - lastUpdateTime
        if lastUpdatedStore === store, lastUpdatedSession == store.dragSessionID,
           point == lastUpdatedPoint, elapsed < 1 / Double(maximumFPS > 0 ? maximumFPS : 60) { return }
        update(point, store: store)
    }
    static var tracingEnabled: Bool { ProcessInfo.processInfo.environment["ILAUNCHPAD_DRAG_TRACE"] == "1" }
    private static var traceStates: [String: String] = [:]
    static func traceChange(_ key: String, _ state: String, store: LayoutStore) {
        guard tracingEnabled else { return }
        let value = "\(store.dragSessionID) \(state)"
        guard traceStates[key] != value else { return }
        traceStates[key] = value
        trace("\(key) \(state)", store: store)
    }
    static func traceHit(at point: CGPoint, window: NSWindow?, store: LayoutStore) {
        guard tracingEnabled, let window, let root = window.contentView else { return }
        let local = root.superview?.convert(window.convertPoint(fromScreen: point), from: nil)
            ?? window.convertPoint(fromScreen: point)
        var view = root.hitTest(local)
        var chain: [String] = []
        while let current = view {
            chain.append("\(type(of: current))[\(current.registeredDraggedTypes.map(\.rawValue).joined(separator: ","))]")
            view = current.superview
        }
        traceChange("pointer.hit", chain.joined(separator: " > "), store: store)
    }
    static func nativePayload(_ info: NSDraggingInfo, store: LayoutStore) -> DragPayload? {
        guard store.isPreviewingDrag, info.draggingSource != nil,
              info.draggingSourceOperationMask.contains(.move),
              let owner = store.dragLifetime as? NativeDragSessionOwner,
              let identity = owner.nativeDragIdentity,
              identity.matches(sessionID: store.dragSessionID, sequenceNumber: info.draggingSequenceNumber,
                               token: info.draggingPasteboard.string(forType: .string)) else { return nil }
        return identity.payload
    }
    static func trace(_ event: String, store: LayoutStore) {
        guard tracingEnabled else { return }
        let line = "drag \(store.dragSessionID) \(event) active=\(store.isPreviewingDrag) folder=\(store.dragOpenFolderID != nil)\n"
        FileHandle.standardError.write(Data(line.utf8))
    }
    static func update(_ point: CGPoint, store: LayoutStore, dropping: Bool = false) {
        guard store.isPreviewingDrag else { return }
        lastUpdatedStore = store
        lastUpdatedSession = store.dragSessionID
        lastUpdatedPoint = point
        lastUpdateTime = ProcessInfo.processInfo.systemUptime
        store.dragDestination = nil
        let info: [String: Any] = ["point": NSValue(point: point), "time": ProcessInfo.processInfo.systemUptime, "dropping": dropping]
        NotificationCenter.default.post(name: .launchpadDragGeometry, object: store, userInfo: info)
        NotificationCenter.default.post(name: .launchpadDragMoved, object: store, userInfo: info)
    }

    static func drop(_ point: CGPoint, store: LayoutStore, payload: DragPayload) -> Bool {
        guard store.isPreviewingDrag else { return false }
        trace("drop.begin", store: store)
        update(point, store: store, dropping: true)
        guard let destination = store.dragDestination else {
            trace("drop.no-destination", store: store)
            return false
        }
        switch destination {
        case .page(let page):
            if let id = store.previewMoveToPage(payload, page: page),
               !store.groups(on: page).contains(where: { $0.id == id }) { store.moveGroup(id, toPage: page) }
        case .folder(let id):
            guard store.group(id: id)?.isFolder == true else { return false }
            store.previewMove(payload, intoFolder: id)
        case .merge(let id):
            // Old/stale merge candidates cannot create a second folder at release.
            guard store.temporaryFolderID == id, store.group(id: id)?.isFolder == true else { return false }
            store.dragDestination = .folder(id)
        }
        store.finishDragPreview(commit: true)
        trace("drop.committed", store: store)
        return true
    }
}

/// Dwell is keyed by target identity, not by a one-shot work item.
struct DragDwell: Equatable {
    private(set) var target: String?
    private var since: TimeInterval = 0
    mutating func reset() { target = nil }
    mutating func update(_ id: String, now: TimeInterval, delay: TimeInterval) -> Bool {
        if target != id { target = id; since = now }
        return now - since >= delay
    }
}

/// Short intent windows keep a folder from moving away while the pointer is
/// merely crossing its surrounding cell on the way to the visible glyph.
enum DragIntentTiming {
    static let reorder: TimeInterval = 0.16
    // Give a slow approach time to reach the glyph before its cell moves away.
    static let topLevelReorder: TimeInterval = 0.35
    static let folderSelection: TimeInterval = 0.12
    static let folderOpen: TimeInterval = 0.65
    static let appMerge: TimeInterval = 0.8

    static func isReady(
        _ dwell: inout DragDwell,
        key: String,
        now: TimeInterval,
        delay: TimeInterval,
        dropping: Bool
    ) -> Bool {
        if dropping {
            dwell.reset()
            return true
        }
        return dwell.update(key, now: now, delay: delay)
    }
}

/// Spring-open travel is not a folder exit. Exit is armed only after entry,
/// or after the pointer deliberately retreats from the panel.
struct FolderDragTravel {
    private var entered = false
    private var closestDistance = CGFloat.infinity
    private var outsideSince: TimeInterval?
    mutating func shouldClose(point: CGPoint, panel: CGRect, now: TimeInterval, dropping: Bool = false) -> Bool {
        if panel.insetBy(dx: -20, dy: -20).contains(point) {
            entered = true; outsideSince = nil; return false
        }
        let dx = max(panel.minX - point.x, 0, point.x - panel.maxX)
        let dy = max(panel.minY - point.y, 0, point.y - panel.maxY)
        let distance = hypot(dx, dy)
        if dropping && entered { return true }
        closestDistance = min(closestDistance, distance)
        guard entered || distance > closestDistance + 64 else { outsideSince = nil; return false }
        if outsideSince == nil { outsideSince = now }
        return now - (outsideSince ?? now) >= 0.22
    }
}

struct DragPageTracking: NSViewRepresentable {
    let page: Int
    let count: Int
    let onPage: (Int) -> Void
    func makeNSView(context: Context) -> TrackingView { TrackingView() }
    func updateNSView(_ view: TrackingView, context: Context) {
        view.page = page; view.count = count; view.onPage = onPage
        LayoutStore.shared.dragCurrentPage = page
    }
    final class TrackingView: NSView {
        var page = 0
        var count = 1
        var onPage: ((Int) -> Void)?
        private var dwell = DragDwell()
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
        override init(frame: NSRect) {
            super.init(frame: frame)
            NotificationCenter.default.addObserver(self, selector: #selector(track(_:)), name: .launchpadDragGeometry, object: nil)
            NotificationCenter.default.addObserver(self, selector: #selector(reset), name: .launchpadDragFinished, object: nil)
        }
        required init?(coder: NSCoder) { nil }
        deinit { NotificationCenter.default.removeObserver(self) }
        @objc private func reset() { dwell.reset() }
        @objc private func track(_ event: Notification) {
            guard let store = event.object as? LayoutStore, let window,
                  let value = event.userInfo?["point"] as? NSValue,
                  let now = event.userInfo?["time"] as? TimeInterval else { return }
            guard store.dragOpenFolderID == nil else { dwell.reset(); return }
            let point = convert(window.convertPoint(fromScreen: value.pointValue), from: nil)
            guard bounds.contains(point) else { dwell.reset(); return }
            store.dragDestination = .page(store.dragCurrentPage)
            guard now >= store.dragRoutingPausedUntil, event.userInfo?["dropping"] as? Bool != true else { dwell.reset(); return }
            let next = point.x < 48 ? page - 1 : point.x > bounds.width - 48 ? page + 1 : page
            guard next != page, next >= 0, next < count else { dwell.reset(); return }
            if dwell.update("\(next)", now: now, delay: 0.5) {
                dwell.reset()
                store.dragCurrentPage = next
                store.dragRoutingPausedUntil = now + 0.32
                store.dragDestination = .page(next)
                page = next
                onPage?(next)
            }
        }
    }
}

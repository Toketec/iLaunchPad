import AppKit
import SwiftUI

enum LaunchpadOpeningPage {
    static func resolve(returnToFirstPage: Bool, lastPage: Int, count: Int) -> Int {
        returnToFirstPage ? 0 : min(max(0, lastPage), max(0, count - 1))
    }
}

enum PageRealization {
    static func shouldRealize(_ page: Int, current: Int, retained: Set<Int>) -> Bool {
        abs(page - current) <= 1 || retained.contains(page)
    }
}

/// One native clipped surface owns paging, including all embedded collection views.
struct PagingSurface<Content: View>: NSViewRepresentable {
    @Binding var currentPage: Int
    let pageCount: Int
    let width: CGFloat
    let height: CGFloat
    let enabled: Bool
    let onSettled: () -> Void
    @ViewBuilder let content: Content

    func makeNSView(context: Context) -> NativePagingView {
        let view = NativePagingView()
        updateNSView(view, context: context)
        return view
    }

    func updateNSView(_ view: NativePagingView, context: Context) {
        view.onSettled = { page in
            currentPage = page
            onSettled()
        }
        // Never animate embedded NSViewRepresentable pages independently.
        let root = AnyView(content
            .frame(width: width * CGFloat(pageCount), height: height, alignment: .leading)
            .transaction { $0.animation = nil; $0.disablesAnimations = true })
        view.configure(root: root, page: currentPage, count: pageCount,
                       size: CGSize(width: width, height: height), enabled: enabled)
    }
}

final class NativePagingView: NSView {
    private let host = NSHostingView(rootView: AnyView(EmptyView()))
    private var page = 0
    private var count = 1
    private var pageSize = CGSize.zero
    private var pagingEnabled = true
    private var draggingPage = false
    private var gestureStartX: CGFloat = 0
    private var gestureDelta: CGFloat = 0
    private var generation = 0
    private var animating = false
    private var pendingPresentationPage: Int?
    var onSettled: ((Int) -> Void)?

    override var isFlipped: Bool { true }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.masksToBounds = true
        host.wantsLayer = true
        host.sizingOptions = []
        addSubview(host)
        NotificationCenter.default.addObserver(self, selector: #selector(handlePageScroll(_:)), name: .launchpadPageScroll, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(endScroll(_:)), name: .launchpadPageScrollEnded, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(resetPaging), name: .launchpadDismissed, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(prepareForPresentation(_:)), name: .launchpadWillPresent, object: nil)
    }

    required init?(coder: NSCoder) { nil }
    deinit { NotificationCenter.default.removeObserver(self) }

    func configure(root: AnyView, page: Int, count: Int, size: CGSize, enabled: Bool) {
        let resized = size != pageSize || count != self.count
        let requestedPage = min(max(0, page), max(0, count - 1))
        let destination = pendingPresentationPage.map { min(max(0, $0), max(0, count - 1)) } ?? requestedPage
        let changedPage = destination != self.page
        host.rootView = root
        self.count = count
        pageSize = size
        pagingEnabled = enabled
        self.page = destination
        if resized {
            stopAnimation()
            host.setFrameSize(NSSize(width: size.width * CGFloat(count), height: size.height))
            host.setFrameOrigin(NSPoint(x: -CGFloat(destination) * size.width, y: 0))
        } else if changedPage {
            draggingPage = false
            settle(to: destination, animated: true)
        } else if !enabled && draggingPage {
            draggingPage = false
            settle(to: destination, animated: false)
        }
        if let pending = pendingPresentationPage, requestedPage == pending {
            self.pendingPresentationPage = nil
        }
    }

    // While animating, model frames are already at the destination. Don't allow
    // a click to activate an app that hasn't visibly arrived there yet.
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let hit = super.hitTest(point) else { return nil }
        return animating || draggingPage ? self : hit
    }

    private func stopAnimation() {
        generation += 1
        if animating {
            let x = host.layer?.presentation()?.frame.minX ?? host.frame.minX
            host.layer?.removeAllAnimations()
            host.setFrameOrigin(NSPoint(x: x, y: 0))
        }
        animating = false
    }

    @objc private func handlePageScroll(_ notification: Notification) {
        guard pagingEnabled, window?.isVisible == true,
              let value = notification.object as? NSNumber else { return }
        if !draggingPage {
            stopAnimation()
            draggingPage = true
            gestureStartX = host.frame.minX
            gestureDelta = 0
        }
        gestureDelta += CGFloat(value.doubleValue)
        let anchor = -CGFloat(page) * pageSize.width
        let proposed = min(anchor + pageSize.width, max(anchor - pageSize.width, gestureStartX + gestureDelta))
        let lower = -CGFloat(max(0, count - 1)) * pageSize.width
        let bounded = min(0, max(lower, proposed))
        let excess = proposed - bounded
        let x = bounded + excess * 0.28 / (1 + abs(excess) / max(1, pageSize.width))
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        host.setFrameOrigin(NSPoint(x: x, y: 0))
        CATransaction.commit()
    }

    @objc private func endScroll(_ notification: Notification) {
        guard draggingPage else { return }
        draggingPage = false
        let cancelled = notification.userInfo?["cancelled"] as? Bool ?? false
        let velocity = notification.userInfo?["velocity"] as? CGFloat ?? 0
        let offset = host.frame.minX + CGFloat(page) * pageSize.width
        let predicted = offset + velocity * 0.15
        var destination = page
        if !cancelled {
            if predicted < -pageSize.width * 0.13 { destination += 1 }
            else if predicted > pageSize.width * 0.13 { destination -= 1 }
        }
        destination = min(max(0, destination), count - 1)
        page = destination
        settle(to: destination, animated: true)
        onSettled?(destination)
    }

    private func settle(to destination: Int, animated: Bool) {
        stopAnimation()
        let target = NSPoint(x: -CGFloat(destination) * pageSize.width, y: 0)
        guard animated, abs(host.frame.minX - target.x) > 0.5 else {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            host.setFrameOrigin(target)
            CATransaction.commit()
            return
        }
        animating = true
        let ticket = generation
        NSAnimationContext.runAnimationGroup { context in
            context.duration = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0.12 : 0.28
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.8, 0.2, 1)
            host.animator().setFrameOrigin(target)
        } completionHandler: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, self.generation == ticket else { return }
                self.animating = false
            }
        }
    }

    @objc private func resetPaging() {
        draggingPage = false
        settle(to: page, animated: false)
    }

    @objc private func prepareForPresentation(_ notification: Notification) {
        guard let destination = notification.object as? NSNumber else { return }
        draggingPage = false
        gestureDelta = 0
        page = min(max(0, destination.intValue), max(0, count - 1))
        pendingPresentationPage = page
        settle(to: page, animated: false)
        onSettled?(page)
    }
}

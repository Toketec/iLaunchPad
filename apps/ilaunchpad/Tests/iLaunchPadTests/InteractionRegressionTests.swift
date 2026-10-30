import AppKit
import SwiftUI
import Testing
@testable import iLaunchPad

@Suite(.serialized)
@MainActor
struct InteractionRegressionTests {
    @Test func openingPolicySelectsHomepageOrClampedRememberedPage() {
        #expect(LaunchpadOpeningPage.resolve(returnToFirstPage: true, lastPage: 2, count: 3) == 0)
        #expect(LaunchpadOpeningPage.resolve(returnToFirstPage: false, lastPage: 2, count: 3) == 2)
        #expect(LaunchpadOpeningPage.resolve(returnToFirstPage: false, lastPage: 8, count: 3) == 2)
        #expect(LaunchpadOpeningPage.resolve(returnToFirstPage: false, lastPage: -1, count: 0) == 0)
    }

    @Test func reopeningSnapsNativeSurfaceBeforeSpreadInsteadOfSliding() {
        let view = NativePagingView()
        let root = AnyView(Color.clear)
        view.configure(root: root, page: 2, count: 3, size: CGSize(width: 800, height: 500), enabled: true)
        let host = view.subviews[0]
        #expect(host.frame.minX == -1600)
        var settled: Int?
        view.onSettled = { settled = $0 }
        NotificationCenter.default.post(name: .launchpadWillPresent, object: NSNumber(value: 0))
        #expect(host.frame.minX == 0)
        #expect((host.layer?.animationKeys() ?? []).isEmpty)
        #expect(settled == 0)
        // SwiftUI/AppStorage can still issue one update with the previously
        // visible page before it observes the opening-page change. That stale
        // update must not animate the hidden pager away from the homepage.
        view.configure(root: root, page: 2, count: 3, size: CGSize(width: 800, height: 500), enabled: true)
        #expect(host.frame.minX == 0)
        #expect((host.layer?.animationKeys() ?? []).isEmpty)
        view.configure(root: root, page: 0, count: 3, size: CGSize(width: 800, height: 500), enabled: true)
        #expect(host.frame.minX == 0)
        #expect((host.layer?.animationKeys() ?? []).isEmpty)
    }

    @Test func openingCancelsPendingPagingAndCanKeepRememberedPage() async throws {
        let view = NativePagingView()
        let root = AnyView(Color.clear)
        let size = CGSize(width: 800, height: 500)
        view.configure(root: root, page: 0, count: 3, size: size, enabled: true)
        view.configure(root: root, page: 2, count: 3, size: size, enabled: true)
        NotificationCenter.default.post(name: .launchpadWillPresent, object: NSNumber(value: 0))
        #expect(view.subviews[0].frame.minX == 0)
        try await Task.sleep(for: .milliseconds(350))
        #expect(view.subviews[0].frame.minX == 0)
        NotificationCenter.default.post(name: .launchpadWillPresent, object: NSNumber(value: 2))
        #expect(view.subviews[0].frame.minX == -1600)
        #expect((view.subviews[0].layer?.animationKeys() ?? []).isEmpty)
    }

    @Test func pagesAreLazyButVisitedDragSourcesStayAlive() {
        #expect(PageRealization.shouldRealize(0, current: 0, retained: []))
        #expect(PageRealization.shouldRealize(1, current: 0, retained: []))
        #expect(!PageRealization.shouldRealize(3, current: 0, retained: []))
        #expect(PageRealization.shouldRealize(3, current: 3, retained: [0, 1]))
        #expect(PageRealization.shouldRealize(0, current: 3, retained: [0, 1]))
    }

    @Test func displayClockStopsAndCanRestartWithStableWindow() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 200, height: 200),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        let clock = WindowDragClock()
        clock.start(window: window) {}
        #expect(clock.isRunning)
        clock.stop()
        #expect(!clock.isRunning)
        clock.start(window: window) {}
        #expect(clock.isRunning)
        clock.stop()
    }

    @Test func folderMorphReturnsToTheActualSourceForEitherLayerAnchor() {
        let source = CGRect(x: 820, y: 930, width: 92, height: 92)
        let destination = CGRect(x: 360, y: 300, width: 1080, height: 580)
        for anchor in [CGPoint.zero, CGPoint(x: 0.5, y: 0.5)] {
            let transform = NativeFolderMorphView.collapsedTransform(source: source, destination: destination, anchor: anchor)
            let localCenter = CGPoint(x: (0.5 - anchor.x) * destination.width,
                                      y: (0.5 - anchor.y) * destination.height)
            let x = destination.minX + anchor.x * destination.width + localCenter.x * transform.m11 + transform.m41
            let y = destination.minY + anchor.y * destination.height + localCenter.y * transform.m22 + transform.m42
            #expect(abs(x - source.midX) < 0.001)
            #expect(abs(y - source.midY) < 0.001)
            #expect(abs(destination.width * transform.m11 - source.width) < 0.001)
            #expect(abs(destination.height * transform.m22 - source.height) < 0.001)
        }
    }

    @Test func folderOnlyAcceptsVisibleRoundedIcon() {
        let frame = NSRect(x: 60, y: 60, width: 92, height: 92)
        let inside = LaunchpadCollectionItem.folderContains(_:frame:radius:)
        #expect(inside(NSPoint(x: 106, y: 106), frame, 22))
        #expect(!inside(NSPoint(x: 54, y: 106), frame, 22))
        #expect(!inside(NSPoint(x: 158, y: 106), frame, 22))
        #expect(!inside(NSPoint(x: 61, y: 61), frame, 22))
        #expect(!inside(NSPoint(x: 106, y: 48), frame, 22))
    }

    @Test func nativePagerOwnsOneClippedSurface() {
        let pager = NativePagingView(frame: NSRect(x: 0, y: 0, width: 700, height: 400))
        pager.configure(root: AnyView(Color.clear), page: 1, count: 3,
                        size: CGSize(width: 700, height: 400), enabled: true)
        #expect(pager.layer?.masksToBounds == true)
        #expect(pager.subviews.count == 1)
        #expect(pager.subviews[0].frame == NSRect(x: -700, y: 0, width: 2100, height: 400))
    }

    @Test func resizeKeepsTheSelectedPageAligned() {
        let pager = NativePagingView(frame: .zero)
        pager.configure(root: AnyView(Color.clear), page: 2, count: 3,
                        size: CGSize(width: 700, height: 400), enabled: true)
        pager.configure(root: AnyView(Color.clear), page: 2, count: 3,
                        size: CGSize(width: 900, height: 500), enabled: true)
        #expect(pager.subviews[0].frame == NSRect(x: -1800, y: 0, width: 2700, height: 500))
    }

    @Test func rapidReversalAndDismissalEndOnOneExactPage() async throws {
        let pager = NativePagingView(frame: .zero)
        let root = AnyView(Color.clear)
        let size = CGSize(width: 700, height: 400)
        pager.configure(root: root, page: 0, count: 3, size: size, enabled: true)
        pager.configure(root: root, page: 1, count: 3, size: size, enabled: true)
        pager.configure(root: root, page: 0, count: 3, size: size, enabled: true)
        NotificationCenter.default.post(name: .launchpadDismissed, object: nil)
        try await Task.sleep(for: .milliseconds(350))
        #expect(pager.subviews[0].frame.origin == .zero)
        #expect(pager.subviews[0].frame.width == 2100)
    }
}

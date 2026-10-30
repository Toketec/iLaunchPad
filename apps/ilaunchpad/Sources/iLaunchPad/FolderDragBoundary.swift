import AppKit
import SwiftUI

extension Notification.Name {
    static let launchpadDragMoved = Notification.Name("iLaunchPad.dragMoved")
}

/// Observe the native drag without installing a second gesture or consuming it.
struct FolderDragBoundary: NSViewRepresentable {
    let panel: CGRect
    let active: Bool
    let folderID: String
    let onExit: () -> Void

    func makeNSView(context: Context) -> BoundaryView { BoundaryView() }
    func updateNSView(_ view: BoundaryView, context: Context) {
        view.panel = panel
        view.active = active
        view.folderID = folderID
        view.onExit = onExit
    }

    final class BoundaryView: NSView {
        var panel = CGRect.zero
        var active = false {
            didSet { if active != oldValue { travel = FolderDragTravel(); exited = false } }
        }
        var folderID = ""
        var onExit: (() -> Void)?
        private var travel = FolderDragTravel()
        private var session: UUID?
        private var exited = false
        override var isFlipped: Bool { true }
        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override init(frame: NSRect) {
            super.init(frame: frame)
            NotificationCenter.default.addObserver(self, selector: #selector(moved(_:)), name: .launchpadDragGeometry, object: nil)
        }
        required init?(coder: NSCoder) { nil }
        deinit { NotificationCenter.default.removeObserver(self) }

        @objc private func moved(_ event: Notification) {
            guard active, let window, let store = event.object as? LayoutStore,
                  store.dragOpenFolderID == folderID,
                  let value = event.userInfo?["point"] as? NSValue,
                  let now = event.userInfo?["time"] as? TimeInterval else { return }
            if session != store.dragSessionID {
                session = store.dragSessionID; travel = FolderDragTravel(); exited = false
            }
            guard !exited else { return }
            let point = convert(window.convertPoint(fromScreen: value.pointValue), from: nil)
            store.dragDestination = .folder(folderID)
            let dropping = event.userInfo?["dropping"] as? Bool == true
            let releasedOutsideTemporaryGroup = dropping && store.temporaryFolderID == folderID
                && !NSBezierPath(roundedRect: panel, xRadius: 44, yRadius: 44).contains(point)
            if releasedOutsideTemporaryGroup || travel.shouldClose(point: point, panel: panel, now: now, dropping: dropping) {
                exited = true
                onExit?()
                store.dragDestination = .page(store.dragCurrentPage)
            }
        }
    }
}

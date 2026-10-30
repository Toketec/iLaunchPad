import AppKit
import SwiftUI

/// Lay out real system glass and its contents once. Core Animation transforms
/// the complete native surface; SwiftUI never resizes its grid during the morph.
struct FolderMorphSurface<Content: View>: NSViewRepresentable {
    let size: CGSize
    let source: CGRect
    let destination: CGRect
    let expanded: Bool
    let onCollapsed: () -> Void
    var dropStore: LayoutStore? = nil
    var dropFolderID: String? = nil
    @ViewBuilder let content: Content

    func makeNSView(context: Context) -> NativeFolderMorphView {
        let view = NativeFolderMorphView()
        updateNSView(view, context: context)
        return view
    }

    func updateNSView(_ view: NativeFolderMorphView, context: Context) {
        view.onCollapsed = onCollapsed
        view.dropStore = dropStore
        view.dropFolderID = dropFolderID
        view.configure(content: AnyView(content.transaction {
            $0.animation = nil
            $0.disablesAnimations = true
        }), size: size, source: source, destination: destination, expanded: expanded)
    }
}

final class NativeFolderMorphView: NSView {
    private static let dropReceivers = NSHashTable<NativeFolderMorphView>.weakObjects()
    private let glass = NSGlassEffectView()
    private let contentHost = NSHostingView(rootView: AnyView(EmptyView()))
    private var expanded: Bool?
    private var generation = 0
    private var transitioning = false
    var onCollapsed: (() -> Void)?
    weak var dropStore: LayoutStore?
    var dropFolderID: String?

    override var isFlipped: Bool { true }

    override init(frame: NSRect) {
        super.init(frame: frame)
        Self.dropReceivers.add(self)
        wantsLayer = true
        registerForDraggedTypes([.string])
        clipsToBounds = false
        layer?.masksToBounds = false
        glass.wantsLayer = true
        glass.style = .clear
        glass.cornerRadius = 44
        glass.layer?.cornerRadius = 44
        glass.layer?.cornerCurve = .continuous
        glass.appearance = NSAppearance(named: .darkAqua)
        contentHost.sizingOptions = []
        contentHost.wantsLayer = true
        contentHost.layer?.cornerRadius = 44
        contentHost.layer?.cornerCurve = .continuous
        contentHost.layer?.masksToBounds = true
        glass.contentView = contentHost
        addSubview(glass)
    }

    required init?(coder: NSCoder) { nil }

    /// AppKit can keep delivering this session to the page that existed before
    /// spring-opening. Forward the real callback, not a mouse-release fallback.
    static func receiveOpenFolderDrop(_ info: NSDraggingInfo, store: LayoutStore, dropping: Bool) -> Bool {
        guard let folderID = store.dragOpenFolderID,
              let receiver = dropReceivers.allObjects.first(where: {
                  $0.dropStore === store && $0.dropFolderID == folderID && $0.expanded == true &&
                  $0.window != nil && $0.window === info.draggingDestinationWindow
              }) else { return false }
        return receiver.receiveNativeDrop(info, dropping: dropping)
    }

    func receiveNativeDrop(_ info: NSDraggingInfo, dropping: Bool) -> Bool {
        if DragTracking.tracingEnabled, let store = dropStore {
            DragTracking.traceChange("native-folder.receive",
                "dropping=\(dropping) expanded=\(expanded == true) current=\(store.dragOpenFolderID == dropFolderID) identity=\(DragTracking.nativePayload(info, store: store) != nil) window=\(window != nil && info.draggingDestinationWindow === window) inside=\(NSBezierPath(roundedRect: bounds, xRadius: 44, yRadius: 44).contains(convert(info.draggingLocation, from: nil)))", store: store)
        }
        guard expanded == true, let store = dropStore, let folderID = dropFolderID,
              store.dragOpenFolderID == folderID, store.group(id: folderID)?.isFolder == true,
              let payload = DragTracking.nativePayload(info, store: store),
              store.draggedAppID(payload) != nil, let window,
              info.draggingDestinationWindow === window,
              NSBezierPath(roundedRect: bounds, xRadius: 44, yRadius: 44)
                .contains(convert(info.draggingLocation, from: nil)) else { return false }
        let point = window.convertPoint(toScreen: info.draggingLocation)
        if dropping {
            DragTracking.trace("native-folder.perform", store: store)
            return DragTracking.drop(point, store: store, payload: payload)
        }
        DragTracking.update(point, store: store)
        return store.isPreviewingDrag && store.dragOpenFolderID == folderID
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        receiveNativeDrop(sender, dropping: false) ? .move : []
    }
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        receiveNativeDrop(sender, dropping: false) ? .move : []
    }
    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        receiveNativeDrop(sender, dropping: false)
    }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        receiveNativeDrop(sender, dropping: true)
    }
    override func wantsPeriodicDraggingUpdates() -> Bool { true }

    /// Account for the backing layer's actual anchor point, rather than assuming
    /// an NSView-backed layer is anchored at its centre.
    static func collapsedTransform(source: CGRect, destination: CGRect,
                                   anchor: CGPoint) -> CATransform3D {
        let sx = source.width / max(1, destination.width)
        let sy = source.height / max(1, destination.height)
        let dx = source.midX - destination.midX + (0.5 - anchor.x) * destination.width * (1 - sx)
        let dy = source.midY - destination.midY + (0.5 - anchor.y) * destination.height * (1 - sy)
        return CATransform3DConcat(CATransform3DMakeScale(sx, sy, 1),
                                 CATransform3DMakeTranslation(dx, dy, 0))
    }

    func configure(content: AnyView, size: CGSize, source: CGRect,
                   destination: CGRect, expanded: Bool) {
        contentHost.rootView = content
        let bounds = CGRect(origin: .zero, size: size)
        if glass.frame != bounds {
            glass.frame = bounds
            contentHost.frame = bounds
        }
        guard let layer = glass.layer else { return }
        let reduced = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let collapsed = reduced ? CATransform3DIdentity : Self.collapsedTransform(
            source: source, destination: destination, anchor: layer.anchorPoint)
        let target = expanded ? CATransform3DIdentity : collapsed
        let opacity: Float = expanded ? 1 : 0

        guard let previous = self.expanded else {
            self.expanded = expanded
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            layer.transform = target
            layer.opacity = opacity
            CATransaction.commit()
            return
        }
        guard previous != expanded else { return }
        self.expanded = expanded
        generation += 1
        let ticket = generation
        transitioning = true
        let fromTransform = layer.presentation()?.transform ?? layer.transform
        let fromOpacity = layer.presentation()?.opacity ?? layer.opacity
        layer.removeAllAnimations()

        let transform = CABasicAnimation(keyPath: "transform")
        transform.fromValue = NSValue(caTransform3D: fromTransform)
        transform.toValue = NSValue(caTransform3D: target)
        let fade = CAKeyframeAnimation(keyPath: "opacity")
        fade.values = expanded ? [fromOpacity, Float(1), Float(1)] : [fromOpacity, fromOpacity, Float(0)]
        fade.keyTimes = expanded ? [0, 0.38, 1] : [0, 0.65, 1]
        let group = CAAnimationGroup()
        group.animations = [transform, fade]
        group.duration = reduced ? 0.15 : LaunchpadMotion.folderDuration
        group.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.8, 0.2, 1)

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        CATransaction.setCompletionBlock { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, self.generation == ticket else { return }
                self.transitioning = false
                if !expanded { self.onCollapsed?() }
            }
        }
        layer.transform = target
        layer.opacity = opacity
        layer.add(group, forKey: "folderMorph")
        CATransaction.commit()
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let hit = super.hitTest(point) else { return nil }
        return transitioning || expanded != true ? self : hit
    }
}

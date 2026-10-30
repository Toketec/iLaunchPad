import AppKit
import CoreImage
import SwiftUI

struct WallpaperBackdropView: NSViewRepresentable {
    @AppStorage("wallpaperBlur") private var blur = 24.0
    func makeNSView(context: Context) -> WallpaperBackdropNSView {
        WallpaperBackdropNSView()
    }

    func updateNSView(_ nsView: WallpaperBackdropNSView, context: Context) {
        nsView.updateBlur(blur)
    }
}

final class WallpaperBackdropNSView: NSView {
    private let wallpaperView = AspectFillImageView()
    private let tintView = NSView()
    private let tint = CAGradientLayer()
    private var blurRadius: Double = 24
    private var resourceTask: Task<Void, Never>?
    private var resourceGeneration = 0

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        autoresizesSubviews = true

        wallpaperView.autoresizingMask = [.width, .height]
        wallpaperView.frame = bounds
        addSubview(wallpaperView)

        tintView.wantsLayer = true
        tint.colors = [NSColor.black.withAlphaComponent(0.12).cgColor,
                       NSColor.black.withAlphaComponent(0.07).cgColor,
                       NSColor.black.withAlphaComponent(0.23).cgColor]
        tint.locations = [0, 0.45, 1]
        tintView.layer?.addSublayer(tint)
        tintView.autoresizingMask = [.width, .height]
        tintView.frame = bounds
        addSubview(tintView)
        NotificationCenter.default.addObserver(self, selector: #selector(refreshForPresentation),
                                               name: .launchpadPresented, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(screenChanged(_:)),
                                               name: NSWindow.didChangeScreenNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(screenChanged(_:)),
                                               name: NSWindow.didChangeBackingPropertiesNotification, object: nil)
        reloadWallpaper()
    }

    required init?(coder: NSCoder) { nil }

    deinit { resourceTask?.cancel(); NotificationCenter.default.removeObserver(self) }

    @objc private func refreshForPresentation() { reloadWallpaper() }

    @objc private func screenChanged(_ event: Notification) {
        if (event.object as? NSWindow) === window { reloadWallpaper() }
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        tint.frame = bounds
        CATransaction.commit()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        reloadWallpaper()
    }

    func updateBlur(_ blur: Double) {
        guard blur != blurRadius else { return }
        reloadWallpaper(blur: blur)
    }

    func reloadWallpaper(blur: Double? = nil) {
        if let blur { blurRadius = blur }
        let screen = window?.screen ?? NSScreen.main
        guard let screen,
              let url = NSWorkspace.shared.desktopImageURL(for: screen) else { return }
        resourceGeneration += 1
        let generation = resourceGeneration
        let radius = blurRadius
        let screenKey = "\(screen.frame.size)|\(screen.backingScaleFactor)"
        resourceTask?.cancel()
        resourceTask = Task { [weak self] in
            let image = await VisualResourceCache.shared.wallpaper(url: url, blur: radius, screenKey: screenKey)
            guard let self, !Task.isCancelled, resourceGeneration == generation, let image else { return }
            wallpaperView.sourceURL = url
            wallpaperView.image = NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
            wallpaperView.needsDisplay = true
        }
    }
}

final class AspectFillImageView: NSView {
    var image: NSImage?
    var sourceURL: URL?

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let image else {
            NSColor.windowBackgroundColor.setFill()
            dirtyRect.fill()
            return
        }
        let source = NSRect(origin: .zero, size: image.size)
        let scale = max(bounds.width / image.size.width, bounds.height / image.size.height)
        let destinationSize = NSSize(width: image.size.width * scale, height: image.size.height * scale)
        let destination = NSRect(
            x: (bounds.width - destinationSize.width) / 2,
            y: (bounds.height - destinationSize.height) / 2,
            width: destinationSize.width,
            height: destinationSize.height
        )
        image.draw(in: destination, from: source, operation: .sourceOver, fraction: 1)
    }
}

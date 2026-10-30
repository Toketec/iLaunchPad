import AppKit
import SwiftUI

enum LaunchpadMotion {
    static let page = Animation.interactiveSpring(response: 0.38, dampingFraction: 0.88)
    static let folderDuration = 0.30
    static let folder = Animation.timingCurve(0.2, 0.8, 0.2, 1, duration: folderDuration)
    static let reveal = Animation.smooth(duration: 0.28)
}

struct GridMetrics: Equatable {
    let width: CGFloat
    let height: CGFloat
    var columns: Int = 7
    var rows: Int = 5
    var iconScale: CGFloat = 1
    var showNames = true
    var fixedIconSize: CGFloat? = nil
    var cellWidth: CGFloat { floor(width / CGFloat(columns)) }
    var cellHeight: CGFloat { floor(height / CGFloat(rows)) }
    var iconSize: CGFloat { fixedIconSize.map { min($0, cellWidth - 32, cellHeight - 48) } ?? min(cellHeight - 36, min(cellWidth * 0.75, min(112, max(60, min(cellWidth * 0.62, cellHeight * 0.68))) * iconScale)) }
    var iconTop: CGFloat { max(4, (cellHeight - iconSize - 28) * 0.40) }

    func iconRect(at index: Int) -> CGRect {
        CGRect(x: CGFloat(index % columns) * cellWidth + (cellWidth - iconSize) / 2,
               y: CGFloat(index / columns) * cellHeight + iconTop,
               width: iconSize, height: iconSize)
    }

    /// Only the visible folder glyph accepts an app. The rest of its cell
    /// (including the label and inter-icon spacing) remains a reorder target.
    /// Keep this independent of hover enlargement so the hit area never grows.
    func folderAcceptsDrop(_ point: CGPoint, at index: Int) -> Bool {
        let frame = iconRect(at: index).insetBy(dx: iconSize * 0.09, dy: iconSize * 0.09)
        let radius = frame.width * 0.235
        return NSBezierPath(roundedRect: frame, xRadius: radius, yRadius: radius).contains(point)
    }
}

extension Notification.Name {
    static let launchpadIconReady = Notification.Name("iLaunchPad.iconReady")
}

@MainActor
final class ApplicationIconCache {
    static let shared = ApplicationIconCache()
    private let images = NSCache<NSString, NSImage>()
    private var availability: [String: Bool] = [:]
    private var pending: [String: Task<Void, Never>] = [:]
    private var generation = 0
    private var invalidation: Task<Void, Never>?
    private let placeholder = NSImage(systemSymbolName: "app.dashed", accessibilityDescription: nil) ?? NSImage()
    init() { images.totalCostLimit = 64 * 1024 * 1024 }

    static func key(_ app: LaunchApp) -> String { app.bundleIdentifier + "|" + app.path }

    func clear() {
        generation += 1
        for task in pending.values { task.cancel() }
        pending.removeAll()
        images.removeAllObjects()
        availability.removeAll()
        let previous = invalidation
        invalidation = Task {
            await previous?.value
            await VisualResourceCache.shared.invalidate()
        }
        NotificationCenter.default.post(name: .launchpadIconReady, object: nil)
    }

    func isAvailable(_ app: LaunchApp) -> Bool {
        if let known = availability[Self.key(app)] { return known }
        return app.fileURL.map { FileManager.default.fileExists(atPath: $0.path) } ?? false
    }

    func image(for app: LaunchApp, store: LayoutStore = .shared) -> NSImage {
        let key = Self.key(app)
        if let image = images.object(forKey: key as NSString) { return image }
        request(app)
        return placeholder
    }

    @discardableResult
    private func request(_ app: LaunchApp, revalidate: Bool = false) -> Task<Void, Never>? {
        let key = Self.key(app)
        if let task = pending[key] { return task }
        if !revalidate, images.object(forKey: key as NSString) != nil { return nil }
        let token = generation
        let barrier = invalidation
        let task = Task { [weak self] in
            await barrier?.value
            guard !Task.isCancelled else { return }
            let result = await VisualResourceCache.shared.icon(for: app)
            guard let self, !Task.isCancelled, generation == token else { return }
            availability[key] = result.available
            if let bitmap = result.image {
                let image = NSImage(cgImage: bitmap, size: NSSize(width: 256, height: 256))
                images.setObject(image, forKey: key as NSString, cost: bitmap.bytesPerRow * bitmap.height)
            } else {
                images.setObject(placeholder, forKey: key as NSString)
            }
            pending[key] = nil
            NotificationCenter.default.post(name: .launchpadIconReady, object: key)
        }
        pending[key] = task
        return task
    }

    func warm(_ apps: [LaunchApp], revalidate: Bool = false) async {
        for app in apps {
            guard !Task.isCancelled else { return }
            await request(app, revalidate: revalidate)?.value
        }
    }
}

@MainActor
final class LaunchpadPresentation: ObservableObject {
    static let shared = LaunchpadPresentation()
    @Published var progress: CGFloat = 0
    var pagingEnabled = true
    var closing = false
    var reducedMotion: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
}

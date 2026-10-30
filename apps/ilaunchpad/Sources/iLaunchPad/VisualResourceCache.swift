import AppKit
import CoreImage
import CryptoKit
import ImageIO
import UniformTypeIdentifiers

/// All file IO, NSImage decoding and Core Image work stays on this serial actor.
/// Only immutable, fully rasterized CGImages cross back to the UI actor.
actor VisualResourceCache {
    static let shared = VisualResourceCache()
    struct Icon: Sendable {
        let image: CGImage?
        let available: Bool
    }
    let directory: URL
    let diskLimit: Int
    private let context = CIContext(options: [.cacheIntermediates: false])

    init(directory: URL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("local.ilaunchpad.app/VisualResources/v1", isDirectory: true),
         diskLimit: Int = 128 * 1024 * 1024) {
        self.directory = directory
        self.diskLimit = diskLimit
    }

    static func fingerprint(_ url: URL) -> String {
        var probe = url
        probe.removeAllCachedResourceValues()
        let value = try? probe.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey, .fileResourceIdentifierKey])
        return "\(url.standardizedFileURL.path)|\(value?.contentModificationDate?.timeIntervalSince1970 ?? 0)|\(value?.fileSize ?? 0)|\(String(describing: value?.fileResourceIdentifier))"
    }

    static func digest(_ key: String) -> String {
        SHA256.hash(data: Data(key.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    func invalidate() {
        // Never recursively remove a caller supplied directory or user layout.
        for url in cacheFiles() { try? FileManager.default.removeItem(at: url) }
    }

    func icon(for app: LaunchApp, pixels: Int = 256) -> Icon {
        guard !Task.isCancelled else { return Icon(image: nil, available: false) }
        return autoreleasepool {
            let original = app.fileURL
            let url = original.flatMap { FileManager.default.fileExists(atPath: $0.path) ? $0 : nil }
                ?? NSWorkspace.shared.urlForApplication(withBundleIdentifier: app.bundleIdentifier)
            guard let url else { return Icon(image: nil, available: false) }
            let contents = url.appendingPathComponent("Contents", isDirectory: true)
            let resources = contents.appendingPathComponent("Resources", isDirectory: true)
            let infoURL = contents.appendingPathComponent("Info.plist")
            let info = (try? Data(contentsOf: infoURL)).flatMap {
                try? PropertyListSerialization.propertyList(from: $0, format: nil) as? [String: Any]
            } ?? [:]
            var sourceKeys = [Self.fingerprint(url), Self.fingerprint(infoURL), Self.fingerprint(resources),
                              Self.fingerprint(resources.appendingPathComponent("Assets.car")),
                              Self.fingerprint(url.appendingPathComponent("Icon\r"))]
            if let file = info["CFBundleIconFile"] as? String {
                sourceKeys.append(Self.fingerprint(resources.appendingPathComponent(file)))
                sourceKeys.append(Self.fingerprint(resources.appendingPathComponent(file + ".icns")))
            }
            let key = "icon|v1|\(app.bundleIdentifier)|\(pixels)|dark|\(ProcessInfo.processInfo.operatingSystemVersionString)|\(info["CFBundleVersion"] ?? "")|" + sourceKeys.joined(separator: "|")
            let image = bitmap(key: key) {
                // NSWorkspace is thread-safe. Copy before modifying size: its cached
                // NSImage must not be mutated or concurrently shared with UI views.
                guard let image = NSWorkspace.shared.icon(forFile: url.path).copy() as? NSImage else { return nil }
                image.size = NSSize(width: pixels, height: pixels)
                var rect = CGRect(x: 0, y: 0, width: pixels, height: pixels)
                guard let source = image.cgImage(forProposedRect: &rect, context: nil, hints: nil),
                      let canvas = CGContext(data: nil, width: pixels, height: pixels, bitsPerComponent: 8,
                                             bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                             bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
                canvas.interpolationQuality = .high
                canvas.draw(source, in: rect)
                return canvas.makeImage()
            }
            return Icon(image: image, available: true)
        }
    }

    func wallpaper(url: URL, blur: Double, screenKey: String) -> CGImage? {
        guard !Task.isCancelled else { return nil }
        return autoreleasepool {
            let key = "wallpaper|v1|\(Self.fingerprint(url))|\(blur)|\(screenKey)|\(ProcessInfo.processInfo.operatingSystemVersionString)"
            return bitmap(key: key) {
                guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                      let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                        kCGImageSourceCreateThumbnailFromImageAlways: true,
                        kCGImageSourceThumbnailMaxPixelSize: 1800,
                        kCGImageSourceCreateThumbnailWithTransform: true,
                        kCGImageSourceShouldCacheImmediately: true
                      ] as CFDictionary) else { return nil }
                let image = CIImage(cgImage: thumbnail)
                let blurred = image.clampedToExtent()
                    .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: blur])
                    .cropped(to: image.extent)
                return context.createCGImage(blurred, from: image.extent) ?? thumbnail
            }
        }
    }

    /// Synchronous actor-isolated operation: concurrent identical requests observe
    /// the previous atomic write rather than decoding the source a second time.
    func bitmap(key: String, create: () -> CGImage?) -> CGImage? {
        let url = directory.appendingPathComponent(Self.digest(key) + ".png")
        if FileManager.default.fileExists(atPath: url.path),
           let source = CGImageSourceCreateWithURL(url as CFURL, nil),
           let image = CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary) {
            try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: url.path)
            return image
        }
        guard let image = create() else { return nil }
        let data = NSMutableData()
        if let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) {
            CGImageDestinationAddImage(destination, image, nil)
            if CGImageDestinationFinalize(destination) {
                try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                try? (data as Data).write(to: url, options: .atomic)
                trim()
            }
        }
        return image
    }

    private func cacheFiles() -> [URL] {
        ((try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey])) ?? [])
            .filter { $0.pathExtension == "png" && $0.deletingPathExtension().lastPathComponent.count == 64 }
    }

    private func trim() {
        let files = cacheFiles().map { url in
            (url, try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]))
        }.sorted { ($0.1?.contentModificationDate ?? .distantPast) < ($1.1?.contentModificationDate ?? .distantPast) }
        var bytes = files.reduce(0) { $0 + ($1.1?.fileSize ?? 0) }
        for (url, values) in files where bytes > diskLimit {
            if (try? FileManager.default.removeItem(at: url)) != nil { bytes -= values?.fileSize ?? 0 }
        }
    }
}

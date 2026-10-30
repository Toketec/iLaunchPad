import AppKit
import Testing
@testable import iLaunchPad

struct VisualResourceCacheTests {
    private func bitmap() -> CGImage {
        let context = CGContext(data: nil, width: 32, height: 32, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(red: 0.1, green: 0.4, blue: 0.9, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 32, height: 32))
        return context.makeImage()!
    }

    @Test func diskHitSurvivesNewCacheInstanceAndCorruptionRebuilds() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = VisualResourceCache(directory: directory)
        let image = bitmap()
        let created = await cache.bitmap(key: "fixture") { image }
        #expect(created?.width == 32)
        let reopened = VisualResourceCache(directory: directory)
        let hit = await reopened.bitmap(key: "fixture") { nil }
        #expect(hit?.width == 32)
        let file = directory.appendingPathComponent(VisualResourceCache.digest("fixture") + ".png")
        try Data("bad png".utf8).write(to: file)
        let rebuilt = await reopened.bitmap(key: "fixture") { image }
        #expect(rebuilt?.width == 32)
        let nextHit = await reopened.bitmap(key: "fixture") { nil }
        #expect(nextHit?.height == 32)
    }

    @Test func cacheBudgetAndInvalidationNeverDeleteUnownedFiles() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let unrelated = directory.appendingPathComponent("layout.json")
        try Data("keep".utf8).write(to: unrelated)
        let image = bitmap()
        let cache = VisualResourceCache(directory: directory, diskLimit: 0)
        let result = await cache.bitmap(key: "fixture") { image }
        #expect(result != nil)
        let files = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        #expect(files == ["layout.json"])
        await cache.invalidate()
        #expect(FileManager.default.fileExists(atPath: unrelated.path))
    }

    @Test func samePathChangeInvalidatesFingerprintAndFailedDiskWriteStillRenders() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent("source")
        try Data("one".utf8).write(to: file)
        let first = VisualResourceCache.fingerprint(file)
        try Data("different size".utf8).write(to: file)
        #expect(first != VisualResourceCache.fingerprint(file))
        // A regular file cannot be used as a directory, but rendering still works.
        let cache = VisualResourceCache(directory: file)
        let image = bitmap()
        let result = await cache.bitmap(key: "fixture") { image }
        #expect(result?.width == 32)
    }

    @Test func sourceDecodingDoesNotRunOnMainThread() async {
        let cache = VisualResourceCache(directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        let result = await cache.bitmap(key: "no-write") {
            precondition(!Thread.isMainThread)
            return nil
        }
        #expect(result == nil)
    }
}

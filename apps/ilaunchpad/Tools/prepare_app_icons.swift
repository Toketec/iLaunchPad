import AppKit
import SwiftUI

// Package the generated artwork into the same native continuous-corner mask.
// Raw masters stay intact; the platform mask excludes stray outer alpha pixels.
let source = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let destination = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
for oldIcon in try FileManager.default.contentsOfDirectory(at: destination, includingPropertiesForKeys: nil)
    where oldIcon.pathExtension == "png" {
    try FileManager.default.removeItem(at: oldIcon)
}
for url in try FileManager.default.contentsOfDirectory(at: source, includingPropertiesForKeys: nil)
    where url.pathExtension == "png" {
    guard let input = NSImage(contentsOf: url) else { fatalError("Invalid icon: \(url.path)") }
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1024, pixelsHigh: 1024,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    NSGraphicsContext.current?.imageInterpolation = .high
    // Generated masters already contain the complete glass tile and rim. Crop
    // only their outer preview gutter, then fit that single tile into the
    // standard macOS safe region so it matches neighboring application icons.
    let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
    NSBezierPath(cgPath: RoundedRectangle(cornerRadius: 188, style: .continuous).path(in: tile).cgPath).addClip()
    let crop = CGRect(origin: .zero, size: input.size).insetBy(dx: input.size.width * 0.024, dy: input.size.height * 0.024)
    input.draw(in: tile, from: crop, operation: .copy, fraction: 1)
    NSGraphicsContext.restoreGraphicsState()
    try bitmap.representation(using: .png, properties: [:])!.write(to: destination.appendingPathComponent(url.lastPathComponent))
}

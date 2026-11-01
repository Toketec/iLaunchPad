import AppKit

@MainActor
enum AppIconCatalog {
    static let defaultID = "ocean"

    struct Choice: Identifiable {
        let id: String
        let name: String
    }
    static let choices = [
        Choice(id: "ocean", name: "玻璃蓝"), Choice(id: "violet", name: "玻璃紫"),
        Choice(id: "obsidian", name: "玻璃黑 · 亮底"),
        Choice(id: "porcelain", name: "玻璃白 · 暗底")
    ]

    static func normalizedID(_ id: String?) -> String {
        guard let id, choices.contains(where: { $0.id == id }) else { return defaultID }
        return id
    }

    static func image(for id: String) -> NSImage? {
        let validID = normalizedID(id)
        guard let url = Bundle.main.url(forResource: validID, withExtension: "png", subdirectory: "AppIcons")
            ?? Bundle.main.url(forResource: defaultID, withExtension: "png", subdirectory: "AppIcons") else { return nil }
        return NSImage(contentsOf: url)
    }

    static func apply(_ id: String) {
        let validID = normalizedID(id)
        guard let image = image(for: validID) else { return }
        NSApp.applicationIconImage = image
        ApplicationIconCache.shared.updateRuntimeIcon(
            image,
            bundleIdentifier: Bundle.main.bundleIdentifier ?? "local.ilaunchpad.app"
        )
        persistFinderIcon(image, styleID: validID)
    }

    private static func persistFinderIcon(_ image: NSImage, styleID: String) {
        let bundlePath = Bundle.main.bundlePath
        guard bundlePath.hasSuffix(".app") else { return }
        let workspace = NSWorkspace.shared
        if styleID == defaultID {
            // The signed bundle already ships with the ocean icon. Removing a
            // previous custom file icon restores that default after quitting.
            _ = workspace.setIcon(nil, forFile: bundlePath, options: [])
        } else {
            // NSWorkspace stores a Finder custom icon as file metadata. This
            // survives process exit without rewriting signed bundle resources.
            _ = workspace.setIcon(image, forFile: bundlePath, options: [])
        }
    }
}

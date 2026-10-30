import AppKit

@MainActor
enum AppIconCatalog {
    static let defaultID = "ocean"

    struct Choice: Identifiable {
        let id: String
        let name: String
    }
    static let choices = [
        Choice(id: "ocean", name: "海蓝玻璃"), Choice(id: "violet", name: "紫晶星际"),
        Choice(id: "obsidian", name: "曜石夜航"),
        Choice(id: "porcelain", name: "白瓷石墨")
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
        guard let image = image(for: id) else { return }
        NSApp.applicationIconImage = image
        ApplicationIconCache.shared.updateRuntimeIcon(
            image,
            bundleIdentifier: Bundle.main.bundleIdentifier ?? "local.ilaunchpad.app"
        )
    }
}

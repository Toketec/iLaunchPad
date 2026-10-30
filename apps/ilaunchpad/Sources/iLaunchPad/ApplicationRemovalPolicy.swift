import Foundation

/// Pure path qualification. File movement and user confirmation live in ApplicationRemoval.
enum ApplicationRemovalPolicy {
    static let protectedIdentifiers: Set<String> = [
        "com.apple.Safari", "com.apple.mail", "com.apple.Music", "com.apple.iBooksX",
        "com.apple.Notes", "com.apple.podcasts", "com.apple.Maps", "com.apple.news",
        "com.apple.stocks", "com.apple.systempreferences", "com.apple.finder",
        "com.apple.dock", "com.apple.apps.launcher", "com.apple.AppStore"
    ]

    static var applicationRoots: [URL] {
        [URL(fileURLWithPath: "/Applications"),
         FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications")]
    }

    static func permittedPath(_ url: URL, bundleID: String, ownBundleID: String,
                              applicationRoots: [URL]) -> Bool {
        let normalized = url.standardizedFileURL
        guard url.isFileURL, normalized.pathExtension.lowercased() == "app",
              !bundleID.isEmpty, bundleID != ownBundleID,
              !protectedIdentifiers.contains(bundleID),
              !normalized.deletingLastPathComponent().pathComponents.contains(where: {
                  $0.lowercased().hasSuffix(".app")
              }) else { return false }
        guard !normalized.path.hasPrefix("/System/"), !normalized.path.hasPrefix("/Library/Apple/") else { return false }
        return applicationRoots.contains {
            normalized.path.hasPrefix($0.standardizedFileURL.path + "/")
        }
    }

}

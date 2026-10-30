import Foundation

struct ApplicationScanner {
    private static let worker = ScanWorker()
    static func scanInBackground() async -> [LaunchApp] { await worker.scan() }

    private actor ScanWorker {
        func scan() -> [LaunchApp] {
            guard !Task.isCancelled else { return [] }
            return ApplicationScanner.installedApplications()
        }
    }
    static var roots: [URL] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return [
            URL(fileURLWithPath: "/Applications", isDirectory: true),
            URL(fileURLWithPath: "/System/Applications", isDirectory: true),
            home.appendingPathComponent("Applications", isDirectory: true)
        ]
    }

    static func installedApplications() -> [LaunchApp] {
        var results: [LaunchApp] = []
        var seen = Set<String>()

        for root in roots where FileManager.default.fileExists(atPath: root.path) {
            guard let enumerator = FileManager.default.enumerator(
                at: root,
                includingPropertiesForKeys: [.isDirectoryKey, .isPackageKey],
                options: [.skipsHiddenFiles]
            ) else { continue }

            for case let url as URL in enumerator {
                guard url.pathExtension.lowercased() == "app" else { continue }
                enumerator.skipDescendants()
                guard let bundle = Bundle(url: url),
                      let bundleID = bundle.bundleIdentifier,
                      !bundleID.isEmpty,
                      !seen.contains(bundleID) else { continue }
                seen.insert(bundleID)
                let displayName = (bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
                    ?? (bundle.object(forInfoDictionaryKey: "CFBundleName") as? String)
                    ?? url.deletingPathExtension().lastPathComponent
                results.append(LaunchApp(
                    id: "installed-\(bundleID)",
                    name: displayName,
                    bundleIdentifier: bundleID,
                    path: url.path
                ))
            }
        }
        return results.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}

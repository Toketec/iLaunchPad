import Foundation

enum LaunchNextImportError: LocalizedError {
    case invalidFile
    case emptyLayout

    var errorDescription: String? {
        switch self {
        case .invalidFile: return "这不是受支持的 LaunchNext JSON 布局文件"
        case .emptyLayout: return "LaunchNext 布局中没有可导入的应用"
        }
    }
}

struct LaunchNextImporter {
    static func importLayout(from url: URL) throws -> LaunchLayout {
        let data = try Data(contentsOf: url)
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw LaunchNextImportError.invalidFile
        }
        let entries: [[String: Any]]
        let modern = root["snapshotType"] as? String == "launchNext.layout"
        if modern, let items = root["items"] as? [[String: Any]] { entries = items }
        else if let pages = root["pages"] as? [[String: Any]] { entries = pages }
        else { throw LaunchNextImportError.invalidFile }

        var groupsByPage: [Int: [(position: Int, group: LaunchGroup)]] = [:]
        for (fallbackPosition, entry) in entries.enumerated() {
            let kind = (entry["kind"] as? String) ?? ""
            let page = entry["pageIndex"] as? Int ?? 0
            let position = entry["position"] as? Int ?? fallbackPosition
            if kind == "app" || kind == "应用" {
                guard let app = app(path: entry["path"] as? String, name: entry["name"] as? String) else { continue }
                groupsByPage[page, default: []].append((position, LaunchGroup(
                    id: "launchnext-app-\(app.id)", name: "", isFolder: false, apps: [app]
                )))
            } else if kind == "folder" || kind == "文件夹" {
                let name = entry["name"] as? String ?? ""
                var folderApps: [LaunchApp] = []
                if let apps = entry["apps"] as? [[String: Any]] {
                    folderApps = apps.compactMap { app(path: $0["path"] as? String, name: $0["name"] as? String) }
                } else if let paths = entry["folderAppPaths"] as? [String] {
                    let names = entry["folderApps"] as? [String] ?? []
                    folderApps = paths.enumerated().compactMap { index, path in
                        app(path: path, name: names.indices.contains(index) ? names[index] : nil)
                    }
                }
                guard !folderApps.isEmpty else { continue }
                let folderID = entry["id"] as? String ?? UUID().uuidString
                groupsByPage[page, default: []].append((position, LaunchGroup(
                    id: "launchnext-folder-\(folderID)", name: name, isFolder: true, apps: folderApps
                )))
            }
        }
        let pages = groupsByPage.keys.sorted().map { page in
            LaunchPage(id: "launchnext-page-\(page)", groups: groupsByPage[page, default: []]
                .sorted { $0.position < $1.position }.map(\.group))
        }
        guard !pages.isEmpty else { throw LaunchNextImportError.emptyLayout }
        return LaunchLayout(importedFrom: url.path, importedAt: Date(), pages: pages)
    }

    private static func app(path: String?, name: String?) -> LaunchApp? {
        guard let path, !path.isEmpty, path.hasSuffix(".app") else { return nil }
        let url = URL(fileURLWithPath: path)
        let bundleID = Bundle(url: url)?.bundleIdentifier ?? ""
        let displayName = (name?.isEmpty == false ? name : nil) ?? url.deletingPathExtension().lastPathComponent
        let id = bundleID.isEmpty ? "launchnext-path-\(path)" : bundleID
        return LaunchApp(id: id, name: displayName, bundleIdentifier: bundleID, path: path)
    }
}

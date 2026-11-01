import Foundation
import SQLite3

enum LegacyLaunchpadImportError: LocalizedError {
    case databaseNotFound
    case incompatibleDatabase
    case openFailed(String)
    case queryFailed(String)

    var errorDescription: String? {
        switch self {
        case .databaseNotFound: return "未找到旧版 macOS LaunchPad 布局数据库"
        case .incompatibleDatabase: return "此文件不是受支持的旧版 macOS LaunchPad 布局数据库"
        case .openFailed(let message): return "无法打开旧版 LaunchPad 数据库：\(message)"
        case .queryFailed(let message): return "读取旧版 LaunchPad 布局失败：\(message)"
        }
    }
}

struct LegacyLaunchpadImporter {
    static func nativeDatabaseURL() throws -> URL {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/getconf")
        process.arguments = ["DARWIN_USER_DIR"]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = Pipe()
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0,
              let path = String(data: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines), !path.isEmpty else {
            throw LegacyLaunchpadImportError.databaseNotFound
        }
        return URL(fileURLWithPath: path).appendingPathComponent("com.apple.dock.launchpad/db/db")
    }

    static func importLayout(from url: URL? = nil) throws -> LaunchLayout {
        let sourceURL = try url ?? nativeDatabaseURL()
        guard FileManager.default.fileExists(atPath: sourceURL.path) else {
            throw LegacyLaunchpadImportError.databaseNotFound
        }
        var database: OpaquePointer?
        let result = sqlite3_open_v2(sourceURL.path, &database, SQLITE_OPEN_READONLY, nil)
        guard result == SQLITE_OK, let database else {
            let message = database.map { String(cString: sqlite3_errmsg($0)) } ?? "未知错误"
            if let database { sqlite3_close(database) }
            throw LegacyLaunchpadImportError.openFailed(message)
        }
        defer { sqlite3_close(database) }
        guard ["apps", "groups", "items"].allSatisfy({ tableExists($0, database: database) }) else {
            throw LegacyLaunchpadImportError.incompatibleDatabase
        }

        struct Item { let rowID: Int; let type: Int; let parentID: Int; let order: Int }
        struct App { let name: String; let bundleID: String }
        var apps: [Int: App] = [:]
        var names: [Int: String] = [:]
        var items: [Item] = []

        try read(database, sql: "SELECT item_id, COALESCE(title, ''), COALESCE(bundleid, '') FROM apps") { statement in
            apps[Int(sqlite3_column_int(statement, 0))] = App(name: string(statement, 1), bundleID: string(statement, 2))
        }
        try read(database, sql: "SELECT item_id, COALESCE(title, '') FROM groups") { statement in
            names[Int(sqlite3_column_int(statement, 0))] = string(statement, 1)
        }
        try read(database, sql: "SELECT rowid, type, parent_id, ordering FROM items ORDER BY parent_id, ordering") { statement in
            items.append(Item(rowID: Int(sqlite3_column_int(statement, 0)),
                              type: Int(sqlite3_column_int(statement, 1)),
                              parentID: Int(sqlite3_column_int(statement, 2)),
                              order: Int(sqlite3_column_int(statement, 3))))
        }

        var children: [Int: [Item]] = [:]
        for item in items { children[item.parentID, default: []].append(item) }
        for key in children.keys { children[key]?.sort { $0.order < $1.order } }
        let roots = items.filter { $0.type == 1 }.map(\.rowID)
        let rootIDs = roots.isEmpty ? [1] : roots
        let pageContainers = rootIDs.flatMap { root in
            (children[root] ?? []).filter { $0.type == 3 }.sorted { $0.order < $1.order }
        }

        func launchApp(_ item: Item) -> LaunchApp? {
            guard let source = apps[item.rowID] else { return nil }
            let id = source.bundleID.isEmpty ? "legacy-app-\(item.rowID)" : source.bundleID
            return LaunchApp(id: id, name: source.name, bundleIdentifier: source.bundleID, path: "")
        }

        let pages = pageContainers.enumerated().map { pageIndex, container in
            let groups = (children[container.rowID] ?? []).compactMap { item -> LaunchGroup? in
                if item.type == 4, let app = launchApp(item) {
                    return LaunchGroup(id: "legacy-app-group-\(item.rowID)", name: "", isFolder: false, apps: [app])
                }
                guard item.type == 2 else { return nil }
                let folderApps = (children[item.rowID] ?? [])
                    .filter { $0.type == 3 }
                    .flatMap { children[$0.rowID] ?? [] }
                    .filter { $0.type == 4 }
                    .compactMap(launchApp)
                guard !folderApps.isEmpty else { return nil }
                return LaunchGroup(id: "legacy-folder-\(item.rowID)", name: names[item.rowID] ?? "",
                                   isFolder: true, apps: folderApps)
            }
            return LaunchPage(id: "legacy-page-\(pageIndex)", groups: groups)
        }.filter { !$0.groups.isEmpty }
        guard !pages.isEmpty else { throw LegacyLaunchpadImportError.incompatibleDatabase }
        return LaunchLayout(importedFrom: sourceURL.path, importedAt: Date(), pages: pages)
    }

    private static func tableExists(_ name: String, database: OpaquePointer) -> Bool {
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        guard sqlite3_prepare_v2(database, "SELECT 1 FROM sqlite_master WHERE type='table' AND name=?", -1, &statement, nil) == SQLITE_OK else { return false }
        sqlite3_bind_text(statement, 1, name, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        return sqlite3_step(statement) == SQLITE_ROW
    }

    private static func read(_ database: OpaquePointer, sql: String, row: (OpaquePointer) -> Void) throws {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw LegacyLaunchpadImportError.queryFailed(String(cString: sqlite3_errmsg(database)))
        }
        defer { sqlite3_finalize(statement) }
        while sqlite3_step(statement) == SQLITE_ROW { row(statement) }
        guard sqlite3_errcode(database) == SQLITE_OK || sqlite3_errcode(database) == SQLITE_DONE else {
            throw LegacyLaunchpadImportError.queryFailed(String(cString: sqlite3_errmsg(database)))
        }
    }

    private static func string(_ statement: OpaquePointer, _ column: Int32) -> String {
        sqlite3_column_text(statement, column).map { String(cString: $0) } ?? ""
    }
}

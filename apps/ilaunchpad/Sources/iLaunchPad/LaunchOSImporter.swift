import Foundation
import SQLite3

enum LaunchOSImportError: LocalizedError {
    case databaseNotFound
    case openFailed(String)
    case queryFailed(String)

    var errorDescription: String? {
        switch self {
        case .databaseNotFound: return "未找到 LaunchOS 布局数据库"
        case .openFailed(let message): return "无法打开 LaunchOS 数据库：\(message)"
        case .queryFailed(let message): return "读取 LaunchOS 布局失败：\(message)"
        }
    }
}

struct LaunchOSImporter {
    static var databaseURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/LaunchOS/LaunchOS.sqlite")
    }

    static func importLayout() throws -> LaunchLayout {
        guard FileManager.default.fileExists(atPath: databaseURL.path) else {
            throw LaunchOSImportError.databaseNotFound
        }

        var database: OpaquePointer?
        let openResult = sqlite3_open_v2(databaseURL.path, &database, SQLITE_OPEN_READONLY, nil)
        guard openResult == SQLITE_OK, let database else {
            let message = database.map { String(cString: sqlite3_errmsg($0)) } ?? "未知错误"
            if let database { sqlite3_close(database) }
            throw LaunchOSImportError.openFailed(message)
        }
        defer { sqlite3_close(database) }

        let sql = """
        SELECT
            g.Z_PK, g.ZPAGE, g.ZORDER, g.ZISFOLDER, COALESCE(g.ZNAME, ''),
            a.Z_PK, a.ZORDER, COALESCE(a.ZID, ''), COALESCE(a.ZNAME, ''),
            COALESCE(a.ZBUNDLEID, ''), COALESCE(a.ZURL, ''), COALESCE(a.ZHIDDEN, 0)
        FROM ZGROUPENTITY g
        LEFT JOIN ZAPPENTITY a ON a.ZGROUP = g.Z_PK
        ORDER BY g.ZPAGE ASC, g.ZORDER ASC, a.ZORDER ASC
        """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
              let statement else {
            throw LaunchOSImportError.queryFailed(String(cString: sqlite3_errmsg(database)))
        }
        defer { sqlite3_finalize(statement) }

        struct GroupRow {
            var page: Int
            var order: Int
            var name: String
            var isFolder: Bool
            var apps: [LaunchApp]
        }
        var rows: [Int: GroupRow] = [:]

        while sqlite3_step(statement) == SQLITE_ROW {
            let groupKey = Int(sqlite3_column_int64(statement, 0))
            let page = Int(sqlite3_column_int(statement, 1))
            let groupOrder = Int(sqlite3_column_int(statement, 2))
            let isFolder = sqlite3_column_int(statement, 3) != 0
            let groupName = string(statement, 4)

            if rows[groupKey] == nil {
                rows[groupKey] = GroupRow(page: page, order: groupOrder, name: groupName,
                                          isFolder: isFolder, apps: [])
            }

            guard sqlite3_column_type(statement, 5) != SQLITE_NULL else { continue }
            let appKey = Int(sqlite3_column_int64(statement, 5))
            let appID = string(statement, 7)
            let appName = string(statement, 8)
            let bundleID = string(statement, 9)
            let rawURL = string(statement, 10)
            let hidden = sqlite3_column_int(statement, 11) != 0
            let identifier = appID.isEmpty ? (bundleID.isEmpty ? "launchos-app-\(appKey)" : bundleID) : appID
            rows[groupKey]?.apps.append(LaunchApp(
                id: identifier, name: appName, bundleIdentifier: bundleID,
                path: normalizedPath(rawURL), hidden: hidden
            ))
        }

        let pageNumbers = Set(rows.values.map(\.page)).sorted()
        let pages = pageNumbers.map { pageNumber in
            let groups = rows
                .filter { $0.value.page == pageNumber }
                .sorted { lhs, rhs in
                    lhs.value.order == rhs.value.order ? lhs.key < rhs.key : lhs.value.order < rhs.value.order
                }
                .compactMap { key, row -> LaunchGroup? in
                    guard !row.apps.isEmpty else { return nil }
                    return LaunchGroup(id: "launchos-group-\(key)", name: row.name,
                                       isFolder: row.isFolder, apps: row.apps)
                }
            return LaunchPage(id: "page-\(pageNumber)", groups: groups)
        }

        return LaunchLayout(importedFrom: databaseURL.path, importedAt: Date(),
                            pages: pages.isEmpty ? [LaunchPage(id: UUID().uuidString, groups: [])] : pages)
    }

    private static func string(_ statement: OpaquePointer, _ column: Int32) -> String {
        guard let value = sqlite3_column_text(statement, column) else { return "" }
        return String(cString: value)
    }

    private static func normalizedPath(_ rawValue: String) -> String {
        guard rawValue.hasPrefix("file://"), let url = URL(string: rawValue) else { return rawValue }
        return url.path
    }
}

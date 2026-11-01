import Foundation
import SQLite3
import Testing
@testable import iLaunchPad

@Suite(.serialized)
struct LayoutImporterTests {
    @Test func importsLaunchNextSnapshotPagesAndFolders() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("launchnext-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let object: [String: Any] = [
            "snapshotType": "launchNext.layout",
            "items": [
                ["kind": "app", "pageIndex": 0, "position": 1, "name": "Second", "path": "/Applications/Second.app"],
                ["kind": "folder", "pageIndex": 0, "position": 0, "id": "work", "name": "Work", "apps": [
                    ["index": 0, "name": "Editor", "path": "/Applications/Editor.app"],
                    ["index": 1, "name": "Notes", "path": "/Applications/Notes.app"]
                ]],
                ["kind": "app", "pageIndex": 1, "position": 0, "name": "Third", "path": "/Applications/Third.app"]
            ]
        ]
        try JSONSerialization.data(withJSONObject: object).write(to: url)

        let layout = try LaunchNextImporter.importLayout(from: url)
        #expect(layout.pages.count == 2)
        #expect(layout.pages[0].groups.map(\.displayName) == ["Work", "Second"])
        #expect(layout.pages[0].groups[0].apps.map(\.name) == ["Editor", "Notes"])
        #expect(layout.pages[1].groups.first?.displayName == "Third")
    }

    @Test func importsLegacyLaunchpadReadOnlyHierarchy() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("launchpad-\(UUID().uuidString).db")
        defer { try? FileManager.default.removeItem(at: url) }
        var database: OpaquePointer?
        #expect(sqlite3_open(url.path, &database) == SQLITE_OK)
        guard let database else { return }
        let sql = """
        CREATE TABLE apps (item_id INTEGER, title TEXT, bundleid TEXT, storeid TEXT);
        CREATE TABLE groups (item_id INTEGER, title TEXT);
        CREATE TABLE items (uuid TEXT, flags INTEGER, type INTEGER, parent_id INTEGER, ordering INTEGER);
        INSERT INTO items(rowid,type,parent_id,ordering) VALUES (1,1,0,0),(10,3,1,0),(20,4,10,0),(30,2,10,1),(40,3,30,0),(21,4,40,0),(22,4,40,1);
        INSERT INTO apps VALUES (20,'Safari','com.apple.Safari',''),(21,'Notes','com.apple.Notes',''),(22,'Maps','com.apple.Maps','');
        INSERT INTO groups VALUES (30,'Apple');
        """
        #expect(sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK)
        sqlite3_close(database)

        let layout = try LegacyLaunchpadImporter.importLayout(from: url)
        #expect(layout.pages.count == 1)
        #expect(layout.pages[0].groups.count == 2)
        #expect(layout.pages[0].groups[0].apps.first?.bundleIdentifier == "com.apple.Safari")
        #expect(layout.pages[0].groups[1].name == "Apple")
        #expect(layout.pages[0].groups[1].apps.map(\.name) == ["Notes", "Maps"])
    }
}

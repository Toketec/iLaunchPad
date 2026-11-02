import Foundation
import Testing
@testable import iLaunchPad

@Suite(.serialized)
struct LayoutBackupTests {
    @Test func appleDefaultKeepsSystemOrderAndPlacesRemainingOnSecondPage() {
        let apps = [
            app("third", bundleID: "example.third", name: "Third"),
            app("safari", bundleID: "com.apple.Safari", name: "Safari"),
            app("terminal", bundleID: "com.apple.Terminal", name: "Terminal"),
            app("store", bundleID: "com.apple.AppStore", name: "App Store")
        ]
        let layout = AppleDefaultLayoutFactory.make(from: apps)
        #expect(layout.pages.count == 2)
        #expect(layout.pages[0].groups[0].apps[0].bundleIdentifier == "com.apple.Safari")
        #expect(layout.pages[0].groups[1].apps[0].bundleIdentifier == "com.apple.AppStore")
        #expect(layout.pages[0].groups[2].isFolder)
        #expect(layout.pages[0].groups[2].apps[0].bundleIdentifier == "com.apple.Terminal")
        #expect(layout.pages[1].groups[0].apps[0].bundleIdentifier == "example.third")
    }

    @Test func reconciliationRemovesMissingUpdatesMetadataAndAppendsNewApps() {
        let missing = app("missing", bundleID: "test.missing", name: "Missing")
        let old = LaunchApp(id: "stable", name: "Old", bundleIdentifier: "test.keep",
                            path: "/Applications/Old.app", hidden: true)
        let source = LaunchLayout(pages: [
            LaunchPage(id: "page", groups: [
                LaunchGroup(id: "folder", name: "Tools", isFolder: true, apps: [missing, old])
            ])
        ])
        let current = app("new-path", bundleID: "test.keep", name: "Current")
        let added = app("added", bundleID: "test.added", name: "Added")
        let result = InstalledApplicationReconciler.reconcile(source, with: [current, added])
        #expect(result.pages.count == 1)
        #expect(result.pages[0].groups.count == 2)
        #expect(!result.pages[0].groups[0].isFolder)
        #expect(result.pages[0].groups[0].apps[0].id == "stable")
        #expect(result.pages[0].groups[0].apps[0].name == "Current")
        #expect(result.pages[0].groups[0].apps[0].hidden)
        #expect(result.pages[0].groups[1].apps[0].bundleIdentifier == "test.added")
    }

    @Test func repositoryPersistsThreeSnapshotsAndRejectsFourth() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("layout-backups.json")
        let layout = LaunchLayout(pages: [LaunchPage(id: "page", groups: [])])
        let repository = LayoutBackupRepository(fileURL: url)
        try repository.create(name: "One", layout: layout)
        try repository.create(name: "Two", layout: layout)
        try repository.create(name: "Three", layout: layout)
        var rejectedFourth = false
        do { try repository.create(name: "Four", layout: layout) }
        catch LayoutBackupError.limitReached { rejectedFourth = true }
        #expect(rejectedFourth)
        let reloaded = LayoutBackupRepository(fileURL: url)
        #expect(reloaded.summaries.map(\.name) == ["One", "Two", "Three"])
    }

    private func app(_ id: String, bundleID: String, name: String) -> LaunchApp {
        LaunchApp(id: id, name: name, bundleIdentifier: bundleID, path: "/Applications/\(id).app")
    }
}

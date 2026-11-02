import AppKit
import Testing
@testable import iLaunchPad

@Suite(.serialized)
@MainActor
struct ApplicationDiscoveryTests {
    @Test func fillsEarliestPageWithoutMovingExistingApps() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let pages = [34, 34, 2].enumerated().map { page, count in
            LaunchPage(id: "page-\(page)", groups: (0..<count).map { slot in
                let id = "\(page)-\(slot)"
                return LaunchGroup(id: id, name: "", isFolder: false, apps: [app(id)])
            })
        }
        let store = LayoutStore(layout: LaunchLayout(pages: pages), storageURL: directory.appendingPathComponent("layout.json"))
        let installed = pages.flatMap(\.groups).flatMap(\.apps)
            + [app("new-a"), app("new-b"), app("new-c"), app("new-a")]
        store.receiveScannedApplications(installed, generation: store.scanGeneration)
        #expect(store.layout.pages.map { $0.groups.count } == [35, 35, 3])
        #expect(store.layout.pages[0].groups.last?.apps.first?.id == "new-a")
        #expect(store.layout.pages[1].groups.last?.apps.first?.id == "new-b")
        #expect(store.layout.pages[2].groups.last?.apps.first?.id == "new-c")
        for index in pages.indices {
            #expect(Array(store.layout.pages[index].groups.prefix(pages[index].groups.count)) == pages[index].groups)
        }
        let persisted = try JSONDecoder().decode(LaunchLayout.self, from: Data(contentsOf: directory.appendingPathComponent("layout.json")))
        #expect(persisted.pages.map { $0.groups.count } == [35, 35, 3])
    }

    @Test func emptyAndFullPagePolicy() {
        #expect(ApplicationDiscoveryPolicy.insertionPage(groupCounts: []) == 0)
        #expect(ApplicationDiscoveryPolicy.insertionPage(groupCounts: [35, 35]) == 2)
        #expect(ApplicationDiscoveryPolicy.insertionPage(groupCounts: [35, 0, 35]) == 1)
        #expect(ApplicationDiscoveryPolicy.insertionPage(groupCounts: [36, 34]) == 1)
    }

    @Test func homepageDefaultDoesNotOverwriteExplicitChoice() {
        let suite = "iLaunchPad-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.register(defaults: ["returnToFirstPage": true])
        #expect(defaults.bool(forKey: "returnToFirstPage"))
        defaults.set(false, forKey: "returnToFirstPage")
        defaults.register(defaults: ["returnToFirstPage": true])
        #expect(!defaults.bool(forKey: "returnToFirstPage"))
    }

    @Test func nativeDirectoryEventsDetectNestedInstallation() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        var calls = 0
        let monitor = ApplicationDirectoryMonitor(roots: [root]) { calls += 1 }
        defer {
            monitor.stop()
            try? FileManager.default.removeItem(at: root)
        }
        let destination = root.appendingPathComponent("Vendor/New.app/Contents")
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        let data = try PropertyListSerialization.data(fromPropertyList: ["CFBundleIdentifier": "test.new"], format: .xml, options: 0)
        try data.write(to: destination.appendingPathComponent("Info.plist"))
        for _ in 0..<40 {
            if calls > 0 { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        #expect(calls > 0)
        monitor.stop()
        let stoppedCalls = calls
        try data.write(to: destination.appendingPathComponent("Info.plist"))
        try await Task.sleep(for: .seconds(2))
        #expect(calls == stoppedCalls)
    }

    private func app(_ id: String) -> LaunchApp {
        LaunchApp(id: id, name: id, bundleIdentifier: "test." + id, path: "/Applications/" + id + ".app")
    }
}

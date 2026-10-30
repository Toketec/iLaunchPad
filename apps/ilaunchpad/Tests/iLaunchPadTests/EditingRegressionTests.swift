import Foundation
import Testing
@testable import iLaunchPad

@Suite(.serialized)
@MainActor
struct EditingRegressionTests {
    @Test func backgroundScanWaitsForDragAndMergesLatestCommittedOrder() {
        let (store, directory) = fixture()
        defer { try? FileManager.default.removeItem(at: directory) }
        let added = LaunchApp(id: "new", name: "new", bundleIdentifier: "test.new", path: "/Applications/new.app")
        store.beginDragPreview()
        store.moveGroup("a", relativeTo: "c", side: .after)
        store.receiveScannedApplications([added, added], generation: store.scanGeneration)
        #expect(store.allApps().count == 3)
        store.finishDragPreview(commit: true)
        #expect(store.groups(on: 0).prefix(3).map(\.id) == ["b", "c", "a"])
        #expect(store.allApps().filter { $0.id == "new" }.count == 1)
    }

    @Test func cancelledDragDoesNotDiscardPendingScanAndStaleScanIsRejected() {
        let (store, directory) = fixture()
        defer { try? FileManager.default.removeItem(at: directory) }
        let added = LaunchApp(id: "new", name: "new", bundleIdentifier: "test.new", path: "/Applications/new.app")
        store.receiveScannedApplications([added], generation: UUID())
        #expect(store.allApps().count == 3)
        store.beginDragPreview()
        store.moveGroup("a", relativeTo: "c", side: .after)
        store.receiveScannedApplications([added], generation: store.scanGeneration)
        store.finishDragPreview(commit: false)
        #expect(store.groups(on: 0).prefix(3).map(\.id) == ["a", "b", "c"])
        #expect(store.allApps().count == 4)
        store.receiveScannedApplications([added], generation: store.scanGeneration)
        #expect(store.allApps().count == 4)
    }

    func fixture() -> (LayoutStore, URL) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let groups = ["a", "b", "c"].map { id in
            LaunchGroup(id: id, name: "", isFolder: false,
                        apps: [LaunchApp(id: id, name: id, bundleIdentifier: "test." + id, path: "/Applications/" + id + ".app")])
        }
        return (LayoutStore(layout: LaunchLayout(pages: [LaunchPage(id: "page", groups: groups)]),
                            storageURL: directory.appendingPathComponent("layout.json")), directory)
    }

    @Test func liveReorderingDoesNotPersistAndCancellationRestoresOrder() {
        let (store, directory) = fixture()
        store.beginDragPreview()
        store.moveGroup("a", relativeTo: "c", side: .after)
        #expect(store.groups(on: 0).map(\.id) == ["b", "c", "a"])
        #expect(!FileManager.default.fileExists(atPath: directory.path))
        store.finishDragPreview(commit: false)
        #expect(store.groups(on: 0).map(\.id) == ["a", "b", "c"])
        #expect(!FileManager.default.fileExists(atPath: directory.path))
    }

    @Test func releasingPersistsPreviewAndLaterCancelCannotUndoIt() throws {
        let (store, directory) = fixture()
        defer { try? FileManager.default.removeItem(at: directory) }
        store.beginDragPreview()
        store.moveGroup("c", relativeTo: "a", side: .before)
        store.finishDragPreview(commit: true)
        store.finishDragPreview(commit: false)
        let data = try Data(contentsOf: directory.appendingPathComponent("layout.json"))
        let saved = try JSONDecoder().decode(LaunchLayout.self, from: data)
        #expect(saved.pages[0].groups.map(\.id) == ["c", "a", "b"])
        #expect(store.groups(on: 0).map(\.id) == ["c", "a", "b"])
    }

    @Test func mergePreviewAndFolderReorderingAreReversible() {
        let (store, directory) = fixture()
        store.beginDragPreview()
        store.dropGroup("b", into: "a")
        let folder = store.groups(on: 0)[0]
        #expect(folder.isFolder)
        store.moveAppInsideFolder("b", folderID: folder.id, relativeTo: "a", side: .before)
        #expect(store.group(id: folder.id)?.apps.map(\.id) == ["b", "a"])
        store.finishDragPreview(commit: false)
        #expect(store.groups(on: 0).map(\.id) == ["a", "b", "c"])
        #expect(!FileManager.default.fileExists(atPath: directory.path))
    }

    @Test func pagePreviewKeepsPageIdentityUntilCommit() {
        let (store, _) = fixture()
        store.beginDragPreview()
        for id in ["a", "b", "c"] { store.moveGroup(id, toPage: 1) }
        #expect(store.pageCount == 2)
        #expect(store.layout.pages[0].id == "page")
        store.finishDragPreview(commit: false)
        #expect(store.pageCount == 1)
        #expect(store.groups(on: 0).map(\.id) == ["a", "b", "c"])
    }

    @Test func uninstallPolicyRejectsSystemSelfHelpersAndLookalikeRoots() {
        func allowed(_ path: String, _ id: String = "vendor.app") -> Bool {
            ApplicationRemoval.permittedPath(URL(fileURLWithPath: path), bundleID: id,
                                             ownBundleID: "local.ilaunchpad.app",
                                             applicationRoots: [URL(fileURLWithPath: "/Applications")])
        }
        #expect(allowed("/Applications/Example.app"))
        #expect(allowed("/Applications/Tools/Example.app"))
        #expect(!allowed("/System/Applications/Example.app"))
        #expect(!allowed("/Applications-other/Example.app"))
        #expect(!allowed("/Applications/Main.app/Contents/Helpers/Helper.app"))
        #expect(!allowed("/Applications/iLaunchPad.app", "local.ilaunchpad.app"))
        #expect(!allowed("/Applications/Safari.app", "com.apple.Safari"))
        #expect(!allowed("/Applications/Example.app", ""))
        #expect(!allowed("/Applications/../System/Example.app"))
    }

    @Test func dragCanEnterReorderLeaveAndReenterFolderWithoutSaving() throws {
        let (store, directory) = fixture()
        defer { try? FileManager.default.removeItem(at: directory) }
        store.dropGroup("b", into: "a")
        let folderID = store.groups(on: 0)[0].id
        let before = try Data(contentsOf: directory.appendingPathComponent("layout.json"))
        store.beginDragPreview()
        let payload = DragPayload.group("c")
        store.previewMove(payload, intoFolder: folderID)
        #expect(store.group(id: "c") == nil)
        #expect(store.allApps().filter { $0.id == "c" }.count == 1)
        store.moveAppInsideFolder("c", folderID: folderID, relativeTo: "a", side: .before)
        #expect(store.group(id: folderID)?.apps.map(\.id) == ["c", "a", "b"])
        #expect(store.allApps().filter { $0.id == "c" }.count == 1)
        #expect(store.previewMoveToPage(payload, page: 0) == "c")
        store.moveGroup("c", relativeTo: folderID, side: .before)
        #expect(store.groups(on: 0).map(\.id) == ["c", folderID])
        #expect(store.allApps().filter { $0.id == "c" }.count == 1)
        store.previewMove(payload, intoFolder: folderID)
        #expect(store.allApps().filter { $0.id == "c" }.count == 1)
        #expect(try Data(contentsOf: directory.appendingPathComponent("layout.json")) == before)
        store.finishDragPreview(commit: false)
        #expect(store.groups(on: 0).map(\.id) == [folderID, "c"])
        #expect(store.group(id: folderID)?.apps.map(\.id) == ["a", "b"])
    }

    @Test func folderOriginCanMoveToAnotherFolderAndCommitOnlyOnce() throws {
        let (store, directory) = fixture()
        defer { try? FileManager.default.removeItem(at: directory) }
        store.dropGroup("b", into: "a")
        let folderID = store.groups(on: 0)[0].id
        store.beginDragPreview()
        let payload = DragPayload.folderApp(appID: "a", folderID: folderID)
        let external = try #require(store.previewMoveToPage(payload, page: 0))
        #expect(store.group(id: folderID)?.apps.map(\.id) == ["b"])
        #expect(store.group(id: folderID)?.isFolder == false)
        store.dropGroup(external, into: "c")
        let second = try #require(store.groups(on: 0).first { $0.id != folderID })
        store.previewMove(payload, intoFolder: folderID)
        store.previewMove(payload, intoFolder: second.id)
        store.finishDragPreview(commit: true)
        store.finishDragPreview(commit: false)
        #expect(store.group(id: second.id)?.apps.map(\.id) == ["c", "a"])
        #expect(store.allApps().count == 3)
    }

    @Test func temporaryMergeReordersCommitsAndRequestsNamingOnlyOnce() throws {
        let (store, directory) = fixture()
        defer { try? FileManager.default.removeItem(at: directory) }
        store.beginDragPreview()
        let payload = DragPayload.group("c")
        let session = store.dragSessionID
        store.registerDragAppearance(payload, sessionID: session)
        let folder = try #require(store.beginMergePreview(payload, targetGroupID: "b"))
        #expect(store.dragSessionID == session)
        #expect(store.group(id: folder)?.apps.map(\.id) == ["b", "c"])
        #expect(store.suppressesDragContent(appID: "c"))
        #expect(store.folderNamingRequest == nil)
        store.moveAppInsideFolder("c", folderID: folder, relativeTo: "b", side: .before)
        #expect(store.group(id: folder)?.isFolder == true)
        #expect(store.allApps().count == 3)
        #expect(!FileManager.default.fileExists(atPath: directory.path))
        store.dragDestination = .folder(folder)
        store.finishDragPreview(commit: true)
        #expect(store.group(id: folder)?.apps.map(\.id) == ["c", "b"])
        let request = try #require(store.folderNamingRequest)
        #expect(request.folderID == folder)
        store.finishDragPreview(commit: false)
        #expect(store.consumeFolderNamingRequest(request))
        #expect(!store.consumeFolderNamingRequest(request))
        #expect(!store.suppressesDragContent(appID: "c"))
        #expect(FileManager.default.fileExists(atPath: directory.appendingPathComponent("layout.json").path))
    }

    @Test func leavingTemporaryMergePreservesEarlierPreviewButCancelRestoresStart() throws {
        let (store, directory) = fixture()
        store.beginDragPreview()
        store.moveGroup("c", relativeTo: "a", side: .before)
        let payload = DragPayload.group("c")
        let folder = try #require(store.beginMergePreview(payload, targetGroupID: "b"))
        store.moveAppInsideFolder("c", folderID: folder, relativeTo: "b", side: .before)
        #expect(store.previewMoveToPage(payload, page: 0) == "c")
        #expect(store.temporaryFolderID == nil)
        #expect(store.groups(on: 0).map(\.id) == ["c", "a", "b"])
        #expect(store.group(id: "b")?.isFolder == false)
        #expect(store.beginMergePreview(payload, targetGroupID: "b") != nil)
        store.previewMoveToPage(payload, page: 0)
        store.moveGroup("c", toPage: 1)
        store.finishDragPreview(commit: false)
        #expect(store.pageCount == 1)
        #expect(store.groups(on: 0).map(\.id) == ["a", "b", "c"])
        #expect(store.folderNamingRequest == nil)
        #expect(!FileManager.default.fileExists(atPath: directory.path))
    }

    @Test func temporaryMergeExitCanJoinExistingFolderWithoutNaming() throws {
        let (store, directory) = fixture()
        defer { try? FileManager.default.removeItem(at: directory) }
        store.dropGroup("b", into: "a")
        let original = store.groups(on: 0)[0].id
        store.beginDragPreview()
        let payload = DragPayload.folderApp(appID: "a", folderID: original)
        let folder = try #require(store.beginMergePreview(payload, targetGroupID: "c"))
        #expect(store.group(id: original)?.isFolder == false)
        // Discard restores the source folder before moving to the current destination.
        store.previewMove(payload, intoFolder: original)
        #expect(store.group(id: folder) == nil)
        #expect(store.group(id: original)?.apps.map(\.id) == ["a", "b"])
        store.dragDestination = .folder(original)
        store.finishDragPreview(commit: true)
        #expect(store.folderNamingRequest == nil)
        #expect(store.allApps().count == 3)
    }

    @Test func singletonCleanupMatchesDragMenuAndUninstallButNotHiddenOrReorder() throws {
        for mode in 0..<3 {
            let (store, directory) = fixture()
            defer { try? FileManager.default.removeItem(at: directory) }
            store.dropGroup("b", into: "a")
            let folder = store.groups(on: 0)[0].id
            let app = try #require(store.group(id: folder)?.apps.first)
            if mode == 0 {
                store.beginDragPreview()
                store.moveAppInsideFolder("a", folderID: folder, relativeTo: "b", side: .after)
                #expect(store.group(id: folder)?.isFolder == true)
                store.previewMoveToPage(.folderApp(appID: "a", folderID: folder), page: 0)
            } else if mode == 1 {
                store.removeFromFolder("a", folderID: folder, toPage: 0)
            } else { store.removeUninstalledApplication(app) }
            #expect(store.groups(on: 0).first?.id == folder)
            #expect(store.group(id: folder)?.isFolder == false)
            #expect(store.group(id: folder)?.apps.map(\.id) == ["b"])
            if mode == 0 {
                store.finishDragPreview(commit: false)
                #expect(store.group(id: folder)?.isFolder == true)
                #expect(store.group(id: folder)?.apps.map(\.id) == ["a", "b"])
            }
        }
    }

    @Test func temporaryMergeRejectsNestedAndStaleRequests() throws {
        let (store, directory) = fixture()
        defer { try? FileManager.default.removeItem(at: directory) }
        #expect(store.beginMergePreview(.group("a"), targetGroupID: "b") == nil)
        store.beginDragPreview()
        #expect(store.beginMergePreview(.group("a"), targetGroupID: "a") == nil)
        let id = try #require(store.beginMergePreview(.group("a"), targetGroupID: "b"))
        #expect(store.beginMergePreview(.group("a"), targetGroupID: "c") == nil)
        store.dragDestination = .folder(id)
        store.finishDragPreview(commit: true)
        let request = try #require(store.folderNamingRequest)
        store.cancelFolderNamingRequest(folderID: id)
        #expect(!store.consumeFolderNamingRequest(request))
        store.beginDragPreview()
        #expect(!store.consumeFolderNamingRequest(request))
        #expect(store.beginMergePreview(.group(id), targetGroupID: "c") == nil)
        store.finishDragPreview(commit: false)
    }
}

import AppKit
import SwiftUI
import Testing
@testable import iLaunchPad

@Suite(.serialized) @MainActor
struct DragTrackingTests {
    @Test func displayPollingCoalescesDuplicateNativePointButNeverFinalDrop() {
        let (store, _) = EditingRegressionTests().fixture()
        store.beginDragPreview()
        let point = CGPoint(x: 321, y: 654)
        DragTracking.update(point, store: store)
        store.dragDestination = .page(42)
        DragTracking.updateFromDisplay(point, store: store, maximumFPS: 1)
        #expect(store.dragDestination == .page(42))
        DragTracking.update(point, store: store)
        #expect(store.dragDestination == .page(42))
        DragTracking.update(point, store: store, dropping: true)
        #expect(store.dragDestination == nil)
        store.dragDestination = .page(42)
        DragTracking.updateFromDisplay(CGPoint(x: 322, y: 654), store: store, maximumFPS: 1)
        #expect(store.dragDestination == nil)
        store.finishDragPreview(commit: false)
        store.beginDragPreview()
        store.dragDestination = .page(42)
        DragTracking.updateFromDisplay(CGPoint(x: 322, y: 654), store: store, maximumFPS: 1)
        #expect(store.dragDestination == nil)
        store.finishDragPreview(commit: false)
    }

    @Test func committedFolderNameUsesNativeEditorAndSelectsDefault() throws {
        let (store, directory) = EditingRegressionTests().fixture()
        defer { try? FileManager.default.removeItem(at: directory) }
        store.beginDragPreview()
        let folder = try #require(store.beginMergePreview(.group("c"), targetGroupID: "a"))
        let window = NSWindow(contentRect: CGRect(x: 100, y: 100, width: 400, height: 100),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        window.contentView = NSHostingView(rootView: FolderNameTestHost(store: store, folderID: folder))
        window.makeKeyAndOrderFront(nil)
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        #expect(store.folderNamingRequest == nil)
        store.dragDestination = .folder(folder)
        store.finishDragPreview(commit: true)
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        let editor = try #require(window.firstResponder as? NSTextView)
        #expect(editor.string == "未命名")
        #expect(editor.selectedRange() == NSRange(location: 0, length: 3))
        #expect(store.folderNamingRequest == nil)
        editor.doCommand(by: #selector(NSResponder.cancelOperation(_:)))
        #expect(!(window.firstResponder is NSTextView))
        #expect(store.group(id: folder)?.isFolder == true)
    }
    @Test func temporaryFolderUsesRetainedPageReceiverAndNamesAfterCommit() throws {
        let (store, directory) = EditingRegressionTests().fixture()
        defer { try? FileManager.default.removeItem(at: directory) }
        store.beginDragPreview()
        let folder = try #require(store.beginMergePreview(.group("c"), targetGroupID: "a"))
        store.dragOpenFolderID = folder
        store.dragLifetime = NativeDropTestOwner(store: store, payload: .group("c"))
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 500, height: 300),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        let root = NSView(frame: CGRect(x: 0, y: 0, width: 500, height: 300))
        window.contentView = root
        let collection = LaunchpadCollectionView(frame: root.bounds)
        root.addSubview(collection)
        let coordinator = NativeLaunchGrid.Coordinator(store: store, dragging: .constant(.group("c")),
                                                      onOpenFolder: { _ in }, onOpenApp: { _ in })
        coordinator.collectionView = collection // AppKit still calls the page, not the new folder.
        collection.nativeDrop = { coordinator.receiveNativeDrop($0, dropping: $1) }
        let surface = NativeFolderMorphView(frame: CGRect(x: 40, y: 40, width: 420, height: 220))
        surface.dropStore = store; surface.dropFolderID = folder
        surface.configure(content: AnyView(EmptyView()), size: surface.bounds.size, source: .zero,
                          destination: surface.bounds, expanded: true)
        root.addSubview(surface)
        let boundary = FolderDragBoundary.BoundaryView(frame: surface.bounds)
        boundary.panel = surface.bounds; boundary.active = true; boundary.folderID = folder
        surface.addSubview(boundary)
        let info = NativeDropTestInfo(window: window, token: "c")
        info.draggingLocation = CGPoint(x: 10, y: 150)
        #expect(!collection.performDragOperation(info)) // Outside actual panel, even with an open folder.
        info.draggingLocation = CGPoint(x: 70, y: 150)
        info.draggingSequenceNumber = 99
        #expect(!collection.prepareForDragOperation(info))
        info.draggingSequenceNumber = 17
        #expect(collection.draggingEntered(info) == .move)
        store.previewMove(.group("c"), intoFolder: folder)
        store.moveAppInsideFolder("c", folderID: folder, relativeTo: "a", side: .before)
        #expect(collection.draggingUpdated(info) == .move)
        #expect(collection.prepareForDragOperation(info))
        #expect(collection.performDragOperation(info))
        #expect(!collection.performDragOperation(info))
        store.finishDragPreview(commit: false)
        #expect(store.group(id: folder)?.apps.first?.id == "c")
        #expect(store.allApps().filter { $0.id == "c" }.count == 1)
        #expect(store.folderNamingRequest?.folderID == folder)
    }


    @Test func appCentreDwellBlocksReorderThenCreatesAndOpensPreview() throws {
        for quickRelease in [false, true] {
            let (store, _) = EditingRegressionTests().fixture()
            store.beginDragPreview()
            let payload = DragPayload.group("c")
            let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 600, height: 300),
                                  styleMask: [.borderless], backing: .buffered, defer: false)
            let collection = LaunchpadCollectionView(frame: CGRect(x: 0, y: 0, width: 600, height: 300))
            window.contentView = collection
            var opened: String?
            let coordinator = NativeLaunchGrid.Coordinator(store: store, dragging: .constant(payload),
                onOpenFolder: { id in opened = id; store.dragOpenFolderID = id }, onOpenApp: { _ in })
            coordinator.collectionView = collection
            coordinator.metrics = GridMetrics(width: 600, height: 300, columns: 3, rows: 1)
            let icon = coordinator.metrics.iconRect(at: 0)
            let screen = window.convertPoint(toScreen: collection.convert(CGPoint(x: icon.midX, y: icon.midY), to: nil))
            func move(_ time: Double, dropping: Bool = false) {
                NotificationCenter.default.post(name: .launchpadDragMoved, object: store,
                    userInfo: ["point": NSValue(point: screen), "time": time, "dropping": dropping])
            }
            move(1)
            move(1.2)
            #expect(store.groups(on: 0).map(\.id) == ["a", "b", "c"])
            #expect(coordinator.mergeTargetID == "a")
            #expect(opened == nil)
            if quickRelease {
                move(1.3, dropping: true)
                #expect(store.temporaryFolderID == nil)
                #expect(store.groups(on: 0).map(\.id) == ["c", "a", "b"])
            } else {
                move(1.81)
                #expect(opened == store.temporaryFolderID)
                let id = try #require(opened)
                #expect(store.group(id: id)?.apps.map(\.id) == ["a", "c"])
                #expect(store.mergePreviewSourceFrame == icon)
                #expect(store.folderNamingRequest == nil)
                // Leaving and approaching the same App must arm a fresh dwell.
                store.previewMoveToPage(payload, page: 0)
                store.dragOpenFolderID = nil
                opened = nil
                move(2)
                #expect(opened == nil)
                move(2.81)
                #expect(opened != nil)
            }
            store.finishDragPreview(commit: false)
            #expect(store.groups(on: 0).map(\.id) == ["a", "b", "c"])
        }
    }

    @Test func retainedPageReceiverForwardsOnlyInsideCurrentExpandedFolder() throws {
        let (store, directory) = EditingRegressionTests().fixture()
        defer { try? FileManager.default.removeItem(at: directory) }
        store.dropGroup("b", into: "a")
        let folder = store.groups(on: 0)[0].id
        store.beginDragPreview()
        store.dragOpenFolderID = folder
        store.dragLifetime = NativeDropTestOwner(store: store, payload: .group("c"))
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 500, height: 300),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        let root = NSView(frame: CGRect(x: 0, y: 0, width: 500, height: 300))
        window.contentView = root
        let collection = LaunchpadCollectionView(frame: root.bounds)
        root.addSubview(collection)
        let coordinator = NativeLaunchGrid.Coordinator(store: store, dragging: .constant(.group("c")),
                                                      onOpenFolder: { _ in }, onOpenApp: { _ in })
        coordinator.collectionView = collection // AppKit still calls the page, not the new folder.
        collection.nativeDrop = { coordinator.receiveNativeDrop($0, dropping: $1) }
        let surface = NativeFolderMorphView(frame: CGRect(x: 40, y: 40, width: 420, height: 220))
        surface.dropStore = store; surface.dropFolderID = folder
        surface.configure(content: AnyView(EmptyView()), size: surface.bounds.size, source: .zero,
                          destination: surface.bounds, expanded: true)
        root.addSubview(surface)
        let boundary = FolderDragBoundary.BoundaryView(frame: surface.bounds)
        boundary.panel = surface.bounds; boundary.active = true; boundary.folderID = folder
        surface.addSubview(boundary)
        let info = NativeDropTestInfo(window: window, token: "c")
        info.draggingLocation = CGPoint(x: 10, y: 150)
        #expect(!collection.performDragOperation(info)) // Outside actual panel, even with an open folder.
        info.draggingLocation = CGPoint(x: 70, y: 150)
        info.draggingSequenceNumber = 99
        #expect(!collection.prepareForDragOperation(info))
        info.draggingSequenceNumber = 17
        #expect(collection.draggingEntered(info) == .move)
        store.previewMove(.group("c"), intoFolder: folder)
        store.moveAppInsideFolder("c", folderID: folder, relativeTo: "a", side: .before)
        #expect(collection.draggingUpdated(info) == .move)
        #expect(collection.prepareForDragOperation(info))
        #expect(collection.performDragOperation(info))
        #expect(!collection.performDragOperation(info))
        store.finishDragPreview(commit: false)
        #expect(store.group(id: folder)?.apps.first?.id == "c")
        #expect(store.allApps().filter { $0.id == "c" }.count == 1)
    }

    @Test func nativeIdentityRejectsOldSessionsSequencesAndForeignPayloads() {
        let session = UUID()
        let identity = NativeDragIdentity(sessionID: session, sequenceNumber: 17, payload: .group("outside"))
        #expect(identity.matches(sessionID: session, sequenceNumber: 17, token: "outside"))
        #expect(!identity.matches(sessionID: UUID(), sequenceNumber: 17, token: "outside"))
        #expect(!identity.matches(sessionID: session, sequenceNumber: 18, token: "outside"))
        #expect(!identity.matches(sessionID: session, sequenceNumber: 17, token: "different"))
    }

    @Test func nativeGridCommitsAfterSourceRemovedAndRejectsDuplicateDrop() throws {
        let (store, directory) = EditingRegressionTests().fixture()
        defer { try? FileManager.default.removeItem(at: directory) }
        store.dropGroup("b", into: "a")
        let folder = store.groups(on: 0)[0].id
        store.beginDragPreview()
        store.dragOpenFolderID = folder
        let owner = NativeDropTestOwner(store: store, payload: .group("c"))
        store.dragLifetime = owner
        store.previewMove(.group("c"), intoFolder: folder)
        #expect(store.group(id: "c") == nil)
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 500, height: 300),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        let collection = LaunchpadCollectionView(frame: CGRect(x: 0, y: 0, width: 500, height: 300))
        window.contentView = collection
        let coordinator = NativeLaunchGrid.Coordinator(store: store, dragging: .constant(.group("c")),
                                                      onOpenFolder: { _ in }, onOpenApp: { _ in })
        coordinator.collectionView = collection
        coordinator.folderID = folder
        coordinator.metrics = GridMetrics(width: 500, height: 300, columns: 3, rows: 1)
        collection.nativeDrop = { coordinator.receiveNativeDrop($0, dropping: $1) }
        let info = NativeDropTestInfo(window: window, token: "c")
        info.draggingLocation = CGPoint(x: 60, y: 160)
        #expect(collection.draggingEntered(info) == .move)
        #expect(collection.prepareForDragOperation(info))
        #expect(collection.performDragOperation(info))
        #expect(!store.isPreviewingDrag)
        #expect(store.group(id: folder)?.apps.first?.id == "c")
        #expect(!collection.performDragOperation(info))
        store.finishDragPreview(commit: false)
        #expect(store.group(id: folder)?.apps.first?.id == "c")
    }

    @Test func nativeFolderPaddingAcceptsOnlyCurrentInternalDropWithinPanel() throws {
        let (store, directory) = EditingRegressionTests().fixture()
        defer { try? FileManager.default.removeItem(at: directory) }
        store.dropGroup("b", into: "a")
        let folder = store.groups(on: 0)[0].id
        store.beginDragPreview()
        store.dragOpenFolderID = folder
        let owner = NativeDropTestOwner(store: store, payload: .group("c"))
        store.dragLifetime = owner
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 500, height: 300),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        let surface = NativeFolderMorphView(frame: CGRect(x: 0, y: 0, width: 500, height: 300))
        window.contentView = surface
        surface.dropStore = store
        surface.dropFolderID = folder
        surface.configure(content: AnyView(EmptyView()), size: surface.bounds.size, source: .zero,
                          destination: surface.bounds, expanded: true)
        let boundary = FolderDragBoundary.BoundaryView(frame: surface.bounds)
        boundary.panel = surface.bounds; boundary.active = true; boundary.folderID = folder
        surface.addSubview(boundary)
        let info = NativeDropTestInfo(window: window, token: "c")
        info.draggingLocation = CGPoint(x: -10, y: 150)
        #expect(!surface.prepareForDragOperation(info))
        info.draggingLocation = CGPoint(x: 20, y: 150) // Panel padding, outside the inner grid.
        info.draggingSequenceNumber = 99
        #expect(!surface.prepareForDragOperation(info))
        info.draggingSequenceNumber = 17
        #expect(surface.draggingEntered(info) == .move)
        #expect(surface.performDragOperation(info))
        #expect(store.group(id: folder)?.apps.contains { $0.id == "c" } == true)
        #expect(!surface.performDragOperation(info))
        #expect(store.allApps().filter { $0.id == "c" }.count == 1)
    }

    @Test func nativePageCommitsFolderOriginAfterItsItemChangesContainers() throws {
        let (store, directory) = EditingRegressionTests().fixture()
        defer { try? FileManager.default.removeItem(at: directory) }
        store.dropGroup("b", into: "a")
        let folder = store.groups(on: 0)[0].id
        store.beginDragPreview()
        let payload = DragPayload.folderApp(appID: "a", folderID: folder)
        let owner = NativeDropTestOwner(store: store, payload: payload)
        store.dragLifetime = owner
        let outside = try #require(store.previewMoveToPage(payload, page: 0))
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 500, height: 300),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        let collection = LaunchpadCollectionView(frame: CGRect(x: 0, y: 0, width: 500, height: 300))
        window.contentView = collection
        let coordinator = NativeLaunchGrid.Coordinator(store: store, dragging: .constant(payload),
                                                      onOpenFolder: { _ in }, onOpenApp: { _ in })
        coordinator.collectionView = collection
        coordinator.metrics = GridMetrics(width: 500, height: 300, columns: 3, rows: 1)
        collection.nativeDrop = { coordinator.receiveNativeDrop($0, dropping: $1) }
        let info = NativeDropTestInfo(window: window, token: "a")
        info.draggingLocation = CGPoint(x: 420, y: 50)
        #expect(collection.draggingEntered(info) == .move)
        #expect(collection.performDragOperation(info))
        store.finishDragPreview(commit: false)
        #expect(store.group(id: outside)?.apps.first?.id == "a")
        #expect(store.group(id: folder)?.apps.contains { $0.id == "a" } == false)
        #expect(!collection.performDragOperation(info))
    }

    @Test func crossContainerAppearanceUsesAppIdentityAndClearsOnFinish() throws {
        let (store, directory) = EditingRegressionTests().fixture()
        defer { try? FileManager.default.removeItem(at: directory) }
        store.dropGroup("b", into: "a")
        let folderID = store.groups(on: 0)[0].id
        store.beginDragPreview()
        let session = store.dragSessionID
        let payload = DragPayload.group("c")
        store.registerDragAppearance(payload, sessionID: session)
        #expect(!store.suppressesDragContent(appID: "c"))
        store.previewMove(payload, intoFolder: folderID)
        #expect(store.suppressesDragContent(appID: "c"))
        #expect(!store.suppressesDragContent(appID: "a"))
        store.previewMoveToPage(payload, page: 0)
        #expect(store.suppressesDragContent(appID: "c"))
        store.previewMove(payload, intoFolder: folderID)
        #expect(store.suppressesDragContent(appID: "c"))
        store.finishDragPreview(commit: false)
        #expect(!store.suppressesDragContent(appID: "c"))
        store.beginDragPreview()
        store.registerDragAppearance(payload, sessionID: session) // Late old-session callback.
        store.previewMove(payload, intoFolder: folderID)
        #expect(!store.suppressesDragContent(appID: "c"))
        store.finishDragPreview(commit: false)
    }

    @Test func contentSuppressionPreservesRootAndRestoresOnReuseAndCommit() throws {
        let (store, directory) = EditingRegressionTests().fixture()
        defer { try? FileManager.default.removeItem(at: directory) }
        store.dropGroup("b", into: "a")
        let folderID = store.groups(on: 0)[0].id
        store.beginDragPreview()
        let payload = DragPayload.group("c")
        store.registerDragAppearance(payload, sessionID: store.dragSessionID)
        store.previewMove(payload, intoFolder: folderID)
        let app = try #require(store.group(id: folderID)?.apps.first { $0.id == "c" })
        let destination = LaunchGroup(id: app.id, name: "", isFolder: false, apps: [app])
        let item = LaunchpadCollectionItem()
        item.loadView()
        let metrics = GridMetrics(width: 1120, height: 620)
        item.configure(with: destination, store: store, metrics: metrics)
        item.setKeyboardSelected(true)
        item.setEditing(true, app: app, store: store)
        #expect(item.dragContentSuppressed)
        #expect(!item.view.isHidden && item.view.alphaValue == 1)
        #expect(item.view.subviews.allSatisfy { $0.alphaValue == 0 })
        item.configure(with: try #require(store.group(id: folderID)), store: store, metrics: metrics)
        #expect(!item.dragContentSuppressed) // Reused for a folder, never hide it.
        #expect(item.view.subviews.allSatisfy { $0.alphaValue == 1 })
        item.configure(with: destination, store: store, metrics: metrics)
        #expect(item.dragContentSuppressed)
        // Exercise the actual coordinator's finish observer without a SwiftUI layout update.
        let collection = DragAppearanceTestCollection()
        collection.testItems = [item]
        let coordinator = NativeLaunchGrid.Coordinator(store: store, dragging: .constant(payload),
                                                      onOpenFolder: { _ in }, onOpenApp: { _ in })
        coordinator.collectionView = collection
        store.finishDragPreview(commit: true)
        #expect(!item.dragContentSuppressed)
        #expect(item.view.subviews.allSatisfy { $0.alphaValue == 1 })
    }

    @Test func sameContainerAndWholeFolderDragsKeepExistingAppearance() throws {
        let (store, directory) = EditingRegressionTests().fixture()
        defer { try? FileManager.default.removeItem(at: directory) }
        store.dropGroup("b", into: "a")
        let folderID = store.groups(on: 0)[0].id
        store.beginDragPreview()
        let payload = DragPayload.folderApp(appID: "a", folderID: folderID)
        store.registerDragAppearance(payload, sessionID: store.dragSessionID)
        store.previewMove(payload, intoFolder: folderID)
        store.moveAppInsideFolder("a", folderID: folderID, relativeTo: "b", side: .after)
        #expect(!store.suppressesDragContent(appID: "a"))
        store.previewMoveToPage(payload, page: 0)
        #expect(store.suppressesDragContent(appID: "a"))
        store.finishDragPreview(commit: false)
        store.beginDragPreview()
        store.registerDragAppearance(.group(folderID), sessionID: store.dragSessionID)
        store.moveGroup(folderID, relativeTo: "c", side: .after)
        #expect(!store.suppressesDragContent(appID: "a"))
        #expect(!store.suppressesDragContent(appID: "b"))
        store.finishDragPreview(commit: false)
    }

    @Test func folderDropUsesOnlyVisibleGlyphAndLeavesSurroundingCellForReordering() {
        for scale in [0.8, 1.0, 1.2] {
            let metrics = GridMetrics(width: 1480, height: 800, iconScale: scale)
            let index = 9
            let icon = metrics.iconRect(at: index)
            let folder = icon.insetBy(dx: metrics.iconSize * 0.09, dy: metrics.iconSize * 0.09)
            #expect(metrics.folderAcceptsDrop(CGPoint(x: folder.midX, y: folder.midY), at: index))
            #expect(metrics.folderAcceptsDrop(CGPoint(x: folder.minX + 1, y: folder.midY), at: index))
            // All four surrounding gaps, the label and rounded-corner cutouts
            // must fall through to the existing live reorder path.
            for point in [CGPoint(x: folder.minX - 1, y: folder.midY),
                          CGPoint(x: folder.maxX + 1, y: folder.midY),
                          CGPoint(x: folder.midX, y: folder.minY - 1),
                          CGPoint(x: folder.midX, y: folder.maxY + 1),
                          CGPoint(x: icon.midX, y: icon.maxY + 12),
                          CGPoint(x: folder.minX + 1, y: folder.minY + 1)] {
                #expect(!metrics.folderAcceptsDrop(point, at: index))
            }
        }
    }

    @Test func springOpenAllowsDiagonalEntryThenRequiresDeliberateExit() {
        var travel = FolderDragTravel()
        let panel = CGRect(x: 300, y: 180, width: 1000, height: 600)
        // Original icon is outside the expanded panel. This diagonal approach
        // used to cross the narrow corridor and close the folder accidentally.
        #expect(({ !travel.shouldClose(point: CGPoint(x: 1450, y: 1000), panel: panel, now: 0) })())
        #expect(({ !travel.shouldClose(point: CGPoint(x: 1330, y: 850), panel: panel, now: 0.4) })())
        #expect(({ !travel.shouldClose(point: CGPoint(x: 1100, y: 650), panel: panel, now: 0.8) })())
        #expect(({ !travel.shouldClose(point: CGPoint(x: 1350, y: 650), panel: panel, now: 1) })())
        #expect(({ !travel.shouldClose(point: CGPoint(x: 1280, y: 650), panel: panel, now: 1.1) })())
        #expect(({ !travel.shouldClose(point: CGPoint(x: 1350, y: 650), panel: panel, now: 1.2) })())
        #expect(({ travel.shouldClose(point: CGPoint(x: 1370, y: 650), panel: panel, now: 1.5) })())
    }

    @Test func sameFolderCanDwellOpenAgainAfterLeaving() {
        var hover = DragDwell()
        #expect(({ !hover.update("folder", now: 0, delay: 0.65) })())
        #expect(({ hover.update("folder", now: 0.7, delay: 0.65) })())
        hover.reset()
        #expect(({ !hover.update("folder", now: 1, delay: 0.65) })())
        #expect(({ hover.update("folder", now: 1.7, delay: 0.65) })())
        #expect(({ !hover.update("other", now: 2, delay: 0.65) })())
    }

    @Test func dragIntentDelaysTransitButNeverDelaysTheFinalDrop() {
        var approach = DragDwell()
        #expect(!DragIntentTiming.isReady(&approach, key: "app-cell", now: 0,
                                          delay: DragIntentTiming.topLevelReorder, dropping: false))
        #expect(!DragIntentTiming.isReady(&approach, key: "app-cell", now: 0.3,
                                          delay: DragIntentTiming.topLevelReorder, dropping: false))
        #expect(DragIntentTiming.isReady(&approach, key: "app-cell", now: 0.36,
                                         delay: DragIntentTiming.topLevelReorder, dropping: false))
        #expect(DragIntentTiming.isReady(&approach, key: "other-cell", now: 0.37,
                                         delay: DragIntentTiming.topLevelReorder, dropping: true))
        var territory = DragDwell()
        #expect(!DragIntentTiming.isReady(&territory, key: "folder-cell", now: 0,
                                          delay: DragIntentTiming.reorder, dropping: false))
        #expect(!DragIntentTiming.isReady(&territory, key: "folder-cell", now: 0.1,
                                          delay: DragIntentTiming.reorder, dropping: false))
        #expect(DragIntentTiming.isReady(&territory, key: "folder-cell", now: 0.17,
                                         delay: DragIntentTiming.reorder, dropping: false))

        var folder = DragDwell()
        #expect(!DragIntentTiming.isReady(&folder, key: "folder", now: 1,
                                          delay: DragIntentTiming.folderSelection, dropping: false))
        #expect(DragIntentTiming.isReady(&folder, key: "folder", now: 1.13,
                                         delay: DragIntentTiming.folderSelection, dropping: false))
        #expect(DragIntentTiming.isReady(&folder, key: "folder", now: 1.14,
                                         delay: DragIntentTiming.folderOpen, dropping: true))
    }

    @Test func retreatBeforeEntryAndReleaseOutsideAreHandled() {
        let panel = CGRect(x: 100, y: 100, width: 300, height: 300)
        var travel = FolderDragTravel()
        #expect(({ !travel.shouldClose(point: CGPoint(x: 500, y: 250), panel: panel, now: 0) })())
        #expect(({ !travel.shouldClose(point: CGPoint(x: 600, y: 250), panel: panel, now: 0.2) })())
        #expect(({ travel.shouldClose(point: CGPoint(x: 600, y: 250), panel: panel, now: 0.5) })())
        travel = FolderDragTravel()
        #expect(({ !travel.shouldClose(point: CGPoint(x: 200, y: 200), panel: panel, now: 1) })())
        #expect(({ travel.shouldClose(point: CGPoint(x: 600, y: 200), panel: panel, now: 1.01, dropping: true) })())
    }

    @Test func endingSessionClearsDestinationAndStopsFurtherRouting() {
        let (store, _) = EditingRegressionTests().fixture()
        store.beginDragPreview()
        store.dragDestination = .folder("example")
        store.finishDragPreview(commit: false)
        DragTracking.update(CGPoint(x: 10, y: 10), store: store)
        #expect(store.dragDestination == nil)
        #expect(!store.isPreviewingDrag)
    }

    @Test func hoverScalesTileWithoutAddingSelectionFrame() {
        let item = LaunchpadCollectionItem()
        item.loadView()
        item.view.frame = CGRect(x: 0, y: 0, width: 160, height: 160)
        let count = item.view.subviews.count
        item.setMergeTarget(true)
        #expect(item.view.subviews.count == count)
        #expect(abs((item.view.layer?.transform.m11 ?? 0) - 1.14) < 0.001)
        item.setMergeTarget(false)
        #expect(item.view.layer?.transform.m11 == 1)
        item.animateReflow(from: CGPoint(x: -160, y: 0))
        if !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            #expect(item.view.layer?.animation(forKey: "gridReflow") != nil)
        }
    }

    @Test func appDragImageContainsOnlyTheIconInsteadOfTheWholeCell() throws {
        let (store, directory) = EditingRegressionTests().fixture()
        defer { try? FileManager.default.removeItem(at: directory) }
        let group = try #require(store.groups(on: 0).first { !$0.isFolder })
        let item = LaunchpadCollectionItem()
        item.loadView()
        item.view.frame = CGRect(x: 0, y: 0, width: 160, height: 160)
        item.configure(with: group, store: store, metrics: GridMetrics(width: 1120, height: 620))
        item.view.layoutSubtreeIfNeeded()

        let components = item.draggingImageComponents
        let preview = try #require(item.appDragPreview)
        #expect(components.count == 1)
        #expect(components.first?.key == .icon)
        #expect(components.first?.contents is NSImage)
        #expect(preview.frame == components.first?.frame)
        #expect(components.first?.frame.width ?? 0 < item.view.bounds.width)
        #expect(components.first?.frame.height ?? 0 < item.view.bounds.height)
    }
}

@MainActor
private final class DragAppearanceTestCollection: NSCollectionView {
    var testItems: [NSCollectionViewItem] = []
    override func visibleItems() -> [NSCollectionViewItem] { testItems }
}

private struct FolderNameTestHost: View {
    @ObservedObject var store: LayoutStore
    let folderID: String
    @State private var name = "未命名"
    @State private var focused = false
    var body: some View {
        FolderNameField(text: $name, focused: $focused, store: store, folderID: folderID,
                        enabled: !store.isPreviewingDrag, request: store.folderNamingRequest,
                        onSave: {}).frame(width: 300, height: 30)
    }
}

@MainActor private final class NativeDropTestOwner: NSObject, NativeDragSessionOwner {
    let nativeDragIdentity: NativeDragIdentity?
    init(store: LayoutStore, payload: DragPayload) {
        nativeDragIdentity = NativeDragIdentity(sessionID: store.dragSessionID, sequenceNumber: 17, payload: payload)
    }
}

@MainActor private final class NativeDropTestInfo: NSObject, NSDraggingInfo {
    let draggingDestinationWindow: NSWindow?
    var draggingSourceOperationMask: NSDragOperation { .move }
    var draggingLocation = CGPoint.zero
    var draggedImageLocation: NSPoint { draggingLocation }
    nonisolated var draggedImage: NSImage? { nil }
    let draggingPasteboard = NSPasteboard.withUniqueName()
    var draggingSource: Any? { self }
    var draggingSequenceNumber = 17
    var draggingFormation: NSDraggingFormation = .none
    var animatesToDestination = false
    var numberOfValidItemsForDrop = 1
    var springLoadingHighlight: NSSpringLoadingHighlight { .none }
    init(window: NSWindow, token: String) {
        draggingDestinationWindow = window
        super.init()
        draggingPasteboard.setString(token, forType: .string)
    }
    func slideDraggedImage(to screenPoint: NSPoint) {}
    nonisolated override func namesOfPromisedFilesDropped(atDestination dropDestination: URL) -> [String]? { nil }
    func resetSpringLoading() {}
    func enumerateDraggingItems(options: NSDraggingItemEnumerationOptions, for view: NSView?,
                                classes classArray: [AnyClass], searchOptions: [NSPasteboard.ReadingOptionKey: Any],
                                using block: (NSDraggingItem, Int, UnsafeMutablePointer<ObjCBool>) -> Void) {}
}

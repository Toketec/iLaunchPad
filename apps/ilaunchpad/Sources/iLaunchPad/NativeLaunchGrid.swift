import AppKit
import SwiftUI

struct NativeLaunchGrid: NSViewRepresentable {
    let groups: [LaunchGroup]
    let store: LayoutStore
    let allowsReordering: Bool
    @Binding var dragging: DragPayload?
    let onOpenFolder: (String) -> Void
    let onOpenApp: (LaunchApp) -> Void
    var metrics = GridMetrics(width: 1120, height: 620)
    var keyboardSelection: String?
    var onBackgroundClick: (() -> Void)?
    var folderID: String? = nil
    var folderDestinationPage: Int = 0

    func makeCoordinator() -> Coordinator {
        Coordinator(
            store: store,
            dragging: $dragging,
            onOpenFolder: onOpenFolder,
            onOpenApp: onOpenApp
        )
    }

    func makeNSView(context: Context) -> NSScrollView {
        let layout = NSCollectionViewFlowLayout()
        layout.itemSize = NSSize(width: metrics.cellWidth, height: metrics.cellHeight)
        layout.minimumInteritemSpacing = 0
        layout.minimumLineSpacing = 0
        layout.sectionInset = NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)

        let collection = LaunchpadCollectionView()
        collection.collectionViewLayout = layout
        collection.backgroundColors = [.clear]
        collection.isSelectable = true
        collection.allowsMultipleSelection = false
        collection.register(LaunchpadCollectionItem.self, forItemWithIdentifier: .launchpadItem)
        collection.dataSource = context.coordinator
        collection.delegate = context.coordinator
        collection.nativeDrop = { [weak coordinator = context.coordinator] info, dropping in
            coordinator?.receiveNativeDrop(info, dropping: dropping) == true
        }
        let click = NSClickGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.activateItem(_:)))
        click.delaysPrimaryMouseButtonEvents = false
        collection.addGestureRecognizer(click)
        let press = NSPressGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.longPress(_:)))
        press.minimumPressDuration = 0.55
        press.allowableMovement = 8
        press.delaysPrimaryMouseButtonEvents = false
        collection.addGestureRecognizer(press)
        collection.onMouseDown = { [weak coordinator = context.coordinator] in coordinator?.suppressClick = false }
        collection.menuProvider = { [weak coordinator = context.coordinator] indexPath in
            coordinator?.allowsReordering == true ? coordinator?.menu(for: indexPath) : nil
        }
        collection.registerForDraggedTypes([.string])
        collection.setDraggingSourceOperationMask(.move, forLocal: true)
        collection.backgroundClick = onBackgroundClick

        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = false
        scroll.hasHorizontalScroller = false
        scroll.autohidesScrollers = true
        scroll.horizontalScrollElasticity = .none
        scroll.verticalScrollElasticity = allowsReordering && folderID == nil ? .none : .automatic
        scroll.documentView = collection
        context.coordinator.collectionView = collection
        context.coordinator.groups = groups
        context.coordinator.allowsReordering = allowsReordering
        context.coordinator.metrics = metrics
        context.coordinator.keyboardSelection = keyboardSelection
        context.coordinator.folderID = folderID
        context.coordinator.folderDestinationPage = folderDestinationPage
        context.coordinator.editing = store.isEditing
        collection.frame = NSRect(x: 0, y: 0, width: metrics.width, height: metrics.height)
        collection.reloadData()
        return scroll
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        let oldGroups = context.coordinator.groups
        let changed = oldGroups != groups
        let resized = context.coordinator.metrics != metrics
        let selectionChanged = context.coordinator.keyboardSelection != keyboardSelection
        let editingChanged = context.coordinator.editing != store.isEditing
        context.coordinator.groups = groups
        context.coordinator.allowsReordering = allowsReordering
        context.coordinator.onOpenFolder = onOpenFolder
        context.coordinator.onOpenApp = onOpenApp
        context.coordinator.metrics = metrics
        context.coordinator.keyboardSelection = keyboardSelection
        context.coordinator.folderID = folderID
        context.coordinator.folderDestinationPage = folderDestinationPage
        context.coordinator.editing = store.isEditing
        guard let collection = context.coordinator.collectionView else { return }
        (collection as? LaunchpadCollectionView)?.backgroundClick = onBackgroundClick
        if resized, let layout = collection.collectionViewLayout as? NSCollectionViewFlowLayout {
            collection.setFrameSize(NSSize(width: metrics.width, height: metrics.height))
            layout.itemSize = NSSize(width: metrics.cellWidth, height: metrics.cellHeight)
            layout.invalidateLayout()
        }
        if resized { collection.reloadData() }
        else if changed {
            let previousOrigins = Dictionary(uniqueKeysWithValues: collection.visibleItems().compactMap { item -> (String, CGPoint)? in
                guard let item = item as? LaunchpadCollectionItem, let layer = item.view.layer else { return nil }
                let visible = layer.presentation()?.position ?? layer.position
                return (item.groupID, CGPoint(x: item.view.frame.minX + visible.x - layer.position.x,
                                             y: item.view.frame.minY + visible.y - layer.position.y))
            })
            let oldIDs = oldGroups.map(\.id)
            let newIDs = groups.map(\.id)
            let removed = Set(oldIDs).subtracting(newIDs)
            let inserted = Set(newIDs).subtracting(oldIDs)
            NSAnimationContext.runAnimationGroup { animation in
            // Apply the model atomically, then explicitly animate retained tiles
            // from their presentation positions. Hosting transactions disable
            // implicit animations, so a duration alone does not animate moves.
            animation.duration = 0
            collection.performBatchUpdates {
                collection.deleteItems(at: Set(oldIDs.indices.filter { removed.contains(oldIDs[$0]) }.map { IndexPath(item: $0, section: 0) }))
                collection.insertItems(at: Set(newIDs.indices.filter { inserted.contains(newIDs[$0]) }.map { IndexPath(item: $0, section: 0) }))
                if removed.isEmpty && inserted.isEmpty {
                    for (oldIndex, id) in oldIDs.enumerated() {
                        if let newIndex = newIDs.firstIndex(of: id), oldIndex != newIndex {
                            collection.moveItem(at: IndexPath(item: oldIndex, section: 0), to: IndexPath(item: newIndex, section: 0))
                        }
                    }
                }
            } completionHandler: { _ in
                collection.layoutSubtreeIfNeeded()
                for case let item as LaunchpadCollectionItem in collection.visibleItems() {
                    if let group = context.coordinator.groups.first(where: { $0.id == item.groupID }) {
                        item.configure(with: group, store: store, metrics: context.coordinator.metrics)
                        item.setEditing(store.isEditing, app: group.isFolder ? nil : group.apps.first, store: store)
                        item.setMergeTarget(group.id == context.coordinator.mergeTargetID)
                        if let origin = previousOrigins[group.id] { item.animateReflow(from: origin) }
                    }
                }
            }
            }
        }
        if selectionChanged || changed || resized || editingChanged {
            for case let item as LaunchpadCollectionItem in collection.visibleItems() {
                item.setKeyboardSelected(item.groupID == keyboardSelection)
                let group = groups.first { $0.id == item.groupID }
                item.setEditing(store.isEditing, app: group?.isFolder == false ? group?.apps.first : nil, store: store)
            }
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSCollectionViewDataSource, NSCollectionViewDelegate, NativeDragSessionOwner {
        let store: LayoutStore
        var dragging: Binding<DragPayload?>
        var onOpenFolder: (String) -> Void
        var onOpenApp: (LaunchApp) -> Void
        weak var collectionView: NSCollectionView?
        var groups: [LaunchGroup] = []
        var allowsReordering = true
        var metrics = GridMetrics(width: 1120, height: 620)
        var keyboardSelection: String?
        var folderID: String?
        var folderDestinationPage = 0
        var editing = false
        var suppressClick = false
        private var retainedDragSource: NSCollectionView?
        private let dragClock = WindowDragClock()
        private(set) var nativeDragIdentity: NativeDragIdentity?
        var mergeTargetID: String?
        private var hover = DragDwell()
        private var reorderDwell = DragDwell()
        private var lastPlacement: String?
        private var appMergeCandidate: (id: String, region: CGRect, sourceFrame: CGRect)?
        private var dropValidationTrace: String?

        init(
            store: LayoutStore,
            dragging: Binding<DragPayload?>,
            onOpenFolder: @escaping (String) -> Void,
            onOpenApp: @escaping (LaunchApp) -> Void
        ) {
            self.store = store
            self.dragging = dragging
            self.onOpenFolder = onOpenFolder
            self.onOpenApp = onOpenApp
            super.init()
            NotificationCenter.default.addObserver(self, selector: #selector(trackPosition(_:)), name: .launchpadDragMoved, object: store)
            NotificationCenter.default.addObserver(self, selector: #selector(finishTracking), name: .launchpadDragFinished, object: store)
        }

        deinit { NotificationCenter.default.removeObserver(self) }

        @objc private func finishTracking() {
            dragClock.stop()
            nativeDragIdentity = nil
            // Finish may not change layout (e.g. a drop at the current slot).
            // Restore content immediately, independently of SwiftUI updates.
            for case let item as LaunchpadCollectionItem in collectionView?.visibleItems() ?? [] {
                item.refreshDragAppearance()
            }
            cancelMerge(); reorderDwell.reset(); lastPlacement = nil
            retainedDragSource = nil
            dragging.wrappedValue = nil
            store.dragLifetime = nil
        }

        @objc private func trackPosition(_ event: Notification) {
            let dropping = event.userInfo?["dropping"] as? Bool == true
            guard let value = event.userInfo?["point"] as? NSValue,
                  let now = event.userInfo?["time"] as? TimeInterval,
                  allowsReordering, store.isPreviewingDrag,
                  store.dragOpenFolderID == folderID,
                  folderID != nil || store.dragCurrentPage == folderDestinationPage,
                  now >= store.dragRoutingPausedUntil || dropping,
                  let collection = collectionView, let window = collection.window,
                  let payload = dragging.wrappedValue else { cancelMerge(); reorderDwell.reset(); lastPlacement = nil; return }
            let point = collection.convert(window.convertPoint(fromScreen: value.pointValue), from: nil)
            guard collection.visibleRect.contains(point) else { cancelMerge(); reorderDwell.reset(); lastPlacement = nil; return }
            updatePlacement(point, payload: payload, now: now, dropping: dropping)
        }

        private func updatePlacement(_ point: CGPoint, payload: DragPayload, now: TimeInterval, dropping: Bool) {
            let sourceID: String
            if let folderID {
                guard let id = store.draggedAppID(payload) else { return }
                sourceID = id
                store.previewMove(payload, intoFolder: folderID)
                store.dragDestination = .folder(folderID)
            } else {
                guard let id = store.previewMoveToPage(payload, page: folderDestinationPage) else { return }
                sourceID = id
                if !store.groups(on: folderDestinationPage).contains(where: { $0.id == id }) {
                    store.moveGroup(id, toPage: folderDestinationPage)
                }
                store.dragDestination = .page(folderDestinationPage)
            }
            // Read the current model, not the collection's previous animation frame.
            let liveGroups = folderID.flatMap { store.group(id: $0) }?.apps.map {
                LaunchGroup(id: $0.id, name: "", isFolder: false, apps: [$0])
            } ?? store.groups(on: folderDestinationPage)
            guard !liveGroups.isEmpty else { return }
            let column = min(metrics.columns - 1, max(0, Int(point.x / metrics.cellWidth)))
            let row = max(0, Int(point.y / metrics.cellHeight))
            let slot = min(liveGroups.count - 1, row * metrics.columns + column)
            let target = liveGroups[slot]
            if let candidate = appMergeCandidate, folderID == nil, !dropping,
               candidate.region.contains(point), store.group(id: candidate.id)?.isFolder == false {
                updateAppMerge(candidate, payload: payload, now: now)
                return
            }
            if appMergeCandidate != nil { cancelMerge() }
            if folderID == nil, target.id != sourceID, target.isFolder,
               metrics.folderAcceptsDrop(point, at: slot), store.draggedAppID(payload) != nil {
                reorderDwell.reset()
                lastPlacement = nil
                let key = "folder:\(target.id)"
                let selected = DragIntentTiming.isReady(
                    &hover, key: key, now: now,
                    delay: DragIntentTiming.folderSelection, dropping: dropping
                )
                if selected {
                    mergeTargetID = target.id
                    updateMergeHighlight()
                    store.dragDestination = .folder(target.id)
                } else {
                    mergeTargetID = nil
                    updateMergeHighlight()
                }
                if !dropping, hover.update(key, now: now, delay: DragIntentTiming.folderOpen) {
                    // Reset before opening: returning to this group always starts a new dwell.
                    cancelMerge(); lastPlacement = nil
                    onOpenFolder(target.id)
                }
                return
            }
            cancelMerge()
            guard target.id != sourceID else { reorderDwell.reset(); return }
            if !dropping, folderID == nil, !target.isFolder, store.draggedAppID(payload) != nil,
               metrics.iconRect(at: slot).insetBy(dx: metrics.iconSize * 0.2, dy: metrics.iconSize * 0.2).contains(point) {
                let frame = metrics.iconRect(at: slot)
                let candidate = (id: target.id, region: frame.insetBy(dx: metrics.iconSize * 0.2, dy: metrics.iconSize * 0.2), sourceFrame: frame)
                appMergeCandidate = candidate
                updateAppMerge(candidate, payload: payload, now: now)
                return // Centre intent owns this frame; do not also arm a reorder.
            }
            let sourceIndex = liveGroups.firstIndex { $0.id == sourceID }
            let side: DropSide = sourceIndex.map { $0 < slot ? .after : .before } ?? .before
            let placement = "\(folderID ?? "page-\(folderDestinationPage)"):\(target.id):\(side)"
            guard lastPlacement != placement else { return }
            guard DragIntentTiming.isReady(
                &reorderDwell, key: placement, now: now,
                delay: folderID == nil ? DragIntentTiming.topLevelReorder : DragIntentTiming.reorder, dropping: dropping
            ) else { return }
            lastPlacement = placement
            if let folderID { store.moveAppInsideFolder(sourceID, folderID: folderID, relativeTo: target.id, side: side) }
            else { store.moveGroup(sourceID, relativeTo: target.id, side: side) }
        }

        private func updateAppMerge(_ candidate: (id: String, region: CGRect, sourceFrame: CGRect),
                                    payload: DragPayload, now: TimeInterval) {
            reorderDwell.reset()
            lastPlacement = nil
            let key = "app:\(candidate.id)"
            mergeTargetID = hover.update(key, now: now, delay: DragIntentTiming.folderSelection) ? candidate.id : nil
            updateMergeHighlight()
            if hover.update(key, now: now, delay: DragIntentTiming.appMerge),
               let id = store.beginMergePreview(payload, targetGroupID: candidate.id, sourceFrame: candidate.sourceFrame) {
                cancelMerge()
                store.dragDestination = .folder(id)
                onOpenFolder(id)
            }
        }

        func collectionView(_ collectionView: NSCollectionView, numberOfItemsInSection section: Int) -> Int {
            groups.count
        }

        func collectionView(_ collectionView: NSCollectionView, itemForRepresentedObjectAt indexPath: IndexPath) -> NSCollectionViewItem {
            let item = collectionView.makeItem(withIdentifier: .launchpadItem, for: indexPath)
            guard let launchItem = item as? LaunchpadCollectionItem,
                  groups.indices.contains(indexPath.item) else { return item }
            launchItem.configure(with: groups[indexPath.item], store: store, metrics: metrics)
            launchItem.setKeyboardSelected(groups[indexPath.item].id == keyboardSelection)
            let group = groups[indexPath.item]
            launchItem.setEditing(editing, app: group.isFolder ? nil : group.apps.first, store: store)
            return launchItem
        }

        func collectionView(_ collectionView: NSCollectionView, didSelectItemsAt indexPaths: Set<IndexPath>) {
            // Keep the native selection through mouse-down: modern AppKit uses
            // it to begin the drag. Clearing it here cancels the drag recognizer.
            // Launching still waits for a completed click, not selection.
        }

        @objc func activateItem(_ recognizer: NSClickGestureRecognizer) {
            guard recognizer.state == .ended, !suppressClick, !store.isPreviewingDrag, let collectionView else { return }
            let point = recognizer.location(in: collectionView)
            if let index = collectionView.indexPathForItem(at: point),
               let item = collectionView.item(at: index) as? LaunchpadCollectionItem,
               item.containsRemovalPoint(item.view.convert(point, from: collectionView)) { return }
            guard let indexPath = collectionView.indexPathForItem(at: point), groups.indices.contains(indexPath.item),
                  let item = collectionView.item(at: indexPath) as? LaunchpadCollectionItem,
                  item.containsActivationPoint(item.view.convert(point, from: collectionView)) else {
                (collectionView as? LaunchpadCollectionView)?.backgroundClick?()
                return
            }
            let group = groups[indexPath.item]
            if group.isFolder { onOpenFolder(group.id) }
            else if !store.isEditing, let app = group.apps.first { onOpenApp(app) }
        }

        @objc func longPress(_ recognizer: NSPressGestureRecognizer) {
            guard recognizer.state == .began, let collectionView else { return }
            let point = recognizer.location(in: collectionView)
            guard let index = collectionView.indexPathForItem(at: point),
                  let item = collectionView.item(at: index) as? LaunchpadCollectionItem,
                  !item.containsRemovalPoint(item.view.convert(point, from: collectionView)),
                  item.containsActivationPoint(item.view.convert(point, from: collectionView)) else { return }
            suppressClick = true
            store.isEditing = true
        }

        func collectionView(_ collectionView: NSCollectionView, pasteboardWriterForItemAt indexPath: IndexPath) -> NSPasteboardWriting? {
            guard allowsReordering, groups.indices.contains(indexPath.item) else { return nil }
            let pasteboardItem = NSPasteboardItem()
            pasteboardItem.setString(groups[indexPath.item].id, forType: .string)
            return pasteboardItem
        }

        func collectionView(
            _ collectionView: NSCollectionView,
            draggingSession session: NSDraggingSession,
            willBeginAt screenPoint: NSPoint,
            forItemsAt indexPaths: Set<IndexPath>
        ) {
            guard let indexPath = indexPaths.first, groups.indices.contains(indexPath.item) else { return }
            if let item = collectionView.item(at: indexPath) as? LaunchpadCollectionItem,
               let preview = item.appDragPreview {
                let iconFrame = collectionView.convert(preview.frame, from: item.view)
                session.draggingFormation = .none
                session.enumerateDraggingItems(options: [], for: collectionView,
                                                classes: [NSPasteboardItem.self], searchOptions: [:]) {
                    draggingItem, _, _ in
                    draggingItem.setDraggingFrame(iconFrame, contents: preview.image)
                }
            }
            cancelMerge()
            store.beginDragPreview()
            store.dragLifetime = self
            retainedDragSource = collectionView
            let id = groups[indexPath.item].id
            dragging.wrappedValue = folderID.map { .folderApp(appID: id, folderID: $0) } ?? .group(id)
            let sessionID = store.dragSessionID
            if let payload = dragging.wrappedValue {
                nativeDragIdentity = NativeDragIdentity(sessionID: sessionID,
                                                        sequenceNumber: session.draggingSequenceNumber, payload: payload)
            }
            DragTracking.trace("source.begin", store: store)
            if let payload = dragging.wrappedValue {
                store.registerDragAppearance(payload, sessionID: sessionID)
            }
            // NSCollectionView uses an internal dragging source, so its optional
            // movedTo callback is not reliably forwarded to the collection view.
            if let window = collectionView.window {
                dragClock.start(window: window) { [weak self] in
                    guard self?.store.isPreviewingDrag == true else { return }
                    guard let self else { return }
                    if NSEvent.pressedMouseButtons & 1 == 0 {
                        self.dragClock.stop()
                        // Let the native destination's mouse-up callback commit
                        // first; a missing/cancelled receiver must never leave a
                        // live preview or a polling timer behind.
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                            guard let self, self.store.dragSessionID == sessionID else { return }
                            DragTracking.trace("source.release-fallback", store: self.store)
                            self.store.finishDragPreview(commit: false)
                        }
                        return
                    }
                    DragTracking.updateFromDisplay(NSEvent.mouseLocation, store: self.store,
                                                   maximumFPS: window.screen?.maximumFramesPerSecond ?? 60)
                    DragTracking.traceHit(at: NSEvent.mouseLocation, window: self.retainedDragSource?.window,
                                          store: self.store)
                }
            }
            suppressClick = true
            session.animatesToStartingPositionsOnCancelOrFail = true
        }

        func collectionView(
            _ collectionView: NSCollectionView,
            draggingSession session: NSDraggingSession,
            endedAt screenPoint: NSPoint,
            dragOperation operation: NSDragOperation
        ) {
            // Successful receivers commit explicitly; every other ending rolls back.
            DragTracking.trace("source.end operation=\(operation.rawValue)", store: store)
            guard nativeDragIdentity?.sessionID == store.dragSessionID,
                  nativeDragIdentity?.sequenceNumber == session.draggingSequenceNumber else { return }
            store.finishDragPreview(commit: false)
        }

        // NSCollectionView's item-level destination is invalidated when live
        // previews remove/reinsert the source item. Receive at the stable view
        // level; never depend on an old index path or AppKit's drop-on item.
        func receiveNativeDrop(_ info: NSDraggingInfo, dropping: Bool) -> Bool {
            if DragTracking.tracingEnabled {
                let collection = collectionView
                DragTracking.traceChange("native-grid.\(folderID == nil ? "page" : "folder")",
                    "dropping=\(dropping) reorder=\(allowsReordering) identity=\(DragTracking.nativePayload(info, store: store) != nil) window=\(collection?.window != nil && info.draggingDestinationWindow === collection?.window) inside=\(collection.map { $0.visibleRect.contains($0.convert(info.draggingLocation, from: nil)) } ?? false) current=\(store.dragOpenFolderID == folderID)", store: store)
            }
            guard allowsReordering, let payload = DragTracking.nativePayload(info, store: store),
                  let collection = collectionView, let window = collection.window,
                  info.draggingDestinationWindow === window else { return false }
            let point = window.convertPoint(toScreen: info.draggingLocation)
            if !dropping { DragTracking.update(point, store: store) }
            if store.dragOpenFolderID != nil, store.dragOpenFolderID != folderID {
                return NativeFolderMorphView.receiveOpenFolderDrop(info, store: store, dropping: dropping)
            }
            guard collection.visibleRect.contains(collection.convert(info.draggingLocation, from: nil)) else { return false }
            guard store.dragOpenFolderID == folderID,
                  folderID != nil || store.dragCurrentPage == folderDestinationPage else { return false }
            if dropping {
                DragTracking.trace("native-grid.perform", store: store)
                return DragTracking.drop(point, store: store, payload: payload)
            }
            return true
        }

        func collectionView(
            _ collectionView: NSCollectionView,
            validateDrop draggingInfo: NSDraggingInfo,
            proposedIndexPath proposedDropIndexPath: AutoreleasingUnsafeMutablePointer<NSIndexPath>,
            dropOperation proposedDropOperation: UnsafeMutablePointer<NSCollectionView.DropOperation>
        ) -> NSDragOperation {
            let diagnostic = "collection.validate reorder=\(allowsReordering) source=\(validatedSourceID(draggingInfo) != nil) payload=\(dragging.wrappedValue != nil)"
            if diagnostic != dropValidationTrace {
                dropValidationTrace = diagnostic
                DragTracking.trace(diagnostic, store: store)
            }
            guard allowsReordering, store.isPreviewingDrag, validatedSourceID(draggingInfo) != nil else { return [] }
            if let window = collectionView.window {
                DragTracking.update(window.convertPoint(toScreen: draggingInfo.draggingLocation), store: store)
            }
            let point = collectionView.convert(draggingInfo.draggingLocation, from: nil)
            // A drop-on proposal has no native blue insertion bar. Ordering is
            // represented by the live grid itself, not a second drop indicator.
            proposedDropOperation.pointee = .on
            guard !groups.isEmpty else {
                proposedDropIndexPath.pointee = IndexPath(item: 0, section: 0) as NSIndexPath
                return .move
            }
            let column = min(metrics.columns - 1, max(0, Int(point.x / metrics.cellWidth)))
            let row = max(0, Int(point.y / metrics.cellHeight))
            let slot = min(groups.count - 1, row * metrics.columns + column)
            proposedDropIndexPath.pointee = IndexPath(item: slot, section: 0) as NSIndexPath
            return .move
        }

        func collectionView(
            _ collectionView: NSCollectionView,
            acceptDrop draggingInfo: NSDraggingInfo,
            indexPath: IndexPath,
            dropOperation: NSCollectionView.DropOperation
        ) -> Bool {
            DragTracking.trace("collection.accept", store: store)
            guard store.isPreviewingDrag, validatedSourceID(draggingInfo) != nil,
                  let payload = dragging.wrappedValue, let window = collectionView.window else {
                DragTracking.trace("collection.reject source=\(validatedSourceID(draggingInfo) != nil) payload=\(dragging.wrappedValue != nil) window=\(collectionView.window != nil)", store: store)
                return false
            }
            return DragTracking.drop(window.convertPoint(toScreen: draggingInfo.draggingLocation), store: store, payload: payload)
        }

        private func validatedSourceID(_ info: NSDraggingInfo) -> String? {
            guard let id = info.draggingPasteboard.string(forType: .string) else { return nil }
            switch dragging.wrappedValue {
            case .group(let source) where source == id: return id
            case .folderApp(let source, _) where source == id: return id
            default: return nil
            }
        }

        private func cancelMerge() {
            hover.reset(); mergeTargetID = nil; appMergeCandidate = nil
            updateMergeHighlight()
        }

        private func updateMergeHighlight() {
            for case let item as LaunchpadCollectionItem in collectionView?.visibleItems() ?? [] {
                item.setMergeTarget(item.groupID == mergeTargetID)
            }
        }

        func menu(for indexPath: IndexPath) -> NSMenu? {
            guard groups.indices.contains(indexPath.item) else { return nil }
            let group = groups[indexPath.item]
            let menu = NSMenu()
            if group.isFolder {
                let open = NSMenuItem(title: "打开文件夹", action: #selector(openFolder(_:)), keyEquivalent: "")
                open.target = self
                open.representedObject = group.id
                menu.addItem(open)
            } else if let app = group.apps.first {
                let open = NSMenuItem(title: "打开", action: #selector(openApplication(_:)), keyEquivalent: "")
                open.target = self
                open.representedObject = group.id
                menu.addItem(open)
                let reveal = NSMenuItem(title: "在访达中显示", action: #selector(revealApplication(_:)), keyEquivalent: "")
                reveal.target = self
                reveal.representedObject = group.id
                menu.addItem(reveal)
                menu.addItem(.separator())
                if folderID != nil {
                    let remove = NSMenuItem(title: "移出文件夹", action: #selector(removeFromFolder(_:)), keyEquivalent: "")
                    remove.target = self; remove.representedObject = group.id
                    menu.addItem(remove)
                    return menu
                }
                let hide = NSMenuItem(title: "从启动台隐藏", action: #selector(hideApplication(_:)), keyEquivalent: "")
                hide.target = self
                hide.representedObject = group.id
                menu.addItem(hide)
                _ = app
            }
            return menu
        }

        @objc private func openFolder(_ sender: NSMenuItem) {
            guard let id = sender.representedObject as? String else { return }
            onOpenFolder(id)
        }

        @objc private func openApplication(_ sender: NSMenuItem) {
            guard let id = sender.representedObject as? String,
                  let app = groups.first(where: { $0.id == id })?.apps.first else { return }
            onOpenApp(app)
        }

        @objc private func revealApplication(_ sender: NSMenuItem) {
            guard let id = sender.representedObject as? String,
                  let app = groups.first(where: { $0.id == id })?.apps.first else { return }
            store.showInFinder(app)
        }

        @objc private func hideApplication(_ sender: NSMenuItem) {
            guard let id = sender.representedObject as? String else { return }
            store.hide(id)
        }

        @objc private func removeFromFolder(_ sender: NSMenuItem) {
            guard let id = sender.representedObject as? String, let folderID else { return }
            store.removeFromFolder(id, folderID: folderID, toPage: folderDestinationPage)
        }
    }
}

final class LaunchpadCollectionView: NSCollectionView {
    var nativeDrop: ((NSDraggingInfo, Bool) -> Bool)?
    var menuProvider: ((IndexPath) -> NSMenu?)?
    var backgroundClick: (() -> Void)?
    var onMouseDown: (() -> Void)?
    nonisolated(unsafe) private var mouseMonitor: Any?

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        nativeDrop?(sender, false) == true ? .move : []
    }
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        nativeDrop?(sender, false) == true ? .move : []
    }
    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        nativeDrop?(sender, false) == true
    }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        nativeDrop?(sender, true) == true
    }
    override func wantsPeriodicDraggingUpdates() -> Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let mouseMonitor { NSEvent.removeMonitor(mouseMonitor); self.mouseMonitor = nil }
        guard window != nil else { return }
        // Overriding mouseDown forces NSCollectionView onto its legacy drag
        // implementation and disables the modern gesture-recognizer path.
        mouseMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
            if let self, event.window === self.window,
               self.visibleRect.contains(self.convert(event.locationInWindow, from: nil)) { self.onMouseDown?() }
            return event
        }
    }

    deinit { if let mouseMonitor { NSEvent.removeMonitor(mouseMonitor) } }

    override func menu(for event: NSEvent) -> NSMenu? {
        let point = convert(event.locationInWindow, from: nil)
        guard let indexPath = indexPathForItem(at: point) else { return nil }
        return menuProvider?(indexPath)
    }
}

final class LaunchpadCollectionItem: NSCollectionViewItem {
    private let contentView = NSView()
    private let iconView = NSImageView()
    private let titleField = NSTextField(labelWithString: "")
    private var folderGlass: NSGlassEffectView?
    private let folderContent = NSView()
    private var selectionGlass: NSGlassEffectView?
    private var keyboardSelected = false
    private var lastLayoutSize: NSSize?
    private var miniIcons: [NSImageView] = []
    private var metrics = GridMetrics(width: 1120, height: 620)
    private var folder = false
    private let removeButton = NSButton()
    private var removeAction: (() -> Void)?
    private var removalAppID: String?
    private var editing = false
    private weak var appearanceStore: LayoutStore?
    private var representedAppID: String?
    private var representedApps: [LaunchApp] = []
    private(set) var dragContentSuppressed = false
    private(set) var groupID = ""
    func containsRemovalPoint(_ point: NSPoint) -> Bool { !removeButton.isHidden && removeButton.frame.contains(point) }
    func containsActivationPoint(_ point: NSPoint) -> Bool {
        if folder, let glass = folderGlass {
            return Self.folderContains(point, frame: glass.frame, radius: glass.cornerRadius)
        }
        if iconView.frame.contains(point) { return true }
        guard !titleField.isHidden else { return false }
        let textWidth = min(titleField.frame.width, titleField.intrinsicContentSize.width)
        let label = NSRect(x: titleField.frame.midX - textWidth / 2, y: titleField.frame.minY,
                           width: textWidth, height: titleField.frame.height)
        return label.contains(point)
    }

    static func folderContains(_ point: NSPoint, frame: NSRect, radius: CGFloat) -> Bool {
        NSBezierPath(roundedRect: frame, xRadius: radius, yRadius: radius).contains(point)
    }

    override var draggingImageComponents: [NSDraggingImageComponent] {
        // The default collection-view snapshot includes the whole transparent
        // cell. Screen recording can expose that compositing rectangle while a
        // folder is open, so use the native app icon as the sole drag component.
        guard !folder, let image = iconView.image else {
            return super.draggingImageComponents
        }
        let icon = NSDraggingImageComponent(key: .icon)
        icon.contents = image
        icon.frame = iconView.frame
        return [icon]
    }

    var appDragPreview: (image: NSImage, frame: NSRect)? {
        guard !folder, let image = iconView.image else { return nil }
        return (image.copy() as? NSImage ?? image, iconView.frame)
    }

    override func loadView() {
        view = NSView()
        view.wantsLayer = true
        contentView.wantsLayer = true
        view.addSubview(contentView)
        NotificationCenter.default.addObserver(self, selector: #selector(refreshIcons(_:)), name: .launchpadIconReady, object: nil)

        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.wantsLayer = true
        contentView.addSubview(iconView)

        titleField.alignment = .center
        titleField.font = .systemFont(ofSize: 13, weight: .regular)
        titleField.textColor = .white
        titleField.maximumNumberOfLines = 2
        titleField.lineBreakMode = .byTruncatingTail
        titleField.cell?.wraps = true
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.44)
        shadow.shadowBlurRadius = 3
        shadow.shadowOffset = NSSize(width: 0, height: -1)
        titleField.shadow = shadow
        titleField.wantsLayer = true
        contentView.addSubview(titleField)

        removeButton.isBordered = false
        removeButton.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: "卸载应用")?
            .withSymbolConfiguration(.init(pointSize: 10, weight: .bold))
        removeButton.contentTintColor = .black
        removeButton.wantsLayer = true
        removeButton.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.92).cgColor
        removeButton.layer?.cornerRadius = 12
        removeButton.layer?.borderColor = NSColor.black.withAlphaComponent(0.12).cgColor
        removeButton.layer?.borderWidth = 0.5
        removeButton.target = self
        removeButton.action = #selector(removeApplication)
        removeButton.isHidden = true
        contentView.addSubview(removeButton)
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        guard lastLayoutSize != view.bounds.size else { return }
        lastLayoutSize = view.bounds.size
        contentView.frame = view.bounds
        let size = metrics.iconSize
        // NSCollectionView items are unflipped; put the glyph at the top of each cell.
        let iconY = view.bounds.height - metrics.iconTop - size
        iconView.frame = NSRect(x: (view.bounds.width - size) / 2, y: iconY, width: size, height: size)
        let folderSize = size * 0.82
        if let folderGlass {
            folderGlass.frame = NSRect(x: (view.bounds.width - folderSize) / 2,
                                      y: iconY + (size - folderSize) / 2,
                                      width: folderSize, height: folderSize)
            folderGlass.cornerRadius = folderSize * 0.235
            folderContent.frame = folderGlass.bounds
            let inset = folderSize * 0.10
            let pitch = (folderSize - inset * 2) / 3
            for (index, mini) in miniIcons.enumerated() {
                mini.frame = NSRect(x: inset + CGFloat(index % 3) * pitch,
                                    y: inset + CGFloat(2 - index / 3) * pitch,
                                    width: pitch, height: pitch)
            }
        }
        titleField.frame = NSRect(x: 5, y: max(0, iconY - 29), width: view.bounds.width - 10, height: 28)
        selectionGlass?.frame = iconView.frame.insetBy(dx: -6, dy: -6)
        removeButton.frame = NSRect(x: iconView.frame.minX + 2, y: iconView.frame.maxY - 24, width: 24, height: 24)
    }

    func configure(with group: LaunchGroup, store: LayoutStore, metrics: GridMetrics) {
        appearanceStore = store
        representedApps = group.apps
        representedAppID = group.isFolder ? nil : group.apps.first?.id
        if groupID != group.id { setMergeTarget(false) }
        self.metrics = metrics
        lastLayoutSize = nil
        groupID = group.id
        folder = group.isFolder
        titleField.stringValue = group.displayName
        titleField.isHidden = !metrics.showNames
        titleField.setAccessibilityLabel(group.displayName)
        view.setAccessibilityLabel(group.displayName)
        if folder && folderGlass == nil {
            let glass = NSGlassEffectView()
            glass.wantsLayer = true
            glass.style = .regular
            glass.appearance = NSAppearance(named: .darkAqua)
            glass.contentView = folderContent
            contentView.addSubview(glass, positioned: .above, relativeTo: iconView)
            folderGlass = glass
            for _ in 0..<9 {
                let mini = NSImageView()
                mini.imageScaling = .scaleProportionallyUpOrDown
                folderContent.addSubview(mini)
                miniIcons.append(mini)
            }
        }
        folderGlass?.isHidden = !folder
        iconView.isHidden = folder
        if folder {
            for (index, mini) in miniIcons.enumerated() {
                mini.image = index < group.apps.count
                    ? ApplicationIconCache.shared.image(for: group.apps[index], store: store) : nil
            }
        } else if let app = group.apps.first {
            iconView.image = ApplicationIconCache.shared.image(for: app, store: store)
        }
        view.needsLayout = true
        refreshDragAppearance()
    }

    @objc private func refreshIcons(_ event: Notification) {
        guard let store = appearanceStore else { return }
        let key = event.object as? String
        // A recycled item reads its current identity, never a captured old index.
        if folder {
            for (index, mini) in miniIcons.enumerated() where representedApps.indices.contains(index) {
                let app = representedApps[index]
                if key == nil || key == ApplicationIconCache.key(app) {
                    mini.image = ApplicationIconCache.shared.image(for: app, store: store)
                }
            }
        } else if let app = representedApps.first, key == nil || key == ApplicationIconCache.key(app) {
            iconView.image = ApplicationIconCache.shared.image(for: app, store: store)
        }
    }

    func refreshDragAppearance() {
        dragContentSuppressed = appearanceStore?.suppressesDragContent(appID: representedAppID) == true
        // AppKit owns the root item's drag visibility and position animations.
        // Keep it and its hit/layout geometry intact; suppress only our content.
        let alpha: CGFloat = dragContentSuppressed ? 0 : 1
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for content in [iconView, titleField, removeButton, folderGlass, selectionGlass].compactMap({ $0 }) {
            content.alphaValue = alpha
        }
        CATransaction.commit()
    }

    func setEditing(_ active: Bool, app: LaunchApp?, store: LayoutStore) {
        defer { refreshDragAppearance() }
        let eligibilityChanged = active != editing || removalAppID != app?.id
        editing = active
        if eligibilityChanged {
            removalAppID = app?.id
            removeButton.isHidden = !active || app.flatMap { ApplicationRemoval.removableURL(for: $0, store: store) } == nil
            removeButton.setAccessibilityLabel(app.map { "卸载“\($0.name)”" } ?? "卸载应用")
            removeAction = app.map { app in { [weak self, weak store] in
                guard let store else { return }
                ApplicationRemoval.confirm(app, store: store, window: self?.view.window)
            } }
        }
        if active && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            if contentView.layer?.animation(forKey: "editingWiggle") == nil {
                let animation = CAKeyframeAnimation(keyPath: "transform.rotation.z")
                animation.values = [-0.018, 0.018, -0.018]
                animation.duration = 0.28
                animation.repeatCount = .infinity
                animation.timeOffset = Double(abs(groupID.hashValue % 11)) * 0.018
                contentView.layer?.add(animation, forKey: "editingWiggle")
            }
        } else {
            contentView.layer?.removeAnimation(forKey: "editingWiggle")
        }
    }

    private var mergeTargeted = false
    func animateReflow(from origin: CGPoint) {
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
              let layer = view.layer else { return }
        let offset = CGPoint(x: origin.x - view.frame.minX, y: origin.y - view.frame.minY)
        guard hypot(offset.x, offset.y) > 0.5 else { return }
        let animation = CABasicAnimation(keyPath: "position")
        animation.fromValue = NSValue(point: CGPoint(x: layer.position.x + offset.x, y: layer.position.y + offset.y))
        animation.toValue = NSValue(point: layer.position)
        animation.duration = 0.22
        animation.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.8, 0.2, 1)
        layer.add(animation, forKey: "gridReflow")
    }

    func setMergeTarget(_ targeted: Bool) {
        guard targeted != mergeTargeted else { return }
        mergeTargeted = targeted
        guard let layer = view.layer else { return }
        let scale: CGFloat = targeted ? 1.14 : 1
        // Scale the entire tile around its centre, independently of its wiggle.
        let anchor = layer.anchorPoint
        let dx = (0.5 - anchor.x) * layer.bounds.width * (1 - scale)
        let dy = (0.5 - anchor.y) * layer.bounds.height * (1 - scale)
        let target = CATransform3DConcat(CATransform3DMakeScale(scale, scale, 1), CATransform3DMakeTranslation(dx, dy, 0))
        let animation = CABasicAnimation(keyPath: "transform")
        animation.fromValue = NSValue(caTransform3D: layer.presentation()?.transform ?? layer.transform)
        animation.toValue = NSValue(caTransform3D: target)
        animation.duration = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : 0.18
        animation.timingFunction = CAMediaTimingFunction(name: .easeOut)
        CATransaction.begin(); CATransaction.setDisableActions(true)
        layer.transform = target
        layer.add(animation, forKey: "dragEmphasis")
        CATransaction.commit()
    }

    @objc private func removeApplication() { removeAction?() }

    func setKeyboardSelected(_ selected: Bool) {
        defer { refreshDragAppearance() }
        guard keyboardSelected != selected else { return }
        keyboardSelected = selected
        if selected && selectionGlass == nil {
            let glass = NSGlassEffectView()
            glass.style = .clear
            glass.cornerRadius = 24
            glass.contentView = NSView()
            glass.frame = iconView.frame.insetBy(dx: -6, dy: -6)
            contentView.addSubview(glass, positioned: .below, relativeTo: iconView)
            selectionGlass = glass
        }
        selectionGlass?.isHidden = !selected
    }
}

private extension NSUserInterfaceItemIdentifier {
    static let launchpadItem = NSUserInterfaceItemIdentifier("iLaunchPad.collection-item")
}

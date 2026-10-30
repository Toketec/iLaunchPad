import SwiftUI
import UniformTypeIdentifiers

enum DragPayload: Equatable {
    case group(String)
    case folderApp(appID: String, folderID: String)
}

struct GroupReorderDropDelegate: DropDelegate {
    let targetID: String
    let side: DropSide
    let store: LayoutStore
    @Binding var dragging: DragPayload?

    func validateDrop(info: DropInfo) -> Bool {
        if case .group(let id) = dragging { return id != targetID }
        return false
    }

    func performDrop(info: DropInfo) -> Bool {
        guard case .group(let sourceID) = dragging else { return false }
        store.moveGroup(sourceID, relativeTo: targetID, side: side)
        dragging = nil
        return true
    }
}

struct GroupIntoDropDelegate: DropDelegate {
    let targetID: String
    let store: LayoutStore
    @Binding var dragging: DragPayload?

    func validateDrop(info: DropInfo) -> Bool {
        if case .group(let id) = dragging { return id != targetID }
        return false
    }

    func performDrop(info: DropInfo) -> Bool {
        guard case .group(let sourceID) = dragging else { return false }
        store.dropGroup(sourceID, into: targetID)
        dragging = nil
        return true
    }
}

struct PageDropDelegate: DropDelegate {
    let targetPage: Int
    let store: LayoutStore
    @Binding var currentPage: Int
    @Binding var dragging: DragPayload?

    func validateDrop(info: DropInfo) -> Bool {
        dragging != nil && store.isPreviewingDrag
    }

    func dropEntered(info: DropInfo) {
        currentPage = targetPage
    }

    func performDrop(info: DropInfo) -> Bool {
        guard let payload = dragging,
              let sourceID = store.previewMoveToPage(payload, page: targetPage) else { return false }
        store.moveGroup(sourceID, toPage: targetPage)
        store.finishDragPreview(commit: true)
        dragging = nil
        return true
    }
}

struct FolderAppReorderDropDelegate: DropDelegate {
    let targetID: String
    let folderID: String
    let side: DropSide
    let store: LayoutStore
    @Binding var dragging: DragPayload?

    func validateDrop(info: DropInfo) -> Bool {
        if case .folderApp(let appID, let sourceFolder) = dragging {
            return sourceFolder == folderID && appID != targetID
        }
        return false
    }

    func performDrop(info: DropInfo) -> Bool {
        guard case .folderApp(let appID, let sourceFolder) = dragging,
              sourceFolder == folderID else { return false }
        store.moveAppInsideFolder(appID, folderID: folderID, relativeTo: targetID, side: side)
        dragging = nil
        return true
    }
}

extension View {
    func launchpadDragProvider(_ payload: DragPayload, dragging: Binding<DragPayload?>) -> some View {
        onDrag {
            dragging.wrappedValue = payload
            let value: String
            switch payload {
            case .group(let id): value = "group:\(id)"
            case .folderApp(let appID, let folderID): value = "folder:\(folderID):\(appID)"
            }
            return NSItemProvider(object: value as NSString)
        }
    }
}

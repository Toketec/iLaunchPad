import SwiftUI
import UniformTypeIdentifiers

struct FolderOverlay: View {
    @ObservedObject private var store = LayoutStore.shared
    let folderID: String
    let currentPage: Int
    @Binding var dragging: DragPayload?
    let expanded: Bool
    let sourceFrame: CGRect
    let keyboardSelection: Int?
    let onClose: () -> Void
    let onCollapsed: () -> Void
    let onOpenApp: (LaunchApp) -> Void
    @State private var folderName = ""
    @State private var nameFocused = false

    var body: some View {
        GeometryReader { geometry in
            let apps = store.group(id: folderID)?.apps ?? []
            let panelWidth = min(1120, geometry.size.width * 0.80)
            let rows = max(1, Int(ceil(Double(apps.count) / 7)))
            let contentHeight = CGFloat(rows) * 168
            let panelHeight = min(geometry.size.height * 0.65, contentHeight + 48)
            let metrics = GridMetrics(width: panelWidth - 80, height: contentHeight,
                                      columns: 7, rows: rows, fixedIconSize: 100)
            let groups = apps.map { LaunchGroup(id: $0.id, name: "", isFolder: false, apps: [$0]) }
            let targetCenter = CGPoint(x: geometry.size.width / 2, y: geometry.size.height * 0.47)
            let targetFrame = CGRect(x: targetCenter.x - panelWidth / 2,
                                     y: targetCenter.y - panelHeight / 2,
                                     width: panelWidth, height: panelHeight)
            ZStack(alignment: .topLeading) {
                Color.black.opacity(0.001)
                    .contentShape(Rectangle())
                    .onTapGesture(perform: onClose)
                    .onDrop(of: [UTType.text.identifier], isTargeted: nil) { _ in
                        DragTracking.trace("folder.background-drop payload=\(dragging != nil)", store: store)
                        guard let payload = dragging, store.isPreviewingDrag else { return false }
                        return DragTracking.drop(NSEvent.mouseLocation, store: store, payload: payload)
                    }

                FolderMorphSurface(size: targetFrame.size, source: sourceFrame,
                                   destination: targetFrame, expanded: expanded, onCollapsed: onCollapsed,
                                   dropStore: store, dropFolderID: folderID) {
                    NativeLaunchGrid(groups: groups, store: store, allowsReordering: true,
                                     dragging: $dragging, onOpenFolder: { _ in }, onOpenApp: onOpenApp,
                                     metrics: metrics,
                                     keyboardSelection: keyboardSelection.flatMap { apps.indices.contains($0) ? apps[$0].id : nil },
                                     onBackgroundClick: { NSApp.keyWindow?.makeFirstResponder(nil); nameFocused = false }, folderID: folderID,
                                     folderDestinationPage: currentPage)
                    .frame(width: panelWidth - 80, height: panelHeight - 48)
                    .padding(.horizontal, 40).padding(.vertical, 24)
                    .frame(width: panelWidth, height: panelHeight)
                }
                .frame(width: panelWidth, height: panelHeight)
                .position(targetCenter)

                FolderDragBoundary(panel: targetFrame, active: expanded && dragging != nil, folderID: folderID) {
                    guard let payload = dragging else { return }
                    store.previewMoveToPage(payload, page: currentPage)
                    onClose()
                }
                .frame(width: geometry.size.width, height: geometry.size.height)
                .allowsHitTesting(false)

                FolderNameField(text: $folderName, focused: $nameFocused, store: store,
                                folderID: folderID, enabled: expanded && dragging == nil,
                                request: store.folderNamingRequest, onSave: saveName)
                    .frame(width: min(360, panelWidth - 48), height: 30)
                    .opacity(expanded ? 1 : 0)
                    .position(x: targetCenter.x, y: targetFrame.minY - 28)
            }
            .allowsHitTesting(expanded)
        }
        .onAppear { folderName = store.group(id: folderID)?.displayName ?? "未命名" }
        .onChange(of: nameFocused) { _, focused in if !focused { saveName() } }
        .onDisappear { saveName() }
        .onChange(of: store.group(id: folderID)?.isFolder != true) { _, missing in if missing { onClose() } }
    }

    private func saveName() {
        guard !store.isPreviewingDrag, store.group(id: folderID)?.isFolder == true else { return }
        let trimmed = folderName.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = trimmed.isEmpty ? (store.group(id: folderID)?.displayName ?? "未命名") : trimmed
        if store.group(id: folderID)?.name != name {
            store.renameFolder(folderID, name: name)
        }
        folderName = name
    }

}

/// Use the system field editor for selection, marked text and Escape handling.
struct FolderNameField: NSViewRepresentable {
    @Binding var text: String
    @Binding var focused: Bool
    let store: LayoutStore
    let folderID: String
    let enabled: Bool
    let request: LayoutStore.FolderNamingRequest?
    let onSave: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField(string: text)
        field.placeholderString = "文件夹名称"
        field.isBordered = false
        field.drawsBackground = false
        field.font = .systemFont(ofSize: 20)
        field.textColor = .white
        field.alignment = .center
        field.focusRingType = .none
        field.delegate = context.coordinator
        return field
    }
    func updateNSView(_ field: NSTextField, context: Context) {
        context.coordinator.parent = self
        field.isEditable = enabled
        field.isSelectable = enabled
        if field.currentEditor() == nil, field.stringValue != text { field.stringValue = text }
        guard enabled, let request, request.folderID == folderID else { return }
        DispatchQueue.main.async { [weak field] in
            guard let field, let window = field.window, field.isEditable,
                  store.folderNamingRequest == request, !store.isPreviewingDrag,
                  store.group(id: folderID)?.isFolder == true,
                  window.makeFirstResponder(field),
                  store.consumeFolderNamingRequest(request) else { return }
            focused = true
            field.selectText(nil)
        }
    }
    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: FolderNameField
        init(_ parent: FolderNameField) { self.parent = parent }
        func controlTextDidBeginEditing(_ obj: Notification) { parent.focused = true }
        func controlTextDidChange(_ obj: Notification) {
            if let field = obj.object as? NSTextField { parent.text = field.stringValue }
        }
        func controlTextDidEndEditing(_ obj: Notification) {
            parent.focused = false
            parent.onSave()
        }
        func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            if selector == #selector(NSResponder.cancelOperation(_:)) || selector == #selector(NSResponder.insertNewline(_:)) {
                control.window?.makeFirstResponder(nil)
                return true
            }
            return false
        }
    }
}

struct LaunchIconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.93 : 1)
            .opacity(configuration.isPressed ? 0.8 : 1)
            .animation(.smooth(duration: 0.13), value: configuration.isPressed)
    }
}

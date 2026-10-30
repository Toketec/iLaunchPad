import AppKit
import SwiftUI

struct NativeSearchField: NSViewRepresentable {
    @Binding var text: String
    let onSubmit: () -> Void
    var focusRequest: Int = 0
    var enabled = true

    func makeCoordinator() -> Coordinator { Coordinator(text: $text, onSubmit: onSubmit) }

    func makeNSView(context: Context) -> NSSearchField {
        let field = NSSearchField()
        // The capsule supplies one SF Symbol outside the editable text bounds.
        // Borderless NSSearchField otherwise draws its own icon over the text.
        (field.cell as? NSSearchFieldCell)?.searchButtonCell = nil
        field.appearance = NSAppearance(named: .darkAqua)
        field.placeholderString = "搜索应用程序"
        field.font = .systemFont(ofSize: 13, weight: .regular)
        field.textColor = .white
        field.controlSize = .regular
        field.isBezeled = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.sendsSearchStringImmediately = true
        field.sendsWholeSearchString = false
        field.delegate = context.coordinator
        field.target = context.coordinator
        field.action = #selector(Coordinator.searchChanged(_:))
        DispatchQueue.main.async { field.window?.makeFirstResponder(field) }
        return field
    }

    func updateNSView(_ nsView: NSSearchField, context: Context) {
        context.coordinator.onSubmit = onSubmit
        nsView.isEnabled = enabled
        if nsView.stringValue != text { nsView.stringValue = text }
        if enabled, context.coordinator.focusRequest != focusRequest {
            context.coordinator.focusRequest = focusRequest
            DispatchQueue.main.async { nsView.window?.makeFirstResponder(nsView) }
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSSearchFieldDelegate {
        private var text: Binding<String>
        var onSubmit: () -> Void
        var focusRequest = -1

        init(text: Binding<String>, onSubmit: @escaping () -> Void) {
            self.text = text
            self.onSubmit = onSubmit
        }

        @objc func searchChanged(_ sender: NSSearchField) {
            text.wrappedValue = sender.stringValue
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSSearchField else { return }
            text.wrappedValue = field.stringValue
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
                NotificationCenter.default.post(name: .launchpadEscape, object: nil)
                return true
            }
            guard commandSelector == #selector(NSResponder.insertNewline(_:)) else { return false }
            onSubmit()
            return true
        }
    }
}

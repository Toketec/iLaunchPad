import AppKit
import SwiftUI

struct VisualEffectView: NSViewRepresentable {
    var withinWindow = false
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .fullScreenUI
        view.blendingMode = withinWindow ? .withinWindow : .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

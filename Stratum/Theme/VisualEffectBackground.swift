import SwiftUI
import AppKit

struct VisualEffectBackground: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .sidebar
    var blendingMode: NSVisualEffectView.BlendingMode = .behindWindow
    var state: NSVisualEffectView.State = .followsWindowActiveState
    var isEmphasized: Bool = false

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = state
        view.isEmphasized = isEmphasized
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        let appearance = AppearanceManager.shared
        if appearance.reduceTransparency || !appearance.enableBlur {
            nsView.material = .windowBackground
            nsView.blendingMode = .withinWindow
        } else {
            nsView.material = material
            nsView.blendingMode = blendingMode
        }
        nsView.state = state
        nsView.isEmphasized = isEmphasized
    }
}

import AppKit
import SwiftUI

/// A behind-window material samples the desktop and other windows as the panel moves.
struct WindowGlass: NSViewRepresentable {
    var reduceTransparency: Bool

    final class Backdrop: NSVisualEffectView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window else { return }
            window.isOpaque = false
            window.backgroundColor = .clear
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.isMovableByWindowBackground = true
            window.hasShadow = true
        }
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }

    func makeNSView(context: Context) -> Backdrop {
        let view = Backdrop()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        view.appearance = NSAppearance(named: .darkAqua)
        return view
    }

    func updateNSView(_ view: Backdrop, context: Context) {
        view.alphaValue = reduceTransparency ? 0 : 0.63
    }
}

enum GlassInk {
    static let blue = Color(red: 0.035, green: 0.48, blue: 1)
    static let capsule = Color.white.opacity(0.16)
    static let secondary = Color.white.opacity(0.80)
}

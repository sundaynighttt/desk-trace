import AppKit
import SwiftUI

/// A behind-window material samples the desktop and other windows as the panel moves.
struct WindowGlass: NSViewRepresentable {
    var reduceTransparency: Bool

    final class Backdrop: NSVisualEffectView {
        private var needsOpeningFit = true

        override func viewWillMove(toWindow newWindow: NSWindow?) {
            if let window { NotificationCenter.default.removeObserver(self, name: nil, object: window) }
            super.viewWillMove(toWindow: newWindow)
            needsOpeningFit = true
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window else { return }
            window.isOpaque = false
            window.backgroundColor = .clear
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.isMovableByWindowBackground = true
            window.hasShadow = true
            let center = NotificationCenter.default
            center.addObserver(self, selector: #selector(fitWhenVisible), name: NSWindow.didUpdateNotification, object: window)
            center.addObserver(self, selector: #selector(prepareForReopening), name: NSWindow.willCloseNotification, object: window)
            DispatchQueue.main.async { [weak self] in self?.fitWhenVisible() }
        }

        @objc private func prepareForReopening() { needsOpeningFit = true }

        @objc private func fitWhenVisible() {
            guard needsOpeningFit, let window, window.isVisible else { return }
            needsOpeningFit = false
            guard !window.styleMask.contains(.fullScreen) else { return }
            // Restoration can override the SwiftUI scene's default size. Fit only on opening,
            // keeping the restored width and top edge and allowing later manual resizing.
            let old = window.frame
            let chrome = old.height - window.contentLayoutRect.height
            let height = max(window.minSize.height, GalleryLayout.minimumHeight + chrome)
            guard abs(old.height - height) >= 1 else { return }
            window.setFrame(NSRect(x: old.minX, y: old.maxY-height, width: old.width, height: height),
                            display: true)
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

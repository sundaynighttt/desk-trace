import AppKit
import SwiftUI

/// A behind-window material samples the desktop and other windows as the panel moves.
struct WindowGlass: NSViewRepresentable {
    var reduceTransparency: Bool
    var mode: GalleryMode
    var onPresentationChange: (Bool) -> Void

    final class Backdrop: NSVisualEffectView {
        private var needsOpeningFit = true
        private var visibilityObservation: NSKeyValueObservation?

        var mode: GalleryMode = .standard {
            didSet {
                guard mode != oldValue else { return }
                needsOpeningFit = true
                DispatchQueue.main.async { [weak self] in self?.fitWhenVisible() }
            }
        }
        var onPresentationChange: ((Bool) -> Void)?

        override func viewWillMove(toWindow newWindow: NSWindow?) {
            visibilityObservation = nil
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
            // A retained gallery can be ordered front again without becoming the key window.
            visibilityObservation = window.observe(\.isVisible, options: [.new]) { [weak self] _, change in
                if change.newValue == true {
                    DispatchQueue.main.async { self?.fitWhenVisible() }
                }
            }
            center.addObserver(self, selector: #selector(prepareForReopening), name: NSWindow.willCloseNotification, object: window)
            DispatchQueue.main.async { [weak self] in self?.fitWhenVisible() }
        }

        @objc private func prepareForReopening() {
            needsOpeningFit = true
            onPresentationChange?(false)
        }

        @objc private func fitWhenVisible() {
            guard needsOpeningFit, let window, window.isVisible else { return }
            needsOpeningFit = false
            onPresentationChange?(true)
            guard !window.styleMask.contains(.fullScreen) else { return }
            // Restoration can override the SwiftUI scene's default size. Fit only on opening,
            // keeping the restored width and top edge and allowing later manual resizing.
            let old = window.frame
            let chrome = old.height - window.contentLayoutRect.height
            let target = mode == .mini ? GalleryLayout.minimumHeight : GalleryLayout.standardOpeningHeight(windowWidth: window.contentLayoutRect.width)
            let height = min(window.screen?.visibleFrame.height ?? .greatestFiniteMagnitude,
                             max(window.minSize.height, target + chrome))
            guard abs(old.height - height) >= 1 else { return }
            let visible = window.screen?.visibleFrame
            let bottom = max(visible?.minY ?? old.maxY-height, old.maxY-height)
            window.setFrame(NSRect(x: old.minX, y: bottom, width: old.width, height: height),
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
        view.mode = mode
        view.onPresentationChange = onPresentationChange
        view.alphaValue = reduceTransparency ? 0 : 0.63
    }
}

enum GlassInk {
    static let blue = Color(red: 0.035, green: 0.48, blue: 1)
    static let capsule = Color.white.opacity(0.16)
    static let secondary = Color.white.opacity(0.80)
}

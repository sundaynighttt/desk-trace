import AppKit
import SwiftUI

enum DeskTraceBrand {
    private static let largeFace: CGPath = {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 8.7, y: 1.1))
        path.addCurve(to: CGPoint(x: 1, y: 10), control1: CGPoint(x: 4.3, y: 1.8), control2: CGPoint(x: 1, y: 5.5))
        path.addCurve(to: CGPoint(x: 10.1, y: 19), control1: CGPoint(x: 1, y: 15), control2: CGPoint(x: 5.1, y: 19))
        path.addCurve(to: CGPoint(x: 19, y: 11.3), control1: CGPoint(x: 14.6, y: 19), control2: CGPoint(x: 18.4, y: 15.7))
        path.addCurve(to: CGPoint(x: 8.7, y: 1.1), control1: CGPoint(x: 13.5, y: 11.5), control2: CGPoint(x: 7.9, y: 6.8))
        path.closeSubpath()
        return path
    }()

    private static let smallFace: CGPath = {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 10.2, y: 1))
        path.addCurve(to: CGPoint(x: 19.1, y: 10), control1: CGPoint(x: 15.1, y: 1.1), control2: CGPoint(x: 19, y: 5.1))
        path.addCurve(to: CGPoint(x: 10.2, y: 1), control1: CGPoint(x: 14, y: 10.1), control2: CGPoint(x: 9.6, y: 5.9))
        path.closeSubpath()
        return path
    }()

    static let menuOutline = image(size: 18, template: true, filled: false)
    static let menuFilled = image(size: 18, template: true, filled: true)
    static let title = image(size: 15, template: false, filled: true)

    private static func image(size: CGFloat, template: Bool, filled: Bool) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size), flipped: true) { rect in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            context.saveGState()
            defer { context.restoreGState() }
            context.translateBy(x: rect.minX, y: rect.minY)
            context.scaleBy(x: rect.width / 20, y: rect.height / 20)
            context.setStrokeColor(NSColor.black.cgColor)
            context.setLineWidth(1.15)
            context.setLineJoin(.round)
            let red = NSColor(srgbRed: 1, green: 0.20, blue: 0.18, alpha: 1)
            let light = NSColor(srgbRed: 0.94, green: 0.94, blue: 0.97, alpha: 1)
            for (face, color) in [(largeFace, red), (smallFace, light)] {
                context.addPath(face)
                if filled {
                    context.setFillColor((template ? NSColor.black : color).cgColor)
                    context.fillPath()
                } else {
                    context.strokePath()
                }
            }
            return true
        }
        image.isTemplate = template
        return image
    }
}

struct DeskTraceWindowTitle: View {
    var body: some View {
        GeometryReader { geometry in
            let titleHeight = geometry.safeAreaInsets.top
            if titleHeight >= 18 {
                HStack(spacing: 6) {
                    Image(nsImage: DeskTraceBrand.title).accessibilityHidden(true)
                    Text("자리기록").font(.system(size: 13, weight: .semibold))
                }
                .foregroundStyle(.white.opacity(0.94))
                .frame(width: geometry.size.width, height: titleHeight)
                .offset(y: -titleHeight)
            }
        }
        .allowsHitTesting(false)
    }
}

import AppKit

let folder = URL(fileURLWithPath: CommandLine.arguments[1])
try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
for side in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let px = side * scale
        let c = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: px*4,
                          space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        c.scaleBy(x: CGFloat(px)/100, y: CGFloat(px)/100)
        c.setFillColor(CGColor(srgbRed: 0.08, green: 0.20, blue: 0.20, alpha: 1))
        c.addPath(CGPath(roundedRect: CGRect(x: 5, y: 5, width: 90, height: 90), cornerWidth: 21, cornerHeight: 21, transform: nil))
        c.fillPath()
        c.setStrokeColor(CGColor(srgbRed: 0.66, green: 0.91, blue: 0.79, alpha: 1))
        c.setLineWidth(4.5)
        c.setLineCap(.round)
        c.setLineJoin(.round)
        for (x,y,dx,dy) in [(25,30,1,1),(75,30,-1,1),(25,70,1,-1),(75,70,-1,-1)] {
            c.move(to: CGPoint(x:x+dx*10,y:y)); c.addLine(to:CGPoint(x:x,y:y))
            c.addLine(to:CGPoint(x:x,y:y+dy*10)); c.strokePath()
        }
        c.setFillColor(CGColor(srgbRed: 0.94, green: 0.73, blue: 0.44, alpha: 1))
        c.fillEllipse(in: CGRect(x: 40, y: 40, width: 20, height: 20))
        let png = NSBitmapImageRep(cgImage: c.makeImage()!).representation(using: .png, properties: [:])!
        let name = "icon_\(side)x\(side)" + (scale == 2 ? "@2x.png" : ".png")
        try png.write(to: folder.appendingPathComponent(name))
    }
}

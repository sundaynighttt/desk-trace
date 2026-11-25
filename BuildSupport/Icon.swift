import AppKit
import ImageIO

let arguments = CommandLine.arguments
guard arguments.count == 3 else {
    fputs("Usage: Icon.swift <source.png> <output.iconset>\n", stderr)
    exit(1)
}

let source = URL(fileURLWithPath: arguments[1])
let folder = URL(fileURLWithPath: arguments[2])
guard let imageSource = CGImageSourceCreateWithURL(source as CFURL, nil),
      let image = CGImageSourceCreateImageAtIndex(imageSource, 0, nil),
      image.width == 1024, image.height == 1024 else {
    fputs("Expected a 1024 × 1024 PNG at \(source.path)\n", stderr)
    exit(1)
}

try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!

for side in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = side * scale
        let context = CGContext(
            data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0,
            space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: pixels, height: pixels))
        let png = NSBitmapImageRep(cgImage: context.makeImage()!).representation(using: .png, properties: [:])!
        let name = "icon_\(side)x\(side)" + (scale == 2 ? "@2x.png" : ".png")
        try png.write(to: folder.appendingPathComponent(name))
    }
}

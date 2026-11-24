import AppKit
import CWebP
import ImageIO

enum CaptureKind: String {
    case camera, screen
    var title: String { self == .camera ? "카메라 사진" : "화면 캡처" }
    var symbol: String { self == .camera ? "camera" : "display" }
}

struct CaptureRecord: Identifiable, Equatable {
    let url: URL
    let date: Date
    let kind: CaptureKind
    var id: URL { url }

    init?(url: URL) {
        guard url.pathExtension == "webp" else { return nil }
        let parts = url.deletingPathExtension().lastPathComponent.split(separator: "_")
        guard parts.count == 3, let stamp = Int64(parts[0]), let kind = CaptureKind(rawValue: String(parts[1])),
              UUID(uuidString: String(parts[2])) != nil else { return nil }
        self.url = URL(fileURLWithPath: url.path, isDirectory: false).standardizedFileURL
        self.date = Date(timeIntervalSince1970: Double(stamp) / 1000)
        self.kind = kind
    }
}

struct AppProblem: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

struct RecordStore {
    let folder: URL
    static var standard: RecordStore {
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return RecordStore(folder: root.appendingPathComponent("DeskTrace/Captures", isDirectory: true))
    }

    func prepare() throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true,
                                               attributes: [.posixPermissions: 0o700])
    }

    func readAll() throws -> [CaptureRecord] {
        guard FileManager.default.fileExists(atPath: folder.path) else { return [] }
        return try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil,
                                                           options: .skipsHiddenFiles)
            .compactMap(CaptureRecord.init).sorted { $0.url.lastPathComponent > $1.url.lastPathComponent }
    }

    func save(_ data: Data, kind: CaptureKind, at date: Date) throws -> CaptureRecord {
        try prepare()
        let millis = Int64((date.timeIntervalSince1970 * 1000).rounded())
        let url = folder.appendingPathComponent("\(millis)_\(kind.rawValue)_\(UUID().uuidString).webp")
        try data.write(to: url, options: .atomic)
        return CaptureRecord(url: url)!
    }
}

enum Picture {
    static func size(width: Int, height: Int) -> (Int, Int) {
        let ratio = min(1, 1024.0 / Double(max(1, max(width, height))))
        return (max(1, Int((Double(width) * ratio).rounded())), max(1, Int((Double(height) * ratio).rounded())))
    }

    static func encode(_ image: CGImage) throws -> Data {
        let (w, h) = size(width: image.width, height: image.height)
        guard let context = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w*4,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue),
              let pixels = context.data else { throw AppProblem("이미지 크기를 조절할 수 없습니다.") }
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: w, height: h))
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        var output: UnsafeMutablePointer<UInt8>?
        let bytes = pixels.assumingMemoryBound(to: UInt8.self)
        let count = WebPEncodeRGBA(bytes, Int32(w), Int32(h), Int32(w*4), 76, &output)
        guard count > 0, let output else { throw AppProblem("WebP 이미지 저장 형식으로 변환하지 못했습니다.") }
        defer { WebPFree(output) }
        return Data(bytes: output, count: count)
    }

    // Capture URLs are unique and immutable. Read only the header for layout, before decoding a visible tile.
    private static let aspectRatios = NSCache<NSURL, NSNumber>()

    static func aspectRatio(at url: URL) -> CGFloat? {
        if let cached = aspectRatios.object(forKey: url as NSURL) { return CGFloat(cached.doubleValue) }
        let options = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(url as CFURL, options),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, options) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0 else { return nil }
        let rotated = (5...8).contains(properties[kCGImagePropertyOrientation] as? Int ?? 1)
        let ratio = rotated ? CGFloat(height) / CGFloat(width) : CGFloat(width) / CGFloat(height)
        aspectRatios.setObject(NSNumber(value: Double(ratio)), forKey: url as NSURL)
        return ratio
    }

    static func thumbnail(at url: URL, pixels: Int) -> NSImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: pixels,
                kCGImageSourceCreateThumbnailWithTransform: true
              ] as CFDictionary) else { return nil }
        return NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
    }
}

struct MotionGate {
    private var previous: [UInt8]?
    private var lastShot: TimeInterval?
    let interval: TimeInterval

    init(minutes: Int, lastMotion: Date? = nil) {
        interval = Double(min(60, max(10, minutes))) * 60
        if let lastMotion {
            let elapsed = max(0, Date().timeIntervalSince(lastMotion))
            lastShot = ProcessInfo.processInfo.systemUptime - elapsed
        }
    }

    mutating func shouldCapture(_ luma: [UInt8], at now: TimeInterval) -> Bool {
        defer { previous = luma }
        guard let old = previous, old.count == luma.count, !luma.isEmpty else { return false }
        if let lastShot, now - lastShot < interval { return false }
        // Remove a uniform lighting shift before counting pixels that moved.
        var diffs = [Int]()
        diffs.reserveCapacity(luma.count)
        for i in luma.indices { diffs.append(Int(luma[i]) - Int(old[i])) }
        let ambient = diffs.sorted()[diffs.count/2]
        let changed = diffs.reduce(0) { $0 + (abs($1 - ambient) >= 18 ? 1 : 0) }
        guard changed * 100 >= luma.count * 4 else { return false }
        lastShot = now
        return true
    }
}

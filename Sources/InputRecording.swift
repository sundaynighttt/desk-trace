import CoreGraphics
import Foundation
import ImageIO
import ScreenCaptureKit
import UniformTypeIdentifiers

struct InputRecordingWindow {
    private let idle: Duration
    private var deadline: ContinuousClock.Instant
    private var nextFrame: ContinuousClock.Instant

    init(at start: ContinuousClock.Instant, idle: Duration = .seconds(10)) {
        self.idle = idle
        deadline = start + idle
        nextFrame = start
    }

    func isOpen(at now: ContinuousClock.Instant) -> Bool { now < deadline }

    mutating func extend(at now: ContinuousClock.Instant) -> Bool {
        guard isOpen(at: now) else { return false }
        deadline = now + idle
        return true
    }

    mutating func shouldCapture(at now: ContinuousClock.Instant) -> Bool {
        guard isOpen(at: now), now >= nextFrame else { return false }
        nextFrame += .seconds(1)
        // Skip missed intervals instead of asking the system for a burst of late frames.
        if nextFrame <= now { nextFrame = now + .seconds(1) }
        return true
    }

    var nextWake: ContinuousClock.Instant { min(deadline, nextFrame) }
}

actor InputFrameFiles {
    let directory: URL
    private var frames = [URL]()
    var isEmpty: Bool { frames.isEmpty }

    init(in folder: URL) throws {
        directory = folder.appendingPathComponent(".input-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false,
                                                attributes: [.posixPermissions: 0o700])
    }

    func append(_ image: CGImage) throws {
        let url = directory.appendingPathComponent("\(frames.count).png")
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            throw AppProblem("GIF에 넣을 화면을 준비하지 못했습니다.")
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw AppProblem("GIF에 넣을 화면을 저장하지 못했습니다.") }
        frames.append(url)
    }

    func makeGIF() throws -> URL {
        let url = directory.appendingPathComponent("screen.gif")
        guard !frames.isEmpty,
              let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.gif.identifier as CFString, frames.count, nil) else {
            throw AppProblem("화면 GIF를 만들지 못했습니다.")
        }
        CGImageDestinationSetProperties(destination, [kCGImagePropertyGIFDictionary: [
            kCGImagePropertyGIFLoopCount: 0
        ]] as CFDictionary)
        let frameSettings = [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 1.0]] as CFDictionary
        for frame in frames {
            try Task.checkCancellation()
            guard let source = CGImageSourceCreateWithURL(frame as CFURL, nil),
                  let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
                throw AppProblem("GIF에 넣을 화면을 불러오지 못했습니다.")
            }
            CGImageDestinationAddImage(destination, image, frameSettings)
        }
        try Task.checkCancellation()
        guard CGImageDestinationFinalize(destination) else { throw AppProblem("화면 GIF를 저장하지 못했습니다.") }
        return url
    }

    nonisolated func remove() { try? FileManager.default.removeItem(at: directory) }
}

@MainActor
struct InputCaptureSource {
    let takeScreen: () async throws -> CGImage
    let listen: (@escaping (Date) -> Void) throws -> (() -> Void)

    struct Failure: LocalizedError {
        let message: String
        let pane: String
        var errorDescription: String? { message }
    }

    static func prepare() async throws -> Self {
        do { try FirstInput.checkPermission() }
        catch { throw Failure(message: error.localizedDescription, pane: "Privacy_ListenEvent") }

        let filter: SCContentFilter
        do { filter = try await DisplayShot.prepare() }
        catch { throw Failure(message: error.localizedDescription, pane: "Privacy_ScreenCapture") }

        return Self(takeScreen: { try await DisplayShot.take(filter) }, listen: { onPress in
            let reader = FirstInput(onPress: onPress)
            do { try reader.start() }
            catch { throw Failure(message: error.localizedDescription, pane: "Privacy_ListenEvent") }
            return reader.stop
        })
    }
}

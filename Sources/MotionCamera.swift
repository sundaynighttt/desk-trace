import AVFoundation
import CoreImage
import os

// The session, gate and observers are confined to the serial camera queue.
final class MotionCamera: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    private static let queue = DispatchQueue(label: "DeskTrace.camera", qos: .userInitiated)
    let session = AVCaptureSession()
    private let context = CIContext(options: [.cacheIntermediates: false])
    private var observers = [NSObjectProtocol]()
    // The capture queue writes here; only the on-screen clock samples the value.
    private let frameDate = OSAllocatedUnfairLock<Date?>(initialState: nil)
    private struct PhotoRequest {
        let id: UUID
        let date: Date
        let continuation: CheckedContinuation<CGImage, Error>
    }

    private var photos = [PhotoRequest]()
    private var lastSample = -Double.infinity
    private var gate: MotionGate?
    private var onImage: (@Sendable (CGImage, Date) -> Void)?
    private var lastDisplaySize = CGSize.zero
    private let onDisplayRatio: @Sendable (CGFloat) -> Void
    private let onFailure: @Sendable (String) -> Void

    init(onDisplayRatio: @escaping @Sendable (CGFloat) -> Void,
         onFailure: @escaping @Sendable (String) -> Void) {
        self.onDisplayRatio = onDisplayRatio
        self.onFailure = onFailure
    }

    func detect(minutes: Int, lastMotion: Date?, onImage: @escaping @Sendable (CGImage, Date) -> Void) {
        Self.queue.async {
            self.gate = MotionGate(minutes: minutes, lastMotion: lastMotion)
            self.onImage = onImage
        }
    }

    func takePhoto(at date: Date) async throws -> CGImage {
        try await withCheckedThrowingContinuation { continuation in
            let id = UUID()
            Self.queue.async {
                self.photos.append(PhotoRequest(id: id, date: date, continuation: continuation))
                Self.queue.asyncAfter(deadline: .now() + 2) {
                    guard let index = self.photos.firstIndex(where: { $0.id == id }) else { return }
                    self.photos.remove(at: index).continuation.resume(
                        throwing: AppProblem("입력 순간에 카메라 영상을 받지 못했습니다."))
                }
            }
        }
    }

    func endDetection() {
        Self.queue.async {
            self.gate = nil
            self.onImage = nil
            self.photos.forEach { $0.continuation.resume(throwing: CancellationError()) }
            self.photos.removeAll()
        }
    }

    func start() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            Self.queue.async {
                do {
                    try self.configure()
                    self.session.startRunning()
                    guard self.session.isRunning else { throw AppProblem("카메라를 시작하지 못했습니다.") }
                    continuation.resume()
                } catch { continuation.resume(throwing: error) }
            }
        }
    }

    private func configure() throws {
        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .unspecified)
                ?? AVCaptureDevice.default(for: .video) else { throw AppProblem("연결된 카메라를 찾을 수 없습니다.") }
        let input = try AVCaptureDeviceInput(device: camera)
        let output = AVCaptureVideoDataOutput()
        output.alwaysDiscardsLateVideoFrames = true
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        if session.canSetSessionPreset(.hd1280x720) { session.sessionPreset = .hd1280x720 }
        guard session.canAddInput(input), session.canAddOutput(output) else { throw AppProblem("카메라를 연결할 수 없습니다.") }
        session.addInput(input)
        session.addOutput(output)
        let formats = [kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange, kCVPixelFormatType_420YpCbCr8BiPlanarFullRange,
                       kCVPixelFormatType_32BGRA]
        guard let format = formats.first(where: output.availableVideoPixelFormatTypes.contains) else {
            throw AppProblem("이 카메라의 영상 형식을 사용할 수 없습니다.")
        }
        output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: format]
        output.setSampleBufferDelegate(self, queue: Self.queue)
        for name in [AVCaptureSession.runtimeErrorNotification, AVCaptureSession.wasInterruptedNotification] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: session, queue: nil) { [weak self] _ in
                self?.onFailure("카메라 연결이 중단됐습니다. 카메라 연결 상태를 확인해 주세요.")
            })
        }
    }

    func stop() {
        Self.queue.async {
            self.observers.forEach { NotificationCenter.default.removeObserver($0) }
            self.observers.removeAll()
            self.session.stopRunning()
            for output in self.session.outputs { self.session.removeOutput(output) }
            for input in self.session.inputs { self.session.removeInput(input) }
        }
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        processFrame(buffer)
    }

    func recentFrameDate(at now: Date) -> Date? {
        frameDate.withLock { received in
            guard let received, abs(now.timeIntervalSince(received)) < 2 else { return nil }
            return received
        }
    }

    func processFrame(_ buffer: CVPixelBuffer, receivedAt date: Date = .now) {
        frameDate.withLock { $0 = date }
        let size = CVImageBufferGetDisplaySize(buffer)
        if size.width > 0, size.height > 0, size != lastDisplaySize {
            lastDisplaySize = size
            onDisplayRatio(size.width / size.height)
        }
        let now = ProcessInfo.processInfo.systemUptime
        if !photos.isEmpty { fulfillPhotos(from: buffer, at: date) }
        guard let onImage, now - lastSample >= 0.18 else { return }
        lastSample = now
        guard gate?.shouldCapture(Self.luminance(buffer), at: now) == true else { return }
        let source = CIImage(cvPixelBuffer: buffer)
        guard let image = context.createCGImage(source, from: source.extent) else {
            onFailure("카메라에서 사진을 만들지 못했습니다.")
            return
        }
        onImage(image, date)
    }

    private func fulfillPhotos(from buffer: CVPixelBuffer, at date: Date) {
        let ready = photos.filter { $0.date <= date }
        guard !ready.isEmpty else { return }
        photos.removeAll { $0.date <= date }
        let source = CIImage(cvPixelBuffer: buffer)
        if let image = context.createCGImage(source, from: source.extent) {
            ready.forEach { $0.continuation.resume(returning: image) }
        } else {
            ready.forEach { $0.continuation.resume(throwing: AppProblem("카메라 사진을 만들지 못했습니다.")) }
        }
    }

    static func luminance(_ buffer: CVPixelBuffer) -> [UInt8] {
        guard CVPixelBufferLockBaseAddress(buffer, .readOnly) == kCVReturnSuccess else { return [] }
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        let planar = CVPixelBufferGetPlaneCount(buffer) > 0
        let address = planar ? CVPixelBufferGetBaseAddressOfPlane(buffer, 0) : CVPixelBufferGetBaseAddress(buffer)
        guard let address, planar || CVPixelBufferGetPixelFormatType(buffer) == kCVPixelFormatType_32BGRA else { return [] }
        let w = planar ? CVPixelBufferGetWidthOfPlane(buffer, 0) : CVPixelBufferGetWidth(buffer)
        let h = planar ? CVPixelBufferGetHeightOfPlane(buffer, 0) : CVPixelBufferGetHeight(buffer)
        let row = planar ? CVPixelBufferGetBytesPerRowOfPlane(buffer, 0) : CVPixelBufferGetBytesPerRow(buffer)
        let base = address.assumingMemoryBound(to: UInt8.self)
        var samples = [UInt8]()
        samples.reserveCapacity(32*24)
        for y in 0..<24 {
            let offset = (2*y+1)*h/48 * row
            for x in 0..<32 {
                let column = (2*x+1)*w/64
                if planar { samples.append(base[offset + column]) }
                else {
                    let i = offset + 4*column
                    let sum = 29*Int(base[i]) + 150*Int(base[i+1]) + 77*Int(base[i+2])
                    samples.append(UInt8(sum >> 8))
                }
            }
        }
        return samples
    }

}

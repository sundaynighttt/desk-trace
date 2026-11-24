import AVFoundation
import Combine

/// Preview and armed capture share one camera session.
@MainActor
final class CameraFeed: ObservableObject {
    struct AccessDenied: LocalizedError {
        var errorDescription: String? { "시스템 설정에서 카메라 접근을 허용해 주세요." }
    }

    @Published private(set) var preview: AVCaptureSession?
    @Published private(set) var displayRatio: CGFloat?
    @Published private(set) var previewIssue: String?
    private var camera: MotionCamera?
    private var startup: Task<Void, Error>?
    private var cameraID = UUID()
    private var previewID: UUID?
    private var detectionID: UUID?
    private var detectionFailed: ((String) -> Void)?
    private let startCamera: (MotionCamera) async throws -> Void
    private let requestAccess: () async -> Bool

    init(requestAccess: @escaping () async -> Bool = {
             switch AVCaptureDevice.authorizationStatus(for: .video) {
             case .authorized: return true
             case .notDetermined: return await AVCaptureDevice.requestAccess(for: .video)
             default: return false
             }
         },
         startCamera: @escaping (MotionCamera) async throws -> Void = { try await $0.start() }) {
        self.startCamera = startCamera
        self.requestAccess = requestAccess
    }

    func showPreview(_ show: Bool) {
        if !show {
            previewID = nil
            preview = nil
            previewIssue = nil
            releaseIfIdle()
            return
        }
        guard previewID == nil else { return }
        let id = UUID()
        previewID = id
        previewIssue = nil
        Task {
            guard previewID == id else { return }
            do {
                _ = try await ready()
            } catch {
                if previewID == id { previewIssue = error.localizedDescription }
            }
        }
    }

    func previewFrameDate(at now: Date) -> Date? {
        guard preview != nil else { return nil }
        return camera?.recentFrameDate(at: now)
    }

    func beginDetection(minutes: Int?, lastMotion: Date? = nil, onImage: @escaping @Sendable (CGImage, Date) -> Void,
                        onFailure: @escaping (String) -> Void) async throws {
        let id = UUID()
        detectionID = id
        detectionFailed = onFailure
        let source = try await ready()
        guard detectionID == id else { throw CancellationError() }
        if let minutes { source.detect(minutes: minutes, lastMotion: lastMotion, onImage: onImage) }
    }

    func takeInputPhoto(at date: Date) async throws -> CGImage {
        guard detectionID != nil, let camera else { throw AppProblem("입력 순간의 카메라 사진을 찍을 수 없습니다.") }
        return try await camera.takePhoto(at: date)
    }

    func endDetection() {
        detectionID = nil
        detectionFailed = nil
        camera?.endDetection()
        releaseIfIdle()
    }

    private func ready() async throws -> MotionCamera {
        if camera == nil {
            let id = UUID()
            cameraID = id
            let source = MotionCamera(onDisplayRatio: { [weak self] ratio in
                Task { @MainActor in
                    guard let self, self.cameraID == id else { return }
                    self.displayRatio = ratio
                }
            }) { [weak self] reason in
                Task { @MainActor in
                    guard let self, self.cameraID == id else { return }
                    self.releaseCamera()
                    if self.previewID != nil { self.previewIssue = reason }
                    self.detectionFailed?(reason)
                }
            }
            camera = source
            startup = Task {
                guard await requestAccess() else { throw AccessDenied() }
                try Task.checkCancellation()
                try await startCamera(source)
            }
        }
        guard let source = camera, let task = startup else { throw CancellationError() }
        do {
            try await task.value
            guard camera === source else { throw CancellationError() }
            if previewID != nil {
                previewIssue = nil
                preview = source.session
            }
            return source
        } catch {
            if camera === source { releaseCamera() }
            throw error
        }
    }

    private func releaseIfIdle() {
        if previewID == nil && detectionID == nil { releaseCamera() }
    }

    private func releaseCamera() {
        cameraID = UUID()
        displayRatio = nil
        preview = nil
        startup?.cancel()
        startup = nil
        camera?.stop()
        camera = nil
    }
}

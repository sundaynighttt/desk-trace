import AppKit
import SwiftUI

@MainActor
final class DeskModel: ObservableObject {
    enum Phase { case off, starting, armed }
    @Published private(set) var phase: Phase = .off
    @Published private(set) var records = [CaptureRecord]()
    @Published var notice: String?
    @Published var permissionPane: String?
    @Published private(set) var inputStatus = ""
    @Published private(set) var cameraStatus = ""
    @Published var cameraOn: Bool { didSet { prefs.set(cameraOn, forKey: "camera") } }
    @Published var inputOn: Bool { didSet { prefs.set(inputOn, forKey: "input") } }
    @Published var minutes: Int { didSet { prefs.set(minutes, forKey: "interval") } }
    private let prefs: UserDefaults
    private let store: RecordStore
    private var generation = UUID()
    let cameraFeed: CameraFeed
    private final class InputSession {
        let id = UUID()
        let date: Date
        var window: InputRecordingWindow
        var staging: InputFrameFiles?
        var task: Task<Void, Never>?

        init(date: Date, at start: ContinuousClock.Instant, idle: Duration) {
            self.date = date
            window = InputRecordingWindow(at: start, idle: idle)
        }
    }

    private let prepareInput: () async throws -> InputCaptureSource
    private let clock = ContinuousClock()
    private let inputIdle: Duration
    private var stopInput: (() -> Void)?
    private var activeInput: InputSession?
    private var inputSessions = [UUID: InputSession]()
    private var lastMotion: Date?
    private static let sessionKey = "detectionSession"

    init(store: RecordStore = .standard, prefs: UserDefaults = .standard, cameraFeed: CameraFeed? = nil,
         prepareInput: (() async throws -> InputCaptureSource)? = nil, inputIdle: Duration = .seconds(10)) {
        self.prepareInput = prepareInput ?? { try await InputCaptureSource.prepare() }
        self.inputIdle = inputIdle
        self.cameraFeed = cameraFeed ?? CameraFeed()
        self.store = store
        self.prefs = prefs
        prefs.register(defaults: ["camera": true, "input": true, "interval": MotionGate.defaultMinutes])
        cameraOn = prefs.bool(forKey: "camera")
        inputOn = prefs.bool(forKey: "input")
        minutes = MotionGate.clampedMinutes(prefs.integer(forKey: "interval"))
        reload()
        if let session = prefs.dictionary(forKey: Self.sessionKey), cameraOn || inputOn {
            lastMotion = session["lastMotion"] as? Date
            begin()
        }
    }

    var active: Bool { phase != .off }
    var status: String {
        switch phase {
        case .off: return "감지 꺼짐"
        case .starting: return "준비 중"
        case .armed: return "감지 켜짐"
        }
    }

    func reload() {
        do { records = try store.readAll() } catch { notice = error.localizedDescription }
    }

    func toggle() {
        if active { stop(); return }
        guard cameraOn || inputOn else { return }
        rememberSession()
        begin()
    }

    private func begin() {
        notice = nil
        permissionPane = nil
        generation = UUID()
        let token = generation
        phase = .starting
        Task { await start(token) }
    }

    private func start(_ token: UUID) async {
        guard token == generation else { return }
        do {
            try store.prepare()
            let input = inputOn ? try await prepareInput() : nil
            guard generation == token else { return }
            try await cameraFeed.beginDetection(minutes: cameraOn ? minutes : nil, lastMotion: lastMotion,
                onImage: { [weak self] image, date in
                    Task { @MainActor in await self?.saveImage(image, kind: .camera, date: date, token: token) }
                }, onFailure: { [weak self] reason in
                    guard let self, self.generation == token else { return }
                    self.stop()
                    self.notice = reason
                })
            guard generation == token else { return }
            if cameraOn { cameraStatus = "움직임 대기" }
            if let input {
                stopInput = try input.listen { [weak self] date in
                    Task { @MainActor in self?.handlePress(date, source: input, token: token) }
                }
                inputStatus = "입력 대기"
            }
            phase = .armed
        } catch {
            guard generation == token else { return }
            stop()
            notice = error.localizedDescription
            permissionPane = error is CameraFeed.AccessDenied ? "Privacy_Camera" : (error as? InputCaptureSource.Failure)?.pane
        }
    }

    private func handlePress(_ date: Date, source: InputCaptureSource, token: UUID) {
        guard generation == token, phase == .armed else { return }
        let now = clock.now
        if let activeInput, activeInput.window.extend(at: now) { return }

        let session = InputSession(date: date, at: now, idle: inputIdle)
        activeInput = session
        inputStatus = "화면 GIF 기록 중"
        Task { [weak self] in
            guard let self, self.generation == token else { return }
            do {
                let image = try await cameraFeed.takeInputPhoto(at: date)
                await saveImage(image, kind: .inputCamera, date: date, token: token)
            } catch {
                if generation == token { notice = error.localizedDescription }
            }
        }
        inputSessions[session.id] = session
        session.task = Task { [weak self] in
            await self?.recordScreen(session, source: source, token: token)
        }
    }

    private func recordScreen(_ session: InputSession, source: InputCaptureSource, token: UUID) async {
        defer {
            session.task = nil
            inputSessions[session.id] = nil
            if activeInput === session {
                activeInput = nil
                inputStatus = "입력 대기"
            }
        }
        do {
            try Task.checkCancellation()
            let staging = try InputFrameFiles(in: store.folder)
            session.staging = staging
            defer { staging.remove() }
            var firstRequest = true
            var lastError: Error?
            while session.window.isOpen(at: clock.now) {
                try Task.checkCancellation()
                if session.window.shouldCapture(at: clock.now) {
                    let isFirst = firstRequest
                    firstRequest = false
                    let image: CGImage
                    do {
                        image = try await source.takeScreen()
                    } catch {
                        if isFirst && generation == token { notice = "첫 화면을 캡처하지 못했습니다. " + error.localizedDescription }
                        lastError = error
                        try await clock.sleep(until: session.window.nextWake)
                        continue
                    }
                    try Task.checkCancellation()
                    if isFirst { await saveImage(image, kind: .screen, date: session.date, token: token) }
                    try Task.checkCancellation()
                    try await staging.append(image)
                }
                try await clock.sleep(until: session.window.nextWake, tolerance: .milliseconds(10))
            }
            if await staging.isEmpty, let lastError { throw lastError }
            if activeInput === session { inputStatus = "화면 GIF 저장 중" }
            let gif = try await staging.makeGIF()
            try Task.checkCancellation()
            guard generation == token else { return }
            insert(try store.saveGIF(from: gif, at: session.date))
        } catch is CancellationError {
            return
        } catch {
            guard generation == token else { return }
            notice = "화면 GIF를 저장하지 못했습니다. " + error.localizedDescription
        }
    }

    private func saveImage(_ image: CGImage, kind: CaptureKind, date: Date, token: UUID) async {
        guard generation == token, phase == .armed else { return }
        do {
            let data = try await Task.detached(priority: .utility) { try Picture.encode(image) }.value
            guard generation == token else { return }
            insert(try store.save(data, kind: kind, at: date))
            if kind == .camera {
                lastMotion = max(lastMotion ?? date, date)
                cameraStatus = "마지막 촬영 " + date.formatted(date: .omitted, time: .shortened)
                rememberSession()
            }
        } catch {
            guard generation == token else { return }
            notice = error.localizedDescription
        }
    }

    private func insert(_ record: CaptureRecord) {
        let i = records.firstIndex { CaptureRecord.newer(record, than: $0) } ?? records.endIndex
        records.insert(record, at: i)
    }

    private func rememberSession() {
        var session = [String: Any]()
        if let lastMotion { session["lastMotion"] = lastMotion }
        prefs.set(session, forKey: Self.sessionKey)
    }

    func stop() {
        prefs.removeObject(forKey: Self.sessionKey)
        lastMotion = nil
        shutDown()
    }

    func shutDown() {
        generation = UUID()
        phase = .off
        stopInput?()
        stopInput = nil
        activeInput = nil
        for session in inputSessions.values {
            session.task?.cancel()
            session.staging?.remove()
        }
        inputSessions.removeAll()
        cameraFeed.endDetection()
        cameraStatus = ""
        inputStatus = ""
    }

    func revealFolder() {
        do { try store.prepare(); NSWorkspace.shared.open(store.folder) }
        catch { notice = error.localizedDescription }
    }
}

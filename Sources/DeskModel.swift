import AppKit
import AVFoundation
import ScreenCaptureKit
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
    private var input: FirstInput?

    init(store: RecordStore = .standard, prefs: UserDefaults = .standard, cameraFeed: CameraFeed? = nil) {
        self.cameraFeed = cameraFeed ?? CameraFeed()
        self.store = store
        self.prefs = prefs
        prefs.register(defaults: ["camera": true, "input": true, "interval": 10])
        cameraOn = prefs.bool(forKey: "camera")
        inputOn = prefs.bool(forKey: "input")
        minutes = min(60, max(10, prefs.integer(forKey: "interval")))
        reload()
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
        notice = nil
        permissionPane = nil
        generation = UUID()
        let token = generation
        phase = .starting
        Task { await start(token) }
    }

    private func start(_ token: UUID) async {
        guard token == generation else { return }
        var pane: String?
        do {
            try store.prepare()
            var filter: SCContentFilter?
            if cameraOn {
                pane = "Privacy_Camera"
                let permitted = await AVCaptureDevice.requestAccess(for: .video)
                guard generation == token else { return }
                guard permitted else { throw AppProblem("움직임 감지를 사용하려면 카메라 접근을 허용해 주세요.") }
            }
            if inputOn {
                pane = "Privacy_ListenEvent"
                try FirstInput.checkPermission()
                pane = "Privacy_ScreenCapture"
                filter = try await DisplayShot.prepare()
                guard generation == token else { return }
            }
            pane = nil
            if cameraOn {
                try await cameraFeed.beginDetection(minutes: minutes, onImage: { [weak self] image, date in
                    Task { @MainActor in await self?.save(image, kind: .camera, date: date, token: token) }
                }, onFailure: { [weak self] reason in
                    self?.cameraFailed(reason, token: token)
                })
                guard generation == token else { return }
                cameraStatus = "움직임 대기"
            }
            if let filter {
                let reader = FirstInput { [weak self] date in
                    Task { @MainActor in await self?.firstPress(date, filter: filter, token: token) }
                }
                input = reader
                pane = "Privacy_ListenEvent"
                try reader.start()
                inputStatus = "첫 입력 대기"
            }
            phase = .armed
        } catch {
            guard generation == token else { return }
            stop()
            notice = error.localizedDescription
            permissionPane = pane
        }
    }

    private func firstPress(_ date: Date, filter: SCContentFilter, token: UUID) async {
        guard generation == token, phase == .armed else { return }
        input?.stop()
        input = nil
        inputStatus = "화면 저장 중"
        do {
            let image = try await DisplayShot.take(filter)
            await save(image, kind: .screen, date: date, token: token)
        } catch {
            guard generation == token else { return }
            inputStatus = "캡처 실패"
            notice = "화면을 캡처하지 못했습니다. 감지를 다시 켜 주세요. " + error.localizedDescription
        }
    }

    private func cameraFailed(_ reason: String, token: UUID) {
        guard generation == token else { return }
        if phase == .starting || !inputOn { stop() }
        else { cameraFeed.endDetection(); cameraStatus = "촬영 중단" }
        notice = reason
    }

    private func save(_ image: CGImage, kind: CaptureKind, date: Date, token: UUID) async {
        guard generation == token, phase == .armed else { return }
        do {
            let data = try await Task.detached(priority: .utility) { try Picture.encode(image) }.value
            guard generation == token else { return }
            let record = try store.save(data, kind: kind, at: date)
            let i = records.firstIndex { $0.date < record.date } ?? records.endIndex
            records.insert(record, at: i)
            if kind == .screen { inputStatus = "첫 입력 저장됨" }
            else { cameraStatus = "마지막 촬영 " + date.formatted(date: .omitted, time: .shortened) }
        } catch {
            guard generation == token else { return }
            if kind == .camera { cameraFailed(error.localizedDescription, token: token) }
            else { inputStatus = "저장 실패"; notice = error.localizedDescription }
        }
    }

    func stop() {
        generation = UUID()
        phase = .off
        input?.stop()
        input = nil
        cameraFeed.endDetection()
        cameraStatus = ""
        inputStatus = ""
    }

    func revealFolder() {
        do { try store.prepare(); NSWorkspace.shared.open(store.folder) }
        catch { notice = error.localizedDescription }
    }
}

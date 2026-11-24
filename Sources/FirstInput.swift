import Cocoa
import IOKit.hid
import IOKit.hidsystem
import ScreenCaptureKit

enum DisplayShot {
    static func prepare() async throws -> SCContentFilter {
        guard CGPreflightScreenCaptureAccess() || CGRequestScreenCaptureAccess() else {
            throw AppProblem("화면 캡처를 위해 시스템 설정에서 화면 녹음 권한을 허용한 뒤 다시 켜 주세요.")
        }
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first(where: { $0.displayID == CGMainDisplayID() }) else {
            throw AppProblem("기본 디스플레이를 찾을 수 없습니다.")
        }
        return SCContentFilter(display: display, excludingWindows: [])
    }

    static func take(_ filter: SCContentFilter) async throws -> CGImage {
        let rect = filter.contentRect
        let scale = CGFloat(filter.pointPixelScale)
        let (w,h) = Picture.size(width: Int(rect.width * scale), height: Int(rect.height * scale))
        let config = SCStreamConfiguration()
        config.width = w
        config.height = h
        config.showsCursor = false
        config.capturesAudio = false
        return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
    }
}

struct PhysicalPressGate {
    let armedAt: UInt64
    private(set) var fired = false

    static func isPhysical(transport: String?, virtual: Bool?) -> Bool {
        guard virtual != true, let transport, !transport.isEmpty else { return false }
        return transport.caseInsensitiveCompare("Virtual") != .orderedSame
    }

    mutating func accept(time: UInt64, pressed: Bool) -> Bool {
        guard pressed, time > armedAt, !fired else { return false }
        fired = true
        return true
    }
}

// Only hardware reports can arm the callback. Never translate keyboard usages to text.
final class FirstInput {
    private var manager: IOHIDManager?
    private var timer: Timer?
    private var latestContact = -Double.infinity
    private var lastClicks: UInt64 = 0
    private var gate = PhysicalPressGate(armedAt: .max)
    private let onPress: (Date) -> Void
    init(onPress: @escaping (Date) -> Void) { self.onPress = onPress }

    static func checkPermission() throws {
        guard IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted ||
                IOHIDRequestAccess(kIOHIDRequestTypeListenEvent) else {
            throw AppProblem("첫 입력 감지를 위해 시스템 설정에서 입력 모니터링을 허용한 뒤 앱을 다시 열어 주세요.")
        }
    }

    func start() throws {
        let hid = IOHIDManagerCreate(kCFAllocatorDefault, 0)
        let devices = [(1,6), (1,7), (1,1), (1,2), (13,5)].map {
            [kIOHIDDeviceUsagePageKey: $0.0, kIOHIDDeviceUsageKey: $0.1]
        }
        IOHIDManagerSetDeviceMatchingMultiple(hid, devices as CFArray)
        let elements = [7, 9, 13].map { [kIOHIDElementUsagePageKey: $0] }
        IOHIDManagerSetInputValueMatchingMultiple(hid, elements as CFArray)
        IOHIDManagerRegisterInputValueCallback(hid, { context, result, _, value in
            guard let context, result == kIOReturnSuccess else { return }
            let owner = Unmanaged<FirstInput>.fromOpaque(context).takeUnretainedValue()
            owner.receive(value)
        }, Unmanaged.passUnretained(self).toOpaque())
        IOHIDManagerScheduleWithRunLoop(hid, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
        let result = IOHIDManagerOpen(hid, 0)
        guard result == kIOReturnSuccess else {
            IOHIDManagerUnscheduleFromRunLoop(hid, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
            IOHIDManagerClose(hid, 0)
            throw AppProblem("입력 장치를 열 수 없습니다. 입력 모니터링 권한을 확인해 주세요.")
        }
        manager = hid
        gate = PhysicalPressGate(armedAt: mach_absolute_time())
        lastClicks = clickCount()
        let timer = Timer(timeInterval: 0.06, repeats: true) { [weak self] _ in self?.checkTapClick() }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func receive(_ value: IOHIDValue) {
        guard manager != nil, !gate.fired, IOHIDValueGetTimeStamp(value) > gate.armedAt else { return }
        let element = IOHIDValueGetElement(value)
        let device = IOHIDElementGetDevice(element)
        let transport = IOHIDDeviceGetProperty(device, kIOHIDTransportKey as CFString) as? String
        let virtual = IOHIDDeviceGetProperty(device, "VirtualDevice" as CFString) as? Bool
        guard PhysicalPressGate.isPhysical(transport: transport, virtual: virtual) else { return }
        let page = IOHIDElementGetUsagePage(element)
        if page == 13 {
            latestContact = ProcessInfo.processInfo.systemUptime
        } else if page == 7 || page == 9 {
            trigger(time: IOHIDValueGetTimeStamp(value), pressed: IOHIDValueGetIntegerValue(value) == 1)
        }
    }

    private func clickCount() -> UInt64 {
        [.leftMouseDown, .rightMouseDown, .otherMouseDown].reduce(0) {
            $0 + UInt64(CGEventSource.counterForEventType(.hidSystemState, eventType: $1))
        }
    }

    private func checkTapClick() {
        let count = clickCount()
        defer { lastClicks = count }
        if count != lastClicks, ProcessInfo.processInfo.systemUptime - latestContact < 0.35 {
            trigger(time: mach_absolute_time(), pressed: true)
        }
    }

    private func trigger(time: UInt64, pressed: Bool) {
        guard gate.accept(time: time, pressed: pressed) else { return }
        onPress(Date())
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        guard let hid = manager else { return }
        manager = nil
        IOHIDManagerUnscheduleFromRunLoop(hid, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
        IOHIDManagerClose(hid, 0)
    }
}

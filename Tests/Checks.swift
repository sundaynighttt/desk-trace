import AppKit
import AVFoundation
import CoreVideo
import ImageIO
import SwiftUI

@main
struct Checks {
    static var checks = 0
    static func expect(_ passed: Bool, _ title: String) throws {
        guard passed else { throw AppProblem("FAIL: " + title) }
        checks += 1
        print("PASS", title)
    }

    static func fixture(_ w: Int, _ h: Int) -> CGImage {
        let c = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w*4,
                          space: CGColorSpace(name: CGColorSpace.sRGB)!,
                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        c.setFillColor(CGColor(srgbRed: 0.08, green: 0.27, blue: 0.25, alpha: 1))
        c.fill(CGRect(x: 0, y: 0, width: w, height: h))
        c.setFillColor(CGColor(srgbRed: 0.65, green: 0.85, blue: 0.75, alpha: 1))
        c.fill(CGRect(x: 0, y: h/3, width: w/2, height: h/2))
        return c.makeImage()!
    }

    @MainActor
    static func main() throws {
        var starts = 0
        var source: MotionCamera?
        let feed = CameraFeed(requestAccess: { true }, startCamera: { source = $0; starts += 1 })
        feed.showPreview(true)
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        let session = feed.preview
        try expect(session != nil && starts == 1, "live preview starts one camera")
        for (width, height) in [(320, 240), (640, 360)] {
            var buffer: CVPixelBuffer?
            guard CVPixelBufferCreate(nil, width, height, kCVPixelFormatType_32BGRA, nil, &buffer) == kCVReturnSuccess,
                  let buffer, let source else { throw AppProblem("라이브 비율 시험 프레임 생성 실패") }
            source.processFrame(buffer)
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
            try expect(feed.displayRatio == CGFloat(width) / CGFloat(height), "live surface follows the received frame aspect before arming")
        }
        var armed = false
        Task { @MainActor in
            try await feed.beginDetection(minutes: 10, onImage: { _, _ in }, onFailure: { _ in })
            armed = true
        }
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        try expect(armed && starts == 1, "arming motion reuses the preview camera")
        feed.showPreview(false)
        feed.showPreview(true)
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        try expect(feed.preview === session && starts == 1, "toggling views preserves armed camera")
        feed.endDetection()
        try expect(feed.preview === session, "disarming preserves a visible preview")
        feed.showPreview(false)
        try expect(feed.preview == nil, "hiding final consumer releases preview")
        for format in [kCVPixelFormatType_32BGRA, kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange] {
            var buffer: CVPixelBuffer?
            let result = CVPixelBufferCreate(nil, 128, 80, format, nil, &buffer)
            guard result == kCVReturnSuccess, let buffer else { throw AppProblem("테스트 영상 프레임 생성 실패") }
            CVPixelBufferLockBaseAddress(buffer, [])
            if CVPixelBufferIsPlanar(buffer) {
                memset(CVPixelBufferGetBaseAddressOfPlane(buffer, 0)!, 80, CVPixelBufferGetBytesPerRowOfPlane(buffer, 0)*80)
            } else {
                memset(CVPixelBufferGetBaseAddress(buffer)!, 80, CVPixelBufferGetBytesPerRow(buffer)*80)
            }
            CVPixelBufferUnlockBaseAddress(buffer, [])
            let luma = MotionCamera.luminance(buffer)
            try expect(luma.count == 32*24 && luma.allSatisfy { $0 == 80 }, "camera frame format "+String(format))
        }
        var gate = MotionGate(minutes: 10)
        let still = [UInt8](repeating: 50, count: 100)
        let lamp = still.map { $0 + 35 }
        var moved = lamp
        for i in 20..<40 { moved[i] = 165 }
        try expect(!gate.shouldCapture(still, at: 0), "first camera frame establishes baseline")
        try expect(!gate.shouldCapture(lamp, at: 1), "uniform lighting does not count as motion")
        try expect(gate.shouldCapture(moved, at: 2), "motion captures once")
        try expect(!gate.shouldCapture(lamp, at: 601.9), "cooldown ignores motion")
        try expect(!gate.shouldCapture(lamp, at: 602), "timer expiry alone does not capture")
        try expect(gate.shouldCapture(moved, at: 602.1), "ignored motion does not extend cooldown")
        try expect(MotionGate(minutes: 60).interval == 3600 && MotionGate(minutes: 31).interval == 1860, "60 minutes and single-minute granularity")
        var input = PhysicalPressGate(armedAt: 100)
        try expect(!input.accept(time: 99, pressed: true), "arming click ignored")
        try expect(!input.accept(time: 101, pressed: false), "release ignored")
        try expect(!PhysicalPressGate.isPhysical(transport: "Virtual", virtual: nil) && !PhysicalPressGate.isPhysical(transport: "USB", virtual: true), "virtual input ignored")
        try expect(PhysicalPressGate.isPhysical(transport: "SPI", virtual: nil) && PhysicalPressGate.isPhysical(transport: "Bluetooth", virtual: false), "physical device transports accepted")
        try expect(input.accept(time: 103, pressed: true), "first physical press independent of camera cooldown")
        try expect(!input.accept(time: 104, pressed: true), "repeated key does not save again")
        var nextSession = PhysicalPressGate(armedAt: 105)
        try expect(nextSession.accept(time: 106, pressed: true), "new session accepts another first input")
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("DeskTraceTests-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = RecordStore(folder: root)
        try expect(try store.readAll().isEmpty, "fresh gallery is empty")
        let data = try Picture.encode(fixture(1920,1080))
        try expect(data.prefix(4) == Data("RIFF".utf8) && data[8..<12] == Data("WEBP".utf8), "real WebP container")
        let decoded = CGImageSourceCreateImageAtIndex(CGImageSourceCreateWithData(data as CFData,nil)!,0,nil)!
        try expect(decoded.width == 1024 && decoded.height == 576, "real WebP decodes at 1024 × 576")
        try expect(Picture.size(width: 900, height: 1800) == (512,1024), "portrait keeps aspect")
        try expect(Picture.size(width: 320, height: 200) == (320,200), "small images not upscaled")
        let now = Date()
        let older = try store.save(data, kind: .camera, at: now.addingTimeInterval(-100))
        let newer = try store.save(data, kind: .screen, at: now)
        _ = FileManager.default.createFile(atPath: root.appendingPathComponent("unrelated.webp").path, contents: Data())
        let suite = "DeskTraceTests-" + UUID().uuidString
        let prefs = UserDefaults(suiteName: suite)!
        defer { prefs.removePersistentDomain(forName: suite) }
        prefs.set(true, forKey: "newest") // Preference saved by 0.2.2.
        let model = DeskModel(store: store, prefs: prefs)
        try expect(model.records == [newer, older], "gallery restores valid records in newest-first order")
        let gallery = ArchiveIndex(newestFirst: model.records, period: .all, kind: nil)
        try expect(gallery.chronological == [older,newer], "old newest-first preference preserves records on the shared chronological axis")
        model.minutes = 37
        model.inputOn = false
        let restored = DeskModel(store: store, prefs: prefs)
        try expect(restored.minutes == 37 && !restored.inputOn && !restored.active, "settings persist and launch disarmed")
        try expect(Picture.thumbnail(at: older.url, pixels: 300) != nil, "gallery thumbnail decodes")
        model.cameraOn = false
        model.inputOn = false
        model.toggle()
        try expect(!model.active, "cannot arm without a selected detector")
        model.cameraOn = true
        model.toggle()
        model.stop()
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        try expect(!model.active && model.notice == nil && model.records.count == 2, "stop cancels queued startup without a new record")
        // Use fixed local dates so a test crossing midnight still exercises two distinct local dates.
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 9*3600)!
        let firstDay = calendar.startOfDay(for: now)
        let yesterday = calendar.date(byAdding: .day, value: -1, to: firstDay)!
        func item(_ time: Date, _ kind: CaptureKind) -> CaptureRecord {
            let name = "\(Int64(time.timeIntervalSince1970*1000))_\(kind.rawValue)_\(UUID().uuidString).webp"
            return CaptureRecord(url: root.appendingPathComponent(name))!
        }
        let a = item(yesterday.addingTimeInterval(3600), .camera)
        let b = item(firstDay.addingTimeInterval(60), .screen)
        let c = item(firstDay.addingTimeInterval(7200), .camera)
        let d = item(c.date, .screen)
        let newestFirst = [d, c, b, a]
        let collection = ArchiveIndex(newestFirst: newestFirst, period: .all, kind: nil, now: firstDay, calendar: calendar)
        try expect(collection.chronological == [a,b,c,d] && collection.spansDays, "all dates include records from multiple days")
        try expect(collection.chronological == [a,b,c,d] && collection.marks.reduce(0,+) == 4, "time ruler retains all events including collisions")
        try expect(collection.nearest(to: -1) == 0 && collection.nearest(to: collection.fraction(of: b.date)) == 1, "ruler clamps start and locates a timestamp by elapsed time")
        try expect(collection.chronological[collection.nearest(to: 2)!].date == c.date, "ruler clamps end and resolves simultaneous captures")
        try expect(collection.nearest(to: 0) == 0 && collection.chronological.last?.date == d.date,
                   "gallery ends at newest capture on the right, timeline starts at oldest on the left")
        try expect(collection.days.map(\.id) == [yesterday, firstDay] &&
                   collection.days.map(\.records) == [[a], [b,c,d]],
                   "one local day heading per group, including simultaneous captures")
        let one = ArchiveIndex(newestFirst: newestFirst, period: .today, kind: .camera, now: firstDay, calendar: calendar)
        try expect(one.chronological == [c] && !one.spansDays, "today and camera filters intersect")
        try expect(one.fraction(of: c.date) == 0.5 && one.nearest(to: 0) == 0 && one.nearest(to: 1) == 0, "single capture stays centered and selectable")
        try expect(one.days.map(\.records) == [[c]], "filter keeps a heading for the first matching photo of the day")
        let noMatch = ArchiveIndex(newestFirst: newestFirst, period: .today, kind: .screen, now: yesterday, calendar: calendar)
        try expect(noMatch.chronological.isEmpty && noMatch.nearest(to: 0.5) == nil && noMatch.marks.reduce(0,+) == 0, "empty result has no phantom ruler events")
        try expect(noMatch.days.isEmpty, "empty filter has no date headings")
        let same = ArchiveIndex(newestFirst: [d,c], period: .all, kind: nil, now: firstDay, calendar: calendar)
        try expect(same.chronological == [c,d] && same.fraction(of: d.date) == 0.5 && same.marks.max() == 2, "simultaneous captures keep distinct cards and share a central mark")
        // Local midnights cross both a month boundary and the spring daylight-saving change.
        var pacific = Calendar(identifier: .gregorian)
        pacific.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        let anchor = pacific.date(from: DateComponents(year: 2026, month: 3, day: 10))!
        func boundary(_ offset: Int) -> Date { pacific.date(byAdding: .day, value: offset, to: anchor)! }
        let tomorrow = item(boundary(1), .screen)
        let evening = item(tomorrow.date.addingTimeInterval(-1), .screen)
        let today = item(anchor, .camera)
        let weekStart = item(boundary(-6), .camera)
        let beforeWeek = item(weekStart.date.addingTimeInterval(-1), .screen)
        let monthStart = item(boundary(-29), .camera)
        let beforeMonth = item(monthStart.date.addingTimeInterval(-1), .screen)
        let samples = [tomorrow, evening, today, weekStart, beforeWeek, monthStart, beforeMonth]
        let dayIndex = ArchiveIndex(newestFirst: [tomorrow, evening, today], period: .all, kind: nil, now: anchor, calendar: pacific)
        try expect(dayIndex.days.map(\.records) == [[today, evening], [tomorrow]], "local midnight starts a new date group")
        var saoPaulo = Calendar(identifier: .gregorian)
        saoPaulo.timeZone = TimeZone(identifier: "America/Sao_Paulo")!
        let shortDay = saoPaulo.date(from: DateComponents(year: 2018, month: 11, day: 4, hour: 12))!
        let followingDay = saoPaulo.date(from: DateComponents(year: 2018, month: 11, day: 5, minute: 10))!
        let shifted = ArchiveIndex(newestFirst: [item(followingDay, .camera), item(shortDay, .camera)],
                                   period: .all, kind: nil, calendar: saoPaulo)
        try expect(shifted.days.count == 2, "date group ends at local midnight after a skipped clock hour")
        func photos(_ period: ArchivePeriod, _ kind: CaptureKind? = nil, now: Date = anchor) -> [CaptureRecord] {
            ArchiveIndex(newestFirst: samples, period: period, kind: kind, now: now, calendar: pacific).chronological
        }
        try expect(photos(.today) == [today, evening], "today includes local midnight and excludes next midnight")
        try expect(photos(.week) == [weekStart, today, evening], "week covers seven local dates across a daylight-saving change")
        try expect(photos(.month) == [monthStart, beforeWeek, weekStart, today, evening], "month includes thirty local dates across different calendar months")
        try expect(photos(.month, .camera) == [monthStart, weekStart, today], "period combines with capture kind")
        try expect(photos(.all) == Array(samples.reversed()), "all periods includes older records")
        try expect(photos(.week, now: tomorrow.date) == [today, evening, tomorrow], "rolling period advances after midnight")
        if CommandLine.arguments.count == 2 {
            let directory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            model.cameraOn = true
            model.inputOn = true
            _ = NSApplication.shared
            _ = NSApp.setActivationPolicy(.accessory)
            let ratioStore = RecordStore(folder: root.appendingPathComponent("ratios"))
            for (w, h) in [(640, 360), (640, 400), (400, 400), (320, 480)] {
                let record = try ratioStore.save(Picture.encode(fixture(w, h)), kind: .camera, at: now)
                let tileWidth: CGFloat = 100
                let tile = NSHostingView(rootView: RecordThumbnail(record: record, selected: false, mode: .standard)
                    .frame(width: tileWidth))
                let rendered = tile.fittingSize
                try expect(abs(rendered.width - tileWidth) < 1 && abs(rendered.height - tileWidth * CGFloat(h) / CGFloat(w)) < 1,
                           "standard thumbnail matches original " + String(w) + " × " + String(h))
            }
            try render(model, to: directory.appendingPathComponent("gallery.png"), width: 1000, height: GalleryLayout.minimumHeight)
            for minute in 1...16 {
                _ = try store.save(data, kind: minute.isMultiple(of: 3) ? .screen : .camera,
                                   at: now.addingTimeInterval(Double(-minute * 60)))
            }
            try checkStandard(store: store, prefs: prefs, data: data, directory: directory)
            let empty = DeskModel(store: RecordStore(folder: root.appendingPathComponent("empty")), prefs: prefs)
            try render(empty, to: directory.appendingPathComponent("empty.png"), width: 680, height: GalleryLayout.minimumHeight)
        }
        print("Completed \(checks) checks.")
    }

    @MainActor
    static func checkStandard(store: RecordStore, prefs: UserDefaults, data: Data, directory: URL) throws {
        var cameraAllowed = false
        let feed = CameraFeed(requestAccess: { cameraAllowed }, startCamera: { _ in })
        let model = DeskModel(store: store, prefs: prefs, cameraFeed: feed)
        let size = CGSize(width: 960, height: 560)
        let host = NSHostingView(rootView: LibraryView(model: model))
        let window = NSWindow(contentRect: CGRect(origin: .zero, size: size), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.orderFrontRegardless()
        defer { window.orderOut(nil) }

        func settle() { RunLoop.current.run(until: Date().addingTimeInterval(0.25)) }
        func list(_ view: NSView) -> NSScrollView? {
            if let scroller = view as? NSScrollView { return scroller }
            return view.subviews.compactMap(list).first
        }
        func displayedSession(in view: NSView) -> AVCaptureSession? {
            if let layer = view.layer as? AVCaptureVideoPreviewLayer { return layer.session }
            return view.subviews.compactMap { displayedSession(in: $0) }.first
        }
        func click(_ point: CGPoint) throws {
            for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
                guard let event = NSEvent.mouseEvent(with: type, location: point, modifierFlags: [],
                    timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                    context: nil, eventNumber: 1, clickCount: 1, pressure: type == .leftMouseDown ? 1 : 0) else {
                    throw AppProblem("시험 창 클릭 생성 실패")
                }
                NSApp.postEvent(event, atStart: false)
            }
            let until = Date().addingTimeInterval(0.3)
            while Date() < until {
                if let event = NSApp.nextEvent(matching: .any, until: Date().addingTimeInterval(0.01), inMode: .default, dequeue: true) {
                    NSApp.sendEvent(event)
                }
            }
            settle()
        }
        func snapshot(_ name: String? = nil) throws -> NSBitmapImageRep {
            host.layoutSubtreeIfNeeded()
            guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { throw AppProblem("일반 화면 캡처 실패") }
            host.cacheDisplay(in: host.bounds, to: rep)
            if let name { try rep.representation(using: .png, properties: [:])!.write(to: directory.appendingPathComponent(name)) }
            return rep
        }
        let expectedTrailingInset: CGFloat = 10
        var rulerLeft: CGFloat { host.bounds.width - expectedTrailingInset - GalleryLayout.standardRulerWidth }
        func markerRow(_ rep: NSBitmapImageRep) -> Int? {
            let scale = CGFloat(rep.pixelsWide) / host.bounds.width
            return (0..<rep.pixelsHigh).first { row in
                (2...14).allSatisfy { offset in
                    let x = Int((rulerLeft + CGFloat(offset)) * scale)
                    guard let color = rep.colorAt(x: x, y: row)?.usingColorSpace(.sRGB) else { return false }
                    return min(color.redComponent, color.greenComponent, color.blueComponent) > 0.85
                }
            }
        }
        settle()
        let expectedHeight = GalleryLayout.standardOpeningHeight(windowWidth: size.width)
        try expect(abs(window.contentLayoutRect.height - expectedHeight) <= 1, "default gallery opens in standard mode at the fitted viewer height")
        // An explicitly taller window must keep the overlay on the photo.
        window.setContentSize(size)
        settle()
        try expect(model.cameraFeed.previewIssue != nil && !model.active, "camera denial keeps standard archive available and detection off")
        guard let scroll = list(host), let document = scroll.documentView else { throw AppProblem("저장 목록 없음") }
        let viewport = scroll.contentView
        try expect(abs(viewport.bounds.maxY - document.bounds.maxY) < 2, "standard list opens at the newest record (viewport \(viewport.bounds.maxY), document \(document.bounds.maxY))")
        let liveImage = try snapshot("standard-live.png")
        guard let liveMark = markerRow(liveImage) else { throw AppProblem("세로 시간 눈금 표시 없음") }
        let scale = CGFloat(liveImage.pixelsWide) / host.bounds.width
        let middleRow = liveMark + Int(scale)
        let length = (0..<Int(30 * scale)).filter { offset in
            guard let c = liveImage.colorAt(x: Int(rulerLeft * scale) + offset, y: middleRow)?.usingColorSpace(.sRGB) else { return false }
            return min(c.redComponent, c.greenComponent, c.blueComponent) > 0.85
        }.count
        try expect(abs(CGFloat(length) / scale - 16) <= 1, "vertical playhead uses a short neutral 16-point tick")
        viewport.scroll(to: CGPoint(x: 0, y: 80))
        scroll.reflectScrolledClipView(viewport)
        settle()
        try expect(try markerRow(snapshot()) == liveMark, "scrolling thumbnails retains live selection")
        let frame = scroll.convert(scroll.bounds, to: nil)
        try click(CGPoint(x: frame.midX, y: frame.midY))
        guard let picked = try markerRow(snapshot("standard-photo.png")) else { throw AppProblem("선택 시간 표시 없음") }
        try expect(abs(picked - liveMark) > 20, "clicking an old thumbnail moves the short neutral marker")
        let offset = viewport.bounds.minY
        _ = try store.save(data, kind: .screen, at: Date().addingTimeInterval(1))
        model.reload()
        settle()
        try expect(abs(viewport.bounds.minY - offset) < 2 && abs((try markerRow(snapshot()) ?? -1000) - picked) < 10,
                   "new capture preserves historical selection and reading position (was \(offset), now \(viewport.bounds.minY))")
        func clickLiveButton(for listFrame: CGRect) throws {
            let mediaWidth = listFrame.minX - GalleryLayout.gap - GalleryLayout.inset
            let viewerTop = window.contentLayoutRect.maxY - 8 - GalleryLayout.filterHeight - GalleryLayout.gap
            let bottom = viewerTop - mediaWidth * 9 / 16
            try click(CGPoint(x: listFrame.minX - 90, y: bottom + 24))
        }
        try clickLiveButton(for: frame)
        try expect(try markerRow(snapshot()) == liveMark, "existing control over the photo's lower right restores live and the latest-record marker")
        for (width, expected) in [(680, 66), (961, 100), (1440, 158), (960, 100)] {
            window.setContentSize(CGSize(width: CGFloat(width), height: size.height))
            settle()
            let archiveRight = scroll.convert(scroll.bounds, to: nil).maxX
            try expect(abs(rulerLeft - archiveRight - 12) < 0.1, "standard ruler has a twelve-point photo gap and ten-point trailing inset at width \(width)")
            try expect(abs(scroll.frame.width - CGFloat(expected)) < 0.01,
                       "right archive uses even one-third width at " + String(width) + " points")
        }

        // Closing while viewing a saved photo must release preview, even if the host is reused.
        try click(scroll.convert(CGPoint(x: scroll.bounds.midX, y: scroll.bounds.midY), to: nil))
        window.close()
        settle()
        try expect(feed.preview == nil && feed.previewIssue == nil, "closed gallery releases preview")
        cameraAllowed = true
        window.makeKeyAndOrderFront(nil)
        settle()
        guard let session = feed.preview, let reopened = list(host) else { throw AppProblem("일반 모드 재열기 실패") }
        try expect(displayedSession(in: host) === session && !model.active, "reopening shows the camera without arming detection")
        let reopenedList = reopened.convert(reopened.bounds, to: nil)
        try click(CGPoint(x: reopenedList.midX, y: reopenedList.midY))
        try expect(displayedSession(in: host) == nil && feed.preview === session, "a saved photo replaces the displayed preview")
        try clickLiveButton(for: reopenedList)
        try expect(displayedSession(in: host) === session && !model.active, "on-air button redisplays the same camera session")
    }

    @MainActor
    static func render(_ model: DeskModel, to url: URL, width: CGFloat, height: CGFloat) throws {
        let rect = CGRect(x: 0, y: 0, width: width, height: height)
        let view = NSHostingView(rootView: LibraryView(model: model, mode: .mini).environment(\.locale, Locale(identifier: "ko_KR")))
        let window = NSWindow(contentRect: rect, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = view
        window.setContentSize(CGSize(width: width, height: height + 190))
        window.orderFrontRegardless()
        RunLoop.current.run(until: Date().addingTimeInterval(0.6))
        try expect(abs(window.contentLayoutRect.height - height) <= 1, "opening a tall gallery fits its minimum at width " + String(Int(width)))
        view.layoutSubtreeIfNeeded()
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { throw AppProblem("화면 렌더링 실패") }
        view.cacheDisplay(in: view.bounds, to: rep)
        // The fixture photos contain no yellow. Check the actual rendered playhead, including edge clipping.
        let scale = CGFloat(rep.pixelsWide) / width
        let markerX = Int((width - GalleryLayout.inset - 3) * scale)
        func isYellow(_ x: Int, _ y: Int) -> Bool {
            guard let color = rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { return false }
            return color.redComponent > 0.85 && color.greenComponent > 0.65 && color.blueComponent < 0.35
        }
        let rows = (0..<rep.pixelsHigh).filter { isYellow(markerX, $0) }
        if model.records.isEmpty {
            try expect(rows.isEmpty, "empty gallery has no latest-record playhead")
        } else {
            try expect(abs(CGFloat(rows.count) / scale - GalleryLayout.rulerHeight) <= 1,
                       "latest-record playhead spans the ruler height")
            let mid = rows[rows.count / 2]
            let yellowWidth = (0..<rep.pixelsWide).filter { isYellow($0, mid) }.count
            try expect(abs(CGFloat(yellowWidth) / scale - 6) <= 1, "one full-width yellow bar at the timeline edge")
        }
        try rep.representation(using: .png, properties: [:])!.write(to: url)
        model.notice = "권한 설정을 확인해 주세요."
        RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        try expect(window.contentLayoutRect.height > height, "permission notice expands the compact window without clipping the ruler")
        model.notice = nil
        window.setContentSize(CGSize(width: width, height: height + 90))
        RunLoop.current.run(until: Date().addingTimeInterval(0.15))
        try expect(window.contentLayoutRect.height >= height + 89, "manual window height survives after opening at width " + String(Int(width)))
        window.orderOut(nil)
    }
}

import AppKit
import SwiftUI

struct LibraryView: View {
    @ObservedObject var model: DeskModel
    @State private var day: Date?
    @State private var kind: CaptureKind?
    @State private var settings = false
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        let index = ArchiveIndex(newestFirst: model.records, day: day, kind: kind, newest: model.newest)
        VStack(spacing: 0) {
            ZStack {
                HStack {
                    Menu {
                        Button("전체 날짜") { day = nil }
                        if !index.availableDates.isEmpty { Divider() }
                        ForEach(index.availableDates, id: \.self) { date in
                            Button(ArchiveText.fullDay.string(from: date)) { day = date }
                        }
                    } label: {
                        Label(day.map(ArchiveText.fullDay.string) ?? "전체 날짜", systemImage: "calendar")
                            .font(.callout)
                    }.menuStyle(.borderlessButton).fixedSize().accessibilityLabel("날짜 필터")
                    Spacer()
                    Toggle("감지", isOn: Binding(get: { model.active }, set: { desired in
                        if desired != model.active { model.toggle() }
                    }))
                    .toggleStyle(.switch).controlSize(.small).tint(.blue)
                    .accessibilityLabel(model.active ? "감지 끄기" : "감지 켜기")
                    .help(model.status)
                    .disabled(!model.active && !model.cameraOn && !model.inputOn)
                    Button { settings.toggle() } label: {
                        Image(systemName: "gearshape").font(.system(size: 15)).frame(width: 28, height: 28)
                    }.buttonStyle(.plain).accessibilityLabel("감지 설정").help("감지 설정")
                        .popover(isPresented: $settings, arrowEdge: .bottom) { MonitorSettings(model: model) }
                }.padding(.leading, 60)
                HStack(spacing: 8) {
                    chip("전체", filter: nil)
                    chip("움직임", filter: .camera)
                    chip("첫 입력", filter: .screen)
                }
            }
            .padding(.horizontal, 25).padding(.top, 8).padding(.bottom, 8)
            if let notice = model.notice {
                HStack(alignment: .center, spacing: 8) {
                    Image(systemName: "exclamationmark.circle")
                    Text(notice).lineLimit(3)
                    if let pane = model.permissionPane, let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?" + pane) {
                        Link("권한 설정", destination: url).fixedSize()
                    }
                    Spacer()
                    Button { model.notice = nil } label: { Image(systemName: "xmark") }
                        .buttonStyle(.plain).accessibilityLabel("안내 닫기")
                }.font(.callout).padding(.horizontal, 24).padding(.vertical, 5)
            }
            ArchiveBrowser(index: index, isFiltered: kind != nil || day != nil, active: model.active) {
                day = nil
                kind = nil
            }
            .id(FilterIdentity(day: day, kind: kind))
        }
        .frame(minWidth: 680, maxWidth: .infinity, minHeight: 216, maxHeight: 380)
        .foregroundStyle(.white)
        .background {
            ZStack {
                WindowGlass(reduceTransparency: reduceTransparency)
                if reduceTransparency { Color(white: 0.14) }
                else { Color.black.opacity(0.38) }
            }.ignoresSafeArea()
        }
        .environment(\.colorScheme, .dark)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in model.reload() }
    }

    private func chip(_ title: String, filter: CaptureKind?) -> some View {
        let selected = kind == filter
        return Button { kind = filter } label: {
            Text(title).font(.system(size: 13, weight: .semibold))
                .padding(.horizontal, 15).frame(height: 29)
                .background(selected ? GlassInk.blue : GlassInk.capsule, in: RoundedRectangle(cornerRadius: 10))
        }.buttonStyle(.plain).accessibilityAddTraits(selected ? .isSelected : [])
    }
}

private struct FilterIdentity: Hashable {
    let day: Date?
    let kind: CaptureKind?
}

struct MonitorSettings: View {
    @ObservedObject var model: DeskModel
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("감지 설정").font(.title3.bold())
            VStack(alignment: .leading, spacing: 12) {
                Toggle(isOn: $model.cameraOn) { Label("카메라 움직임", systemImage: "camera") }
                if model.cameraOn {
                    HStack {
                        Text("촬영 간격").foregroundStyle(.secondary)
                        Spacer()
                        Text("\(model.minutes)분").monospacedDigit()
                        Stepper("촬영 간격", value: $model.minutes, in: 10...60).labelsHidden()
                    }
                    Slider(value: Binding(get: { Double(model.minutes) }, set: { model.minutes = Int($0.rounded()) }), in: 10...60, step: 1)
                        .accessibilityLabel("촬영 간격").accessibilityValue("\(model.minutes)분")
                }
                Divider()
                Toggle(isOn: $model.inputOn) { Label("첫 입력 캡처", systemImage: "keyboard") }
            }.toggleStyle(.switch).disabled(model.active)
            if model.active {
                Text([model.cameraStatus, model.inputStatus].filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.caption).foregroundStyle(.secondary)
                Text("감지를 끄면 설정을 바꿀 수 있습니다.").font(.caption)
            }
            Divider()
            Picker("기록 정렬", selection: $model.newest) {
                Text("최신순").tag(true)
                Text("오래된순").tag(false)
            }.pickerStyle(.segmented)
            Button(action: model.revealFolder) { Label("저장 폴더 열기", systemImage: "folder") }
                .buttonStyle(.borderless)
        }.padding(20).frame(width: 282)
    }
}

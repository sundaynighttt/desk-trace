import AppKit
import SwiftUI

struct LibraryView: View {
    @ObservedObject var model: DeskModel
    @State var mode: GalleryMode = .mini
    @State private var period: ArchivePeriod = .week
    @State private var referenceDate = Date()
    @State private var kind: CaptureKind?
    @State private var settings = false
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        let index = ArchiveIndex(newestFirst: model.records, period: period, kind: kind, now: referenceDate)
        VStack(spacing: 0) {
            ZStack {
                HStack {
                    Menu {
                        Picker("조회 기간", selection: $period) {
                            ForEach(ArchivePeriod.allCases, id: \.self) { choice in
                                Text(choice.rawValue).tag(choice)
                            }
                        }.pickerStyle(.inline).labelsHidden()
                    } label: {
                        HStack(spacing: 6) {
                            Text(period.rawValue)
                            Image(systemName: "chevron.down").font(.system(size: 9, weight: .bold))
                        }
                        .font(.system(size: 13, weight: .semibold))
                        .padding(.horizontal, 12).frame(height: 29)
                        .background(GlassInk.blue, in: RoundedRectangle(cornerRadius: 10))
                        .contentShape(Rectangle())
                    }
                    .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
                    .accessibilityLabel("조회 기간").accessibilityValue(period.rawValue)
                    .accessibilityIdentifier("archive.period")
                    Spacer()
                    Menu {
                        Picker("화면 모드", selection: $mode) {
                            ForEach(GalleryMode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                        }.pickerStyle(.inline).labelsHidden()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: mode == .mini ? "rectangle.compress.vertical" : "rectangle.split.2x1")
                            Text(mode.rawValue)
                            Image(systemName: "chevron.down").font(.system(size: 9, weight: .bold))
                        }.font(.system(size: 12, weight: .semibold))
                        .padding(.horizontal, 10).frame(height: 29)
                        .background(GlassInk.capsule, in: RoundedRectangle(cornerRadius: 10))
                    }
                    .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
                    .accessibilityLabel("화면 모드").accessibilityValue(mode.rawValue)
                    .accessibilityIdentifier("archive.mode")
                    Toggle("감지", isOn: Binding(get: { model.active }, set: { desired in
                        if desired != model.active { model.toggle() }
                    }))
                    .toggleStyle(.switch).controlSize(.small).tint(.blue)
                    .accessibilityLabel(model.active ? "감지 끄기" : "감지 켜기")
                    .help(model.status)
                    .disabled(!model.active && !model.cameraOn && !model.inputOn)
                    Button { settings.toggle() } label: {
                        Image(systemName: "gearshape").font(.system(size: 15)).frame(width: 28, height: 28, alignment: .trailing)
                            .contentShape(Rectangle())
                    }.buttonStyle(.plain).accessibilityLabel("감지 설정").help("감지 설정")
                        .popover(isPresented: $settings, arrowEdge: .bottom) { MonitorSettings(model: model) }
                }
                HStack(spacing: 5) {
                    chip("전체", leading: 8, trailing: 8, selected: kind == nil) { kind = nil }
                        .accessibilityLabel("감지 종류 전체")
                    HStack(spacing: 0) {
                        chip("입력", leading: 0, trailing: 8, selected: kind == .screen) { kind = .screen }
                        chip("움직임", leading: 8, trailing: 0, selected: kind == .camera) { kind = .camera }
                    }
                }
                .padding(3).background(.black.opacity(0.56), in: RoundedRectangle(cornerRadius: 11))
            }
            .padding(.horizontal, GalleryLayout.inset).padding(.top, 8).padding(.bottom, GalleryLayout.gap)
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
                }.font(.callout).fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, GalleryLayout.inset).padding(.vertical, 5)
            }
            if mode == .standard {
                StandardGallery(index: index, feed: model.cameraFeed,
                                isFiltered: !model.records.isEmpty && (kind != nil || period != .all),
                                resetFilters: { period = .all; kind = nil })
            } else {
                ArchiveBrowser(index: index, isFiltered: !model.records.isEmpty && (kind != nil || period != .all), active: model.active) {
                    period = .all
                    kind = nil
                }
                .id(FilterIdentity(period: period, kind: kind))
            }
        }
        .fixedSize(horizontal: false, vertical: mode == .mini)
        .frame(minWidth: 680, maxWidth: .infinity, minHeight: mode == .standard ? 350 : nil, maxHeight: .infinity, alignment: .top)
        .foregroundStyle(.white)
        .background {
            ZStack {
                WindowGlass(reduceTransparency: reduceTransparency, mode: mode) {
                    model.cameraFeed.showPreview(false)
                    mode = .mini
                }
                if reduceTransparency { Color(white: 0.14) }
                else { Color.black.opacity(0.38) }
            }.ignoresSafeArea()
        }
        .environment(\.colorScheme, .dark)
        .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in referenceDate = Date() }
        .onReceive(NotificationCenter.default.publisher(for: .NSSystemTimeZoneDidChange)) { _ in referenceDate = Date() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            referenceDate = Date()
            model.reload()
        }
    }

    private func chip(_ title: String, leading: CGFloat, trailing: CGFloat, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.system(size: 13, weight: .semibold))
                .fixedSize().padding(.horizontal, 12).frame(height: 28)
                .background(selected ? GlassInk.blue : GlassInk.capsule, in: UnevenRoundedRectangle(
                    topLeadingRadius: leading, bottomLeadingRadius: leading,
                    bottomTrailingRadius: trailing, topTrailingRadius: trailing))
                .contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityAddTraits(selected ? .isSelected : [])
    }
}

private struct FilterIdentity: Hashable {
    let period: ArchivePeriod
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
            Button(action: model.revealFolder) { Label("저장 폴더 열기", systemImage: "folder") }
                .buttonStyle(.borderless)
        }.padding(20).frame(width: 282)
    }
}

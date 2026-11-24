import AppKit
import SwiftUI

private let accent = Color(nsColor: .systemTeal)

struct LibraryView: View {
    @ObservedObject var model: DeskModel
    @State private var selected: CaptureRecord?
    @Environment(\.colorScheme) private var scheme
    private var rail: Color { scheme == .dark ? Color(white: 0.115) : Color(red: 0.946, green: 0.952, blue: 0.945) }

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 10) {
                    Image(systemName: "viewfinder").font(.system(size: 23, weight: .medium))
                        .foregroundStyle(accent)
                    Text("자리기록").font(.system(size: 21, weight: .bold))
                }
                .padding(.bottom, 34)
                Label(model.status, systemImage: model.active ? "circle.inset.filled" : "circle")
                    .font(.headline).foregroundStyle(model.active ? accent : .secondary)
                Button(action: model.toggle) {
                    HStack {
                        Image(systemName: model.active ? "stop.fill" : "play.fill")
                        Text(model.active ? "감지 끄기" : "감지 켜기").fontWeight(.semibold)
                    }.frame(maxWidth: .infinity).padding(.vertical, 4)
                }
                .buttonStyle(.borderedProminent).controlSize(.large).tint(Color(red: 0.12, green: 0.40, blue: 0.36))
                .disabled(!model.active && !model.inputOn && !model.cameraOn)
                .padding(.top, 12)
                Divider().padding(.vertical, 22)
                VStack(alignment: .leading, spacing: 16) {
                    mode("카메라 움직임", icon: "camera", value: $model.cameraOn)
                    if model.cameraOn {
                        HStack {
                            Text("촬영 간격").foregroundStyle(.secondary)
                            Spacer()
                            Text("\(model.minutes)분").monospacedDigit()
                            Stepper("촬영 간격", value: $model.minutes, in: 10...60).labelsHidden()
                        }
                        Slider(value: Binding(get: { Double(model.minutes) }, set: { model.minutes = Int($0.rounded()) }),
                               in: 10...60, step: 1)
                            .accessibilityLabel("카메라 촬영 간격").accessibilityValue("\(model.minutes)분")
                    }
                    Divider()
                    mode("첫 입력 캡처", icon: "keyboard", value: $model.inputOn)
                }
                .disabled(model.active)
                if model.active {
                    VStack(alignment: .leading, spacing: 6) {
                        if !model.cameraStatus.isEmpty { Label(model.cameraStatus, systemImage: "camera") }
                        if !model.inputStatus.isEmpty { Label(model.inputStatus, systemImage: "keyboard") }
                    }.font(.caption).foregroundStyle(.secondary).padding(.top, 15)
                }
                Spacer(minLength: 20)
                Button(action: model.revealFolder) {
                    Label("저장 폴더 열기", systemImage: "folder").frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain).help("Finder에서 촬영 기록 폴더를 엽니다")
            }
            .padding(22).frame(width: 230).frame(maxHeight: .infinity).background(rail)
            Divider()
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("촬영 기록").font(.system(size: 25, weight: .bold))
                        Text("총 \(model.records.count)장").foregroundStyle(.secondary).font(.callout)
                    }
                    Spacer()
                    Picker("정렬", selection: $model.newest) {
                        Text("최신순").tag(true)
                        Text("오래된순").tag(false)
                    }.labelsHidden().accessibilityLabel("기록 정렬").fixedSize()
                }.padding(.horizontal, 26).padding(.vertical, 22)
                Divider()
                if let notice = model.notice {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "exclamationmark.circle").foregroundStyle(.orange)
                        VStack(alignment: .leading, spacing: 6) {
                            Text(notice).fixedSize(horizontal: false, vertical: true)
                            if let pane = model.permissionPane,
                               let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?" + pane) {
                                Link("권한 설정 열기", destination: url)
                            }
                        }
                        Spacer()
                        Button { model.notice = nil } label: { Image(systemName: "xmark") }
                            .buttonStyle(.borderless).accessibilityLabel("안내 닫기")
                    }.padding(14).background(Color.orange.opacity(0.1))
                }
                if model.records.isEmpty {
                    VStack(spacing: 13) {
                        Image(systemName: "photo.on.rectangle.angled").font(.system(size: 34, weight: .light))
                            .foregroundStyle(accent).padding(.bottom, 2)
                        Text("아직 촬영 기록이 없습니다").font(.title3.weight(.semibold))
                        Text(model.active ? "감지가 발생하면 여기에 이미지가 표시됩니다." : "감지를 켜면 이곳에 사진과 화면 캡처가 쌓입니다.")
                            .foregroundStyle(.secondary)
                    }.frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 170, maximum: 310), spacing: 16)], spacing: 18) {
                            ForEach(model.ordered) { record in
                                Button { selected = record } label: { CaptureCard(record: record) }
                                    .buttonStyle(.plain)
                            }
                        }.padding(22)
                    }
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity).background(Color(nsColor: .windowBackgroundColor))
        }
        .tint(accent)
        .frame(minWidth: 710, minHeight: 480)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in model.reload() }
        .sheet(item: $selected) { record in CaptureDetail(record: record) }
    }

    private func mode(_ text: String, icon: String, value: Binding<Bool>) -> some View {
        Toggle(isOn: value) {
            Label(text, systemImage: icon).font(.system(size: 13, weight: .semibold))
        }.toggleStyle(.switch).controlSize(.small)
    }
}

private struct FileImage: View {
    let url: URL
    let detail: Bool
    @State private var image: NSImage?
    @State private var missing = false

    var body: some View {
        Group {
            if let image {
                if detail { Image(nsImage: image).resizable().scaledToFit() }
                else { Image(nsImage: image).resizable().scaledToFill() }
            } else if missing { Image(systemName: "photo.badge.exclamationmark") }
            else { ProgressView().controlSize(.small) }
        }.task(id: url) {
            let result = await Task.detached(priority: .utility) { Picture.thumbnail(at: url, pixels: detail ? 1024 : 480) }.value
            guard !Task.isCancelled else { return }
            image = result
            missing = result == nil
        }
    }
}

private struct CaptureCard: View {
    let record: CaptureRecord
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Color.secondary.opacity(0.10).aspectRatio(1.55, contentMode: .fit)
                .overlay { FileImage(url: record.url, detail: false) }
                .clipShape(RoundedRectangle(cornerRadius: 8))
            Label(record.kind.title, systemImage: record.kind.symbol).font(.headline)
            Text(record.date.formatted(.dateTime.month().day().hour().minute().second()))
                .font(.caption).foregroundStyle(.secondary)
        }.contentShape(Rectangle())
    }
}

private struct CaptureDetail: View {
    let record: CaptureRecord
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(spacing: 14) {
            HStack {
                Label(record.kind.title, systemImage: record.kind.symbol).font(.headline)
                Spacer()
                Text(record.date.formatted(date: .abbreviated, time: .standard)).foregroundStyle(.secondary)
                Button("닫기") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            FileImage(url: record.url, detail: true).frame(maxWidth: .infinity, maxHeight: .infinity)
        }.padding(18).frame(minWidth: 550, idealWidth: 760, minHeight: 340, idealHeight: 480)
    }
}

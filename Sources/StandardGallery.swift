import AVFoundation
import SwiftUI

struct StandardGallery: View {
    let index: ArchiveIndex
    @ObservedObject var feed: CameraFeed
    @Binding var period: ArchivePeriod
    let isFiltered: Bool
    let resetFilters: () -> Void
    @State private var selected: CaptureRecord?
    @State private var nearBottom = true

    var body: some View {
        GeometryReader { area in
            let width = GalleryLayout.standardThumbnailWidth(windowWidth: area.size.width)
            ScrollViewReader { scroll in
                HStack(spacing: GalleryLayout.gap) {
                    viewer
                    VStack(alignment: .leading, spacing: 6) {
                        ArchivePeriodMenu(period: $period, mode: .standard)
                            .frame(width: width)
                        HStack(spacing: GalleryLayout.standardRulerGap) {
                            archive.frame(width: width)
                            TimeRuler(index: index, pinned: selected ?? index.chronological.last,
                                      hover: { _ in }, choose: { item in
                                selected = item
                                scroll.scrollTo(item.id, anchor: .center)
                            }, vertical: true)
                            .frame(width: GalleryLayout.standardRulerWidth)
                        }
                    }
                }
                .onChange(of: index.chronological) { old, rows in
                    if let selected, !rows.contains(selected) {
                        self.selected = nil
                        scrollToLatest(scroll)
                    } else if selected == nil, nearBottom || old.isEmpty {
                        scrollToLatest(scroll)
                    }
                }
            }
            .padding(.leading, GalleryLayout.inset)
            .padding(.trailing, GalleryLayout.standardTrailingInset)
        }
        .padding(.bottom, GalleryLayout.standardBottomInset)
        .onAppear { feed.showPreview(true) }
        .onDisappear { feed.showPreview(false) }
    }

    private func scrollToLatest(_ scroll: ScrollViewProxy) {
        if let last = index.chronological.last { scroll.scrollTo(last.id, anchor: .bottom) }
    }

    private var archive: some View {
        GeometryReader { viewport in
            if index.chronological.isEmpty {
                VStack(spacing: 8) {
                    Text(isFiltered ? "이 조건에 맞는 기록이 없습니다" : "아직 촬영한 이미지가 없습니다")
                        .font(.callout)
                    if isFiltered { Button("전체 기록 보기", action: resetFilters).buttonStyle(.borderless) }
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4, pinnedViews: [.sectionHeaders]) {
                        ForEach(index.days) { day in
                            Section {
                                ForEach(day.records) { item in
                                    thumbnailRow(item)
                                }
                            } header: {
                                Text(ArchiveText.groupDate.string(from: day.id))
                                    .font(.system(size: 11, weight: .semibold)).monospacedDigit()
                                    .lineLimit(1).minimumScaleFactor(0.85)
                                    .padding(.horizontal, GalleryLayout.archiveTextInset).padding(.vertical, 1)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(.black.opacity(0.74), in: RoundedRectangle(cornerRadius: 3))
                                    .padding(.top, day.id == index.days.first?.id ? 0 : 4)
                                    .accessibilityAddTraits(.isHeader)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: viewport.size.height, alignment: .topLeading)
                    .onGeometryChange(for: Bool.self) {
                        $0.frame(in: .named("recordList")).maxY <= viewport.size.height + 2
                    } action: { nearBottom = $0 }
                }
                .defaultScrollAnchor(nearBottom && selected == nil ? .bottom : nil)
                .coordinateSpace(name: "recordList")
                .scrollIndicators(.hidden)
            }
        }
    }

    private func thumbnailRow(_ item: CaptureRecord) -> some View {
        Button { selected = item } label: {
            RecordThumbnail(record: item, selected: selected == item, mode: .standard)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain).id(item.id)
        .accessibilityLabel(item.kind.eventName + " " + ArchiveText.fullStamp.string(from: item.date))
        .accessibilityAddTraits(selected == item ? .isSelected : [])
    }

    private var viewer: some View {
        let ratio = selected.flatMap { Picture.aspectRatio(at: $0.url) } ?? feed.displayRatio ?? GalleryLayout.defaultVideoAspect
        return Color.clear.aspectRatio(ratio, contentMode: .fit)
        .overlay {
            if let selected {
                FileImage(url: selected.url, detail: true).id(selected.url)
                    .accessibilityLabel(selected.kind.title)
            } else if let session = feed.preview {
                CameraPreview(session: session).accessibilityLabel("라이브 카메라")
            } else if let issue = feed.previewIssue {
                VStack(spacing: 9) {
                    Image(systemName: "video.slash").font(.title2)
                    Text(issue).font(.callout).multilineTextAlignment(.center)
                    Button("다시 연결") { feed.showPreview(false); feed.showPreview(true) }
                }.padding()
            } else {
                ProgressView("카메라 연결 중").controlSize(.small)
            }
        }
        .background {
            if selected == nil && feed.preview == nil { Color.black.opacity(0.56) }
        }
        .overlay(alignment: .topLeading) {
            HStack(spacing: 6) {
                if let selected {
                    Image(systemName: selected.kind.symbol)
                    Text(ArchiveText.fullStamp.string(from: selected.date)).monospacedDigit()
                } else {
                    Image(systemName: "video")
                    Text(feed.preview == nil ? "카메라" : "온에어")
                }
            }.font(.system(size: 12, weight: .semibold))
            .padding(.horizontal, 9).padding(.vertical, 6)
            .background(.black.opacity(0.72), in: Capsule()).padding(10)
        }
        .overlay(alignment: .bottomTrailing) {
            if selected != nil {
                Button { selected = nil } label: {
                    Label("라이브로 돌아가기", systemImage: "video")
                        .font(.system(size: 12, weight: .semibold))
                        .padding(.horizontal, 12).padding(.vertical, 7)
                        .background(GlassInk.blue, in: Capsule())
                }.buttonStyle(.plain)
                    .accessibilityIdentifier("archive.returnToLive")
                    .padding(10)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

private struct CameraPreview: NSViewRepresentable {
    let session: AVCaptureSession

    final class Surface: NSView {
        let preview = AVCaptureVideoPreviewLayer()
        override func makeBackingLayer() -> CALayer { preview }
    }

    func makeNSView(context: Context) -> Surface {
        let view = Surface()
        view.wantsLayer = true
        view.preview.videoGravity = .resizeAspect
        return view
    }

    func updateNSView(_ view: Surface, context: Context) {
        if view.preview.session !== session { view.preview.session = session }
    }

    static func dismantleNSView(_ view: Surface, coordinator: ()) {
        view.preview.session = nil
    }
}

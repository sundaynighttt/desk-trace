import AVFoundation
import SwiftUI

struct StandardGallery: View {
    let index: ArchiveIndex
    @ObservedObject var feed: CameraFeed
    let isFiltered: Bool
    let resetFilters: () -> Void
    @State private var selected: CaptureRecord?
    @State private var nearBottom = true

    var body: some View {
        GeometryReader { area in
            let thumbnail = GalleryLayout.standardThumbnailSize(in: area.size.width)
            ScrollViewReader { scroll in
                HStack(spacing: GalleryLayout.gap) {
                    viewer
                    archive(thumbnail: thumbnail)
                        .frame(width: thumbnail.width)
                    TimeRuler(index: index, pinned: selected ?? index.chronological.last,
                              hover: { _ in }, choose: { item in
                        selected = item
                        scroll.scrollTo(item.id, anchor: .center)
                    }, vertical: true)
                    .frame(width: 52)
                }
                .onAppear { scrollToLatest(scroll) }
                .onChange(of: index.chronological) { old, rows in
                    if let selected, !rows.contains(selected) {
                        self.selected = nil
                        scrollToLatest(scroll)
                    } else if selected == nil, nearBottom || old.isEmpty {
                        scrollToLatest(scroll)
                    }
                }
            }
        }
        .padding(.horizontal, GalleryLayout.inset).padding(.bottom, 16)
        .onAppear { feed.showPreview(true) }
        .onDisappear { feed.showPreview(false) }
    }

    private func scrollToLatest(_ scroll: ScrollViewProxy) {
        if let last = index.chronological.last { scroll.scrollTo(last.id, anchor: .bottom) }
    }

    private func archive(thumbnail: CGSize) -> some View {
        GeometryReader { viewport in
            if index.chronological.isEmpty {
                VStack(spacing: 8) {
                    Text(isFiltered ? "이 조건에 맞는 기록이 없습니다" : "아직 촬영한 이미지가 없습니다")
                        .font(.callout)
                    if isFiltered { Button("전체 기록 보기", action: resetFilters).buttonStyle(.borderless) }
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(index.chronological) { item in
                            Button { selected = item } label: {
                                VStack(alignment: .leading, spacing: 3) {
                                    RecordThumbnail(record: item, selected: selected == item, showsTimeOverlay: false)
                                        .frame(width: thumbnail.width, height: thumbnail.height)
                                    timestamp(for: item)
                                }.contentShape(Rectangle())
                            }
                            .buttonStyle(.plain).id(item.id)
                            .accessibilityLabel(item.kind.eventName + " " + ArchiveText.fullStamp.string(from: item.date))
                            .accessibilityAddTraits(selected == item ? .isSelected : [])
                        }
                    }
                    .onGeometryChange(for: Bool.self) {
                        $0.frame(in: .named("recordList")).maxY <= viewport.size.height + 2
                    } action: { nearBottom = $0 }
                }
                .coordinateSpace(name: "recordList")
                .scrollIndicators(.hidden)
            }
        }
    }

    private func timestamp(for item: CaptureRecord) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 3) {
                Image(systemName: item.kind.symbol)
                Text(ArchiveText.day.string(from: item.date))
                Text(ArchiveText.clock.string(from: item.date))
            }.fixedSize()
            VStack(alignment: .leading, spacing: 1) {
                Label(ArchiveText.day.string(from: item.date), systemImage: item.kind.symbol)
                Text(ArchiveText.clock.string(from: item.date))
            }.fixedSize()
        }
        .font(.system(size: 10, weight: .medium)).monospacedDigit()
        .foregroundStyle(.white)
        .padding(.horizontal, 3).padding(.vertical, 1)
        .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 3))
    }

    private var viewer: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14).fill(.black.opacity(0.56))
            if let selected {
                FileImage(url: selected.url, detail: true).id(selected.url)
                    .padding(1).accessibilityLabel(selected.kind.title)
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
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .topLeading) {
            HStack(spacing: 6) {
                if let selected {
                    Image(systemName: selected.kind.symbol)
                    Text(ArchiveText.fullStamp.string(from: selected.date)).monospacedDigit()
                } else {
                    Image(systemName: "video")
                    Text("라이브")
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
                }.buttonStyle(.plain).padding(10)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 14))
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

import AppKit
import SwiftUI

struct ArchiveBrowser: View {
    let index: ArchiveIndex
    let isFiltered: Bool
    let active: Bool
    let resetFilters: () -> Void
    @State private var cardHover: CaptureRecord?
    @State private var rulerHover: CaptureRecord?
    @State private var pinned: CaptureRecord?
    @State private var detail: CaptureRecord?
    @State private var trailingVisible: CaptureRecord.ID?

    private var highlighted: CaptureRecord? { rulerHover ?? cardHover ?? pinned }

    var body: some View {
        ScrollViewReader { proxy in
            VStack(spacing: 0) {
                if index.chronological.isEmpty {
                    VStack(spacing: 7) {
                        Text(isFiltered ? "이 조건에 맞는 기록이 없습니다" : "아직 촬영한 이미지가 없습니다")
                            .font(.system(size: 16, weight: .medium))
                        if isFiltered { Button("전체 기록 보기", action: resetFilters).buttonStyle(.borderless) }
                        else {
                            Text(active ? "움직임이나 첫 입력을 기다리는 중입니다." : "감지를 켜면 이곳에 기록이 쌓입니다.")
                                .font(.callout).foregroundStyle(GlassInk.secondary)
                        }
                    }.frame(maxWidth: .infinity).frame(height: GalleryLayout.photoSize.height)
                } else {
                    ScrollView(.horizontal) {
                        LazyHStack(spacing: GalleryLayout.gap) {
                            ForEach(index.chronological) { item in
                                let selected = item.id == highlighted?.id
                                Button {
                                    pinned = item
                                    detail = item
                                } label: {
                                    RecordThumbnail(record: item, selected: selected)
                                        .frame(width: GalleryLayout.photoSize.width, height: GalleryLayout.photoSize.height)
                                }
                                .buttonStyle(.plain).id(item.id)
                                .onHover { over in
                                    if over { cardHover = item }
                                    else if cardHover?.id == item.id { cardHover = nil }
                                }
                                .accessibilityLabel("\(item.kind.eventName), \(item.date.formatted(date: .abbreviated, time: .standard))")
                            }
                        }.scrollTargetLayout()
                    }
                    .defaultScrollAnchor(.trailing)
                    .scrollPosition(id: $trailingVisible, anchor: .trailing)
                    .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { _ in
                        if let id = trailingVisible ?? index.chronological.last?.id {
                            proxy.scrollTo(id, anchor: .trailing)
                        }
                    }
                    .scrollIndicators(.hidden)
                    .frame(height: GalleryLayout.photoSize.height)
                    .padding(.horizontal, GalleryLayout.inset)
                }
                TimeRuler(index: index, pinned: cardHover ?? pinned, hover: { item in
                    rulerHover = item
                    if let item { proxy.scrollTo(item.id) }
                }, choose: { item in
                    pinned = item
                    proxy.scrollTo(item.id)
                })
                .padding(.horizontal, GalleryLayout.inset).padding(.top, GalleryLayout.gap).padding(.bottom, 12)
            }
        }
        .onChange(of: index.chronological.isEmpty, initial: true) { _, empty in
            if !empty { pinned = index.chronological.last }
        }
        .sheet(item: $detail) { item in CaptureDetail(record: item) }
        .onChange(of: index.chronological) { _, rows in
            if let pinned, !rows.contains(pinned) { self.pinned = nil }
            if let cardHover, !rows.contains(cardHover) { self.cardHover = nil }
            if let rulerHover, !rows.contains(rulerHover) { self.rulerHover = nil }
        }
    }
}

struct RecordThumbnail: View {
    let record: CaptureRecord
    let selected: Bool
    var mode: GalleryMode = .mini

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: mode == .mini ? 12 : 6, style: .continuous)
        let tile = shape.fill(GlassInk.capsule)
            .overlay { FileImage(url: record.url, detail: false, contentMode: mode == .mini ? .fill : .fit) }
            .clipShape(shape)
            .overlay(alignment: .bottomLeading) {
                if mode == .mini {
                    HStack(spacing: 5) {
                        Image(systemName: record.kind.symbol)
                        Text(ArchiveText.clock.string(from: record.date))
                    }
                    .font(.system(size: 10, weight: .semibold)).monospacedDigit()
                    .lineLimit(1).padding(.horizontal, 6).padding(.vertical, 3)
                    .background(.black.opacity(0.76), in: RoundedRectangle(cornerRadius: 5))
                    .padding(6)
                }
            }
            .overlay { if selected { shape.strokeBorder(GlassInk.blue, lineWidth: mode == .mini ? 3 : 2) } }
            .contentShape(shape)
        if mode == .standard {
            tile.aspectRatio(Picture.aspectRatio(at: record.url) ?? 1, contentMode: .fit)
        } else {
            tile
        }
    }
}

struct FileImage: View {
    let url: URL
    let detail: Bool
    var contentMode: ContentMode = .fit
    @State private var image: NSImage?
    @State private var missing = false
    var body: some View {
        Group {
            if let image {
                Image(nsImage: image).resizable().aspectRatio(contentMode: contentMode)
            } else if missing { Image(systemName: "photo.badge.exclamationmark") }
            else { ProgressView().controlSize(.small) }
        }.task(id: url) {
            image = nil
            missing = false
            let result = await Task.detached(priority: .utility) { Picture.thumbnail(at: url, pixels: detail ? 1024 : 360) }.value
            guard !Task.isCancelled else { return }
            image = result
            missing = result == nil
        }
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

import SwiftUI

struct TimeRuler: View {
    let index: ArchiveIndex
    let pinned: CaptureRecord?
    let hover: (CaptureRecord?) -> Void
    let choose: (CaptureRecord) -> Void
    var vertical = false
    @State private var pointer: Double?
    @State private var lastPosition = 0.5
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var keyboardFocus: Bool

    private func record(at position: Double?) -> CaptureRecord? {
        position.flatMap(index.nearest).map { index.chronological[$0] }
    }
    private func coordinate(_ point: CGPoint, in size: CGSize) -> Double {
        let offset = vertical ? point.y : point.x
        return min(1, max(0, offset / max(1, vertical ? size.height : size.width)))
    }

    private var active: CaptureRecord? {
        (vertical ? nil : record(at: pointer)) ?? pinned
    }

    var body: some View {
        VStack(spacing: 3) {
            if vertical, let first = index.chronological.first { dateLabel(first) }
            GeometryReader { proxy in
                let position = active.map { index.fraction(of: $0.date) }
                WaveTicks(buckets: index.marks, center: lastPosition, gain: pointer == nil ? 0 : 1,
                          currentPosition: vertical ? nil : position, reduceMotion: reduceMotion, vertical: vertical)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.11), value: lastPosition)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: pointer != nil)
                .overlay {
                    if vertical, let position {
                        let length = min(16, max(0, proxy.size.width - 4))
                        let thickness = min(2.5, proxy.size.height)
                        Capsule().fill(.white.opacity(0.94))
                            .frame(width: length, height: thickness)
                            .position(x: proxy.size.width - 4 - length / 2,
                                      y: min(max(thickness / 2, proxy.size.height * position), proxy.size.height - thickness / 2))
                            .id(position).transition(.opacity)
                    }
                }
                .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: vertical ? position : nil)
                .contentShape(Rectangle())
                .onContinuousHover { phase in
                    switch phase {
                    case .active(let point): updatePointer(coordinate(point, in: proxy.size))
                    case .ended: updatePointer(nil)
                    }
                }
                .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                    updatePointer(coordinate(value.location, in: proxy.size))
                }.onEnded { value in
                    let t = coordinate(value.location, in: proxy.size)
                    if let item = record(at: t) { choose(item); keyboardFocus = true }
                })
            }.frame(height: vertical ? nil : GalleryLayout.rulerHeight)
            if vertical {
                if let last = index.chronological.last { dateLabel(last) }
            } else {
                HStack {
                    if let first = index.chronological.first, let last = index.chronological.last {
                        let formatter = index.spansDays ? ArchiveText.stamp : ArchiveText.shortTime
                        Text(formatter.string(from: first.date))
                        Spacer()
                        Text(formatter.string(from: last.date))
                    }
                }.frame(height: GalleryLayout.clockHeight)
                .font(.system(size: 10, weight: .medium, design: .monospaced)).foregroundStyle(.white.opacity(0.70))
            }
        }
        .foregroundStyle(.white)
        .focusable(!index.chronological.isEmpty).focused($keyboardFocus)
        .focusEffectDisabled()
        .overlay(alignment: .bottom) {
            if keyboardFocus { Capsule().fill(.white.opacity(0.5)).frame(width: 20, height: 1) }
        }
        .onKeyPress(vertical ? .upArrow : .leftArrow) { step(-1); return .handled }
        .onKeyPress(vertical ? .downArrow : .rightArrow) { step(1); return .handled }
        .onChange(of: index.chronological) { _, _ in
            if let pointer { hover(record(at: pointer)) }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("시간 탐색")
        .accessibilityValue(active.map { ArchiveText.clock.string(from: $0.date) + " " + $0.kind.eventName } ?? "\(index.chronological.count)장")
        .accessibilityAdjustableAction { direction in step(direction == .increment ? 1 : -1) }
        .accessibilityIdentifier("archive.timeline")
    }

    private func dateLabel(_ item: CaptureRecord) -> some View {
        Text(ArchiveText.day.string(from: item.date))
            .font(.system(size: 10, weight: .medium, design: .monospaced))
            .foregroundStyle(GlassInk.secondary).fixedSize()
    }

    private func updatePointer(_ fraction: Double?) {
        guard pointer != fraction else { return }
        let old = record(at: pointer)
        if let fraction { lastPosition = fraction }
        pointer = fraction
        let new = record(at: fraction)
        if old?.id != new?.id { hover(new) }
    }

    private func step(_ step: Int) {
        let records = index.chronological
        guard !records.isEmpty else { return }
        let current = active.flatMap { records.firstIndex(of: $0) }
        let target = current.map { min(records.count-1, max(0, $0+step)) } ?? (step > 0 ? 0 : records.count-1)
        updatePointer(nil)
        choose(records[target])
    }
}

private struct WaveTicks: View, Animatable {
    let buckets: [Int]
    var center: Double
    var gain: Double
    let currentPosition: Double?
    let reduceMotion: Bool
    let vertical: Bool

    var animatableData: AnimatablePair<Double, Double> {
        get { AnimatablePair(center, gain) }
        set { center = newValue.first; gain = newValue.second }
    }

    var body: some View {
        Canvas { ctx, size in
            let n = buckets.count
            let width = vertical ? size.height : size.width
            let height = vertical ? size.width : size.height
            if vertical { ctx.concatenate(CGAffineTransform(a: 0, b: 1, c: 1, d: 0, tx: 0, ty: 0)) }
            let baseline = height-4
            for i in 0..<n {
                let t = Double(i)/Double(n-1)
                let x = width*t
                let major = i % 12 == 0 || i == n-1
                let events = buckets[i]
                let base: CGFloat = major ? 7 : (i.isMultiple(of: 3) ? 5 : 3)
                let distance = (t-center)*width
                let proximity = gain * exp(-pow(distance/28, 2)/2)
                let amplitude: CGFloat = vertical ? 4 : 21
                let extra = reduceMotion ? 0 : amplitude * proximity * (0.87 + 0.13 * cos(distance / 8))
                let eventHeight = events == 0 ? 0 : min(10, 5+log2(Double(events+1)))
                let h = min(max(0, baseline-5), base+extra+eventHeight)
                let color: Color
                if proximity > 0.36 { color = .white.opacity(0.95) }
                else if events > 0 { color = .white.opacity(0.83) }
                else { color = .white.opacity(major ? 0.54 : 0.32) }
                let tickWidth: CGFloat = events > 0 ? 2.6 : 1.7
                let tick = CGRect(x: min(max(0, x-tickWidth/2), max(0, width-tickWidth)),
                                  y: max(0, baseline-h), width: tickWidth, height: min(baseline,h))
                ctx.fill(Path(roundedRect: tick, cornerRadius: 1), with: .color(color))
            }
            if let currentPosition, width > 0 {
                let markerWidth = min(CGFloat(6), width)
                let x = min(max(0, width * currentPosition - markerWidth / 2), width - markerWidth)
                let marker = CGRect(x: x, y: 0, width: markerWidth, height: height)
                ctx.fill(Path(roundedRect: marker, cornerRadius: markerWidth / 2),
                         with: .color(Color(red: 1, green: 0.84, blue: 0.04)))
            }
        }
    }
}

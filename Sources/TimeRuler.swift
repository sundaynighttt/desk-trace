import SwiftUI

struct TimeRuler: View {
    let index: ArchiveIndex
    let pinned: CaptureRecord?
    let hover: (CaptureRecord?) -> Void
    let choose: (CaptureRecord) -> Void
    @State private var pointer: Double?
    @State private var lastPosition = 0.5
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var keyboardFocus: Bool

    private func record(at position: Double?) -> CaptureRecord? {
        position.flatMap(index.nearest).map { index.chronological[$0] }
    }
    private func coordinate(_ x: CGFloat, width: CGFloat) -> Double {
        min(1, max(0, x/max(1, width)))
    }

    var body: some View {
        let active = record(at: pointer) ?? pinned
        VStack(spacing: 3) {
            GeometryReader { proxy in
                WaveTicks(buckets: index.marks, center: lastPosition, gain: pointer == nil ? 0 : 1,
                          pin: pinned.map { index.fraction(of: $0.date) }, reduceMotion: reduceMotion)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.11), value: lastPosition)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: pointer != nil)
                .contentShape(Rectangle())
                .onContinuousHover { phase in
                    switch phase {
                    case .active(let point): updatePointer(coordinate(point.x, width: proxy.size.width))
                    case .ended: updatePointer(nil)
                    }
                }
                .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                    updatePointer(coordinate(value.location.x, width: proxy.size.width))
                }.onEnded { value in
                    let t = coordinate(value.location.x, width: proxy.size.width)
                    if let item = record(at: t) { choose(item); keyboardFocus = true }
                })
            }.frame(height: GalleryLayout.rulerHeight)
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
        .foregroundStyle(.white)
        .focusable(!index.chronological.isEmpty).focused($keyboardFocus)
        .focusEffectDisabled()
        .overlay(alignment: .bottom) {
            if keyboardFocus { Capsule().fill(.white.opacity(0.5)).frame(width: 20, height: 1) }
        }
        .onKeyPress(.leftArrow) { step(-1); return .handled }
        .onKeyPress(.rightArrow) { step(1); return .handled }
        .onChange(of: index.chronological) { _, _ in
            if let pointer { hover(record(at: pointer)) }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("시간 탐색")
        .accessibilityValue(active.map { ArchiveText.clock.string(from: $0.date) + " " + $0.kind.eventName } ?? "\(index.chronological.count)장")
        .accessibilityAdjustableAction { direction in step(direction == .increment ? 1 : -1) }
        .accessibilityIdentifier("archive.timeline")
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
        let current = (record(at: pointer) ?? pinned).flatMap { records.firstIndex(of: $0) }
        let target = current.map { min(records.count-1, max(0, $0+step)) } ?? (step > 0 ? 0 : records.count-1)
        updatePointer(nil)
        choose(records[target])
    }
}

private struct WaveTicks: View, Animatable {
    let buckets: [Int]
    var center: Double
    var gain: Double
    let pin: Double?
    let reduceMotion: Bool

    var animatableData: AnimatablePair<Double, Double> {
        get { AnimatablePair(center, gain) }
        set { center = newValue.first; gain = newValue.second }
    }

    var body: some View {
        Canvas { ctx, size in
            let n = buckets.count
            let width = size.width
            let baseline = size.height-4
            for i in 0..<n {
                let t = Double(i)/Double(n-1)
                let x = width*t
                let major = i % 12 == 0 || i == n-1
                let events = buckets[i]
                let base: CGFloat = major ? 7 : (i.isMultiple(of: 3) ? 5 : 3)
                let distance = (t-center)*width
                let proximity = gain * exp(-pow(distance/28, 2)/2)
                let extra = reduceMotion ? 0 : 21*proximity*(0.87+0.13*cos(distance/8))
                let eventHeight = events == 0 ? 0 : min(10, 5+log2(Double(events+1)))
                let h = min(size.height-2, base+extra+eventHeight)
                let color: Color
                if proximity > 0.36 { color = GlassInk.blue }
                else if events > 0 { color = .white.opacity(0.83) }
                else { color = .white.opacity(major ? 0.54 : 0.32) }
                let tickWidth: CGFloat = events > 0 ? 2.6 : 1.7
                let tick = CGRect(x: min(max(0, x-tickWidth/2), max(0, width-tickWidth)),
                                  y: max(0, baseline-h), width: tickWidth, height: min(baseline,h))
                ctx.fill(Path(roundedRect: tick, cornerRadius: 1), with: .color(color))
            }
            if let cursor = gain > 0.02 ? center : pin {
                let x = min(max(2.5, width*cursor), width-2.5)
                ctx.fill(Path(ellipseIn: CGRect(x: x-2.5, y: baseline-1, width: 5, height: 5)), with: .color(GlassInk.blue))
            }
        }
    }
}

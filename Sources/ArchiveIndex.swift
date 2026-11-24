import Foundation

/// Input is the store's newest-first order. Rebuild only when the records or filters change.
struct ArchiveIndex {
    let chronological: [CaptureRecord]
    let displayed: [CaptureRecord]
    let availableDates: [Date]
    let marks: [Int]
    let spansDays: Bool

    init(newestFirst: [CaptureRecord], day: Date?, kind: CaptureKind?, newest: Bool,
         calendar: Calendar = .current) {
        var dates = [Date]()
        var filtered = [CaptureRecord]()
        for record in newestFirst {
            let date = calendar.startOfDay(for: record.date)
            if dates.last != date { dates.append(date) }
            if (day == nil || date == day), (kind == nil || record.kind == kind) {
                filtered.append(record)
            }
        }
        availableDates = dates
        let ascending = Array(filtered.reversed())
        chronological = ascending
        displayed = newest ? filtered : ascending
        if let first = ascending.first, let last = ascending.last {
            spansDays = !calendar.isDate(first.date, inSameDayAs: last.date)
        } else {
            spansDays = false
        }
        var counts = [Int](repeating: 0, count: 144)
        if let first = ascending.first, let last = ascending.last {
            let span = last.date.timeIntervalSince(first.date)
            for record in ascending {
                let fraction = span > 0 ? record.date.timeIntervalSince(first.date) / span : 0.5
                counts[Int((fraction * Double(counts.count-1)).rounded())] += 1
            }
        }
        marks = counts
    }

    func fraction(of date: Date) -> Double {
        guard let first = chronological.first, let last = chronological.last, first.date < last.date else { return 0.5 }
        return min(1, max(0, date.timeIntervalSince(first.date) / last.date.timeIntervalSince(first.date)))
    }

    func nearest(to fraction: Double) -> Int? {
        guard let first = chronological.first, let last = chronological.last else { return nil }
        let target = first.date.addingTimeInterval(min(1, max(0, fraction)) * last.date.timeIntervalSince(first.date))
        var low = 0, high = chronological.count
        while low < high {
            let mid = low + (high-low)/2
            if chronological[mid].date < target { low = mid+1 } else { high = mid }
        }
        guard low > 0 else { return 0 }
        guard low < chronological.count else { return low-1 }
        return target.timeIntervalSince(chronological[low-1].date) <= chronological[low].date.timeIntervalSince(target) ? low-1 : low
    }
}

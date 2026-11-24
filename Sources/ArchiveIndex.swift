import Foundation

enum ArchivePeriod: String, CaseIterable {
    case today = "오늘"
    case week = "일주일"
    case month = "한달"
    case all = "전체"

    func dateRange(relativeTo now: Date, in calendar: Calendar) -> Range<Date>? {
        let days: Int
        switch self {
        case .today: days = 1
        case .week: days = 7
        case .month: days = 30
        case .all: return nil
        }
        guard let today = calendar.dateInterval(of: .day, for: now),
              let start = calendar.date(byAdding: .day, value: 1 - days, to: today.start) else { return nil }
        return calendar.startOfDay(for: start)..<today.end
    }
}

/// Input is the store's newest-first order. Rebuild only when the records or filters change.
struct ArchiveIndex {
    let chronological: [CaptureRecord]
    let displayed: [CaptureRecord]
    let marks: [Int]
    let spansDays: Bool

    init(newestFirst: [CaptureRecord], period: ArchivePeriod, kind: CaptureKind?, newest: Bool,
         now: Date = Date(), calendar: Calendar = .current) {
        let range = period.dateRange(relativeTo: now, in: calendar)
        let filtered = newestFirst.filter { record in
            (range?.contains(record.date) ?? true) && (kind == nil || record.kind == kind)
        }
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

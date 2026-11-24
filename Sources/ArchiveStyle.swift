import Foundation

enum ArchiveText {
    private static func formatter(_ pattern: String) -> DateFormatter {
        let value = DateFormatter()
        value.locale = Locale(identifier: "ko_KR")
        value.timeZone = .autoupdatingCurrent
        value.dateFormat = pattern
        return value
    }
    static let day = formatter("MM.dd")
    static let fullStamp = formatter("MM.dd  HH:mm:ss")
    static let clock = formatter("HH:mm:ss")
    static let shortTime = formatter("HH:mm")
    static let stamp = formatter("MM.dd  HH:mm")
}

extension CaptureKind {
    var eventName: String { self == .camera ? "움직임" : "첫 입력" }
}

enum GalleryMode: String, CaseIterable {
    case mini = "미니"
    case standard = "일반"
}

enum GalleryLayout {
    static let inset: CGFloat = 25
    static let gap: CGFloat = 12
    static let photoSize = CGSize(width: 132, height: 87)
    static let rulerHeight: CGFloat = 31
    static let clockHeight: CGFloat = 13
    // Header (8+34), two gaps, photo, ruler, clock spacing and bottom inset.
    static let minimumHeight = 8 + 34 + gap * 2 + photoSize.height + rulerHeight + 3 + clockHeight + 12
}

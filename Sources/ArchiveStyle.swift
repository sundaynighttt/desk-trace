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
    static let groupDate = formatter("yyyy.MM.dd")
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
    static let filterButtonHeight: CGFloat = 28
    static let filterVerticalInset: CGFloat = 7
    static let filterHeight = filterButtonHeight + 2 * filterVerticalInset
    static let photoSize = CGSize(width: 132, height: 87)
    static func standardThumbnailWidth(windowWidth: CGFloat) -> CGFloat {
        // The thumbnail scale is based on the original gallery's symmetric insets.
        let referenceWidth = windowWidth - inset * 2
        let fullWidth = max(165, (referenceWidth - 74) * 0.36)
        return ((fullWidth / 3) / 2).rounded() * 2
    }

    static let archiveTextInset: CGFloat = 2
    static let standardRulerGap: CGFloat = 12
    static let standardTrailingInset: CGFloat = 10
    static let standardRulerWidth: CGFloat = 32
    static let defaultVideoAspect: CGFloat = 16.0 / 9.0
    static let standardBottomInset: CGFloat = 16

    static func standardOpeningHeight(windowWidth: CGFloat) -> CGFloat {
        let contentWidth = windowWidth - inset - standardTrailingInset
        let viewerWidth = contentWidth - standardThumbnailWidth(windowWidth: windowWidth) - standardRulerWidth - gap - standardRulerGap
        return max(350, ceil(viewerWidth / defaultVideoAspect) + 8 + filterHeight + gap + standardBottomInset)
    }

    static let rulerHeight: CGFloat = 31
    static let clockHeight: CGFloat = 13
    // Header, two gaps, photo, ruler, clock spacing and bottom inset.
    static let minimumHeight = 8 + filterHeight + gap * 2 + photoSize.height + rulerHeight + 3 + clockHeight + 12
}

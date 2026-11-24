import Foundation

enum ArchiveText {
    private static func formatter(_ pattern: String) -> DateFormatter {
        let value = DateFormatter()
        value.locale = Locale(identifier: "ko_KR")
        value.timeZone = .autoupdatingCurrent
        value.dateFormat = pattern
        return value
    }
    static let clock = formatter("HH:mm:ss")
    static let shortTime = formatter("HH:mm")
    static let stamp = formatter("MM.dd  HH:mm")
}

extension CaptureKind {
    var eventName: String { self == .camera ? "움직임" : "첫 입력" }
}

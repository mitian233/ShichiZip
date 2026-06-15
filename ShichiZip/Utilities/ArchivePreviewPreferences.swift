import Foundation

/// Archive-preview defaults shared by the main app and the Quick Look extension.
///
/// The extension runs out of process and cannot see `SZSettings`, so the canonical
/// expansion-depth key and its default/clamp live here where both targets compile it.
enum ArchivePreviewPreferences {
    private enum TimestampDisplayLevel: Int {
        case day
        case minute
        case second
        case ntfs
        case nanoseconds

        var dateFormat: String {
            switch self {
            case .day:
                "yyyy-MM-dd"
            case .minute:
                "yyyy-MM-dd HH:mm"
            case .second:
                "yyyy-MM-dd HH:mm:ss"
            case .ntfs:
                "yyyy-MM-dd HH:mm:ss.SSSSSSS"
            case .nanoseconds:
                "yyyy-MM-dd HH:mm:ss.SSSSSSSSS"
            }
        }
    }

    private static let timestampUTCKey = "FileManager.TimestampUTC"
    private static let timestampLevelKey = "FileManager.TimestampLevel"
    static let expansionDepthKey = "QuickLookPreviewExpansionDepth"
    static let defaultExpansionDepth = 3
    static let maximumExpansionDepth = 10

    static func expansionDepth(defaults: UserDefaults = SZSharedUserDefaults.defaults) -> Int {
        guard defaults.object(forKey: expansionDepthKey) != nil else {
            return defaultExpansionDepth
        }

        return normalizedExpansionDepth(defaults.integer(forKey: expansionDepthKey))
    }

    static func normalizedExpansionDepth(_ depth: Int) -> Int {
        min(max(0, depth), maximumExpansionDepth)
    }

    static func makeListDateFormatter(defaults: UserDefaults = SZSharedUserDefaults.defaults) -> DateFormatter {
        let rawLevel = defaults.object(forKey: timestampLevelKey) == nil
            ? TimestampDisplayLevel.minute.rawValue
            : defaults.integer(forKey: timestampLevelKey)
        let level = TimestampDisplayLevel(rawValue: rawLevel) ?? .minute

        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = level.dateFormat
        formatter.timeZone = defaults.object(forKey: timestampUTCKey) != nil && defaults.bool(forKey: timestampUTCKey)
            ? TimeZone(secondsFromGMT: 0)
            : .current
        return formatter
    }
}

import Foundation

/// How long ago, written out (UIUX.md → Search): "just now", "4 minutes ago", "2 hours ago",
/// "yesterday", "3 days ago", then the date. The sidebar's cards say "4m"; a search result has
/// the room to say it in words.
public enum WrittenTime {
    /// A stretch of the text: figures are drawn a step brighter than the words around them.
    public struct Run: Equatable, Sendable {
        public let text: String
        public let isNumber: Bool
    }

    public static func text(since date: Date, now: Date = Date()) -> String {
        let seconds = max(now.timeIntervalSince(date), 0)
        switch seconds {
        case ..<60: return "just now"
        case ..<3600: return counted(Int(seconds / 60), "minute")
        case ..<86400: return counted(Int(seconds / 3600), "hour")
        case ..<(2 * 86400): return "yesterday"
        case ..<(7 * 86400): return counted(Int(seconds / 86400), "day")
        default:
            let sameYear = Calendar.current.isDate(date, equalTo: now, toGranularity: .year)
            return date.formatted(sameYear ? .dateTime.month(.abbreviated).day() : .dateTime.month(.abbreviated).day().year())
        }
    }

    /// `text` split into figures and the rest.
    public static func runs(_ text: String) -> [Run] {
        var runs: [Run] = []
        var current = ""
        var inNumber = false
        for character in text {
            let isDigit = character.isNumber
            if !current.isEmpty, isDigit != inNumber {
                runs.append(Run(text: current, isNumber: inNumber))
                current = ""
            }
            inNumber = isDigit
            current.append(character)
        }
        if !current.isEmpty {
            runs.append(Run(text: current, isNumber: inNumber))
        }
        return runs
    }

    private static func counted(_ count: Int, _ unit: String) -> String {
        "\(count) \(unit)\(count == 1 ? "" : "s") ago"
    }
}

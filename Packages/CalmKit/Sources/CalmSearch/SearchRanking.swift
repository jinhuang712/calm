import Foundation

/// How search results are ordered (FEATURES.md → F7): text relevance first, then title
/// matches, recency and the current project as smaller boosts.
public enum SearchRanking {
    static let titleWeight = 0.35
    static let recencyWeight = 0.3
    static let projectWeight = 0.2

    /// BM25 scores are negative, lower is better; this maps them to 0…1 against the query's best.
    public static func relevance(rank: Double, best: Double) -> Double {
        guard best < 0 else { return 1 } // LIKE matches (short terms) carry no rank
        return min(max(rank / best, 0), 1)
    }

    /// 1 today, 0.5 after a week, fading slowly after that.
    public static func recency(of date: Date, now: Date) -> Double {
        let days = max(now.timeIntervalSince(date), 0) / 86400
        return 1 / (1 + days / 7)
    }

    public static func score(relevance: Double, titleMatches: Bool, lastActive: Date, inCurrentProject: Bool, now: Date) -> Double {
        relevance
            + (titleMatches ? titleWeight : 0)
            + recencyWeight * recency(of: lastActive, now: now)
            + (inCurrentProject ? projectWeight : 0)
    }
}

/// Turning what the user typed into index queries.
enum SearchQuery {
    /// Whitespace-separated terms; every one must appear somewhere in a session.
    static func terms(in query: String) -> [String] {
        query.split(whereSeparator: \.isWhitespace).map(String.init).filter { !$0.isEmpty }
    }

    /// A term as an FTS5 phrase, so its characters are matched literally.
    static func phrase(_ term: String) -> String {
        "\"" + term.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    static func likePattern(_ term: String) -> String {
        let escaped = term
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "%", with: "\\%")
            .replacingOccurrences(of: "_", with: "\\_")
        return "%\(escaped)%"
    }

    /// An excerpt from the first match on, marked with U+0002 and U+0003. It opens a few words
    /// before the match, so the match stays on screen when the row truncates the rest.
    static func snippet(_ text: String, around term: String, before: Int = 28, after: Int = 160) -> String {
        let flat = text.split(whereSeparator: \.isNewline).joined(separator: " ")
        guard let range = SearchMatch.firstRange(of: term, in: flat) else {
            return String(flat.prefix(after))
        }
        var start = flat.index(range.lowerBound, offsetBy: -before, limitedBy: flat.startIndex) ?? flat.startIndex
        if start > flat.startIndex, let space = flat[start ..< range.lowerBound].firstIndex(of: " ") {
            start = flat.index(after: space) // begin on a whole word
        }
        let end = flat.index(range.upperBound, offsetBy: after, limitedBy: flat.endIndex) ?? flat.endIndex
        let prefix = start > flat.startIndex ? "…" : ""
        let suffix = end < flat.endIndex ? "…" : ""
        return prefix + flat[start ..< range.lowerBound] + "\u{2}" + flat[range] + "\u{3}" + flat[range.upperBound ..< end] + suffix
    }

    /// The stretch of `text` (one line) that holds the first match of each of `terms`, with
    /// `margin` characters either side, opening on a whole word: all a row's line can show of a
    /// long message.
    static func excerpt(_ text: String, around terms: [String], margin: Int = 240) -> (text: String, cutBefore: Bool) {
        let ranges = terms.compactMap { SearchMatch.firstRange(of: $0, in: text) }
        guard let first = ranges.map(\.lowerBound).min(), let last = ranges.map(\.upperBound).max() else {
            return (String(text.prefix(margin * 2)), false)
        }
        var start = text.index(first, offsetBy: -margin, limitedBy: text.startIndex) ?? text.startIndex
        if start > text.startIndex, let space = text[start ..< first].firstIndex(of: " ") {
            start = text.index(after: space)
        }
        let end = text.index(last, offsetBy: margin, limitedBy: text.endIndex) ?? text.endIndex
        return (String(text[start ..< end]), start > text.startIndex)
    }
}

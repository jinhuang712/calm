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

    /// A short excerpt around the first match, marked like FTS5's snippets.
    static func snippet(_ text: String, around term: String, context: Int = 40) -> String {
        let flat = text.replacingOccurrences(of: "\n", with: " ")
        guard let range = flat.range(of: term, options: .caseInsensitive) else { return String(flat.prefix(context * 2)) }
        let start = flat.index(range.lowerBound, offsetBy: -context, limitedBy: flat.startIndex) ?? flat.startIndex
        let end = flat.index(range.upperBound, offsetBy: context, limitedBy: flat.endIndex) ?? flat.endIndex
        let prefix = start > flat.startIndex ? "…" : ""
        let suffix = end < flat.endIndex ? "…" : ""
        return prefix + flat[start ..< range.lowerBound] + "\u{2}" + flat[range] + "\u{3}" + flat[range.upperBound ..< end] + suffix
    }
}

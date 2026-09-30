import CalmAgents
import Foundation

public extension SearchResult {
    /// A message of the session that holds words the user typed: what the rows under a result's
    /// title are made of (UIUX.md → Search).
    struct Line: Sendable, Equatable {
        /// The message's place in the index, which is the order it was said in.
        public var id: Int64
        public var role: TranscriptMessage.Role
        /// On one line, and cut to the part around the words when the message is long.
        public var text: String
        /// Whether the message goes on before `text` starts.
        public var cutBefore: Bool
        /// The query's terms it holds.
        public var terms: [String]

        public init(id: Int64, role: TranscriptMessage.Role, text: String, cutBefore: Bool = false, terms: [String]) {
            self.id = id
            self.role = role
            self.text = text
            self.cutBefore = cutBefore
            self.terms = terms
        }
    }

    /// The lines to show under the title: the fewest that put every word on screen, at most
    /// three, in the order they were said. A word already on screen (`shown`: in the title, or
    /// in the project's name) needs none; when every word is, one line shows, for context.
    func linesToShow(terms: [String], shown: Set<String>) -> [Line] {
        var needed = terms.filter { !shown.contains($0) }
        var chosen: [Line] = []
        while chosen.count < 3 {
            // Once every word is on screen, one line still shows, so the row says what was said.
            let pool = needed.isEmpty ? (chosen.isEmpty ? terms : []) : needed
            guard !pool.isEmpty else { break }
            var best: Line?
            var bestCount = 0
            for line in lines where !chosen.contains(where: { $0.id == line.id }) {
                let count = line.terms.count { pool.contains($0) }
                if count > bestCount {
                    best = line
                    bestCount = count
                }
            }
            guard let best else { break }
            chosen.append(best)
            needed.removeAll { best.terms.contains($0) }
            if needed.isEmpty {
                break
            }
        }
        return chosen.sorted { $0.id < $1.id }
    }
}

/// One line built around the words it has to show (UIUX.md → Search): a few words of context
/// around each, trimmed before a word ever is, and the stretch between two words far apart
/// left out.
public enum SearchLineFit {
    public enum Part: Equatable, Sendable {
        case text(String)
        /// Words left out, drawn as "…".
        case gap
    }

    /// Words of context kept before and after each match, given up in this order until the line
    /// fits.
    static let contexts: [(before: Int, after: Int)] = [(3, 3), (2, 2), (2, 1), (1, 1), (1, 0), (0, 0)]

    /// `text` as parts that show every one of `terms` it holds within `width`, as `measure`
    /// measures a string (a gap counts as "… "). The text after the last word follows, for the
    /// line to cut where it ends.
    public static func parts(
        _ text: String,
        terms: [String],
        cutBefore: Bool = false,
        width: Double,
        measure: (String) -> Double,
    ) -> [Part] {
        let matches = terms.compactMap { SearchMatch.firstRange(of: $0, in: text) }
        guard !matches.isEmpty else { return (cutBefore ? [.gap] : []) + [.text(text)] }
        for context in contexts {
            let segments = matches.map { match in
                var start = wordStart(before: match.lowerBound, in: text)
                var end = wordEnd(after: match.upperBound, in: text)
                for _ in 0 ..< context.before where start > text.startIndex {
                    start = wordStart(before: text.index(before: start), in: text)
                }
                for _ in 0 ..< context.after where end < text.endIndex {
                    end = wordEnd(after: text.index(after: end), in: text)
                }
                return start ..< end
            }
            let built = build(segments, in: text, cutBefore: cutBefore)
            if measure(built.shown) <= width {
                return built.parts
            }
        }
        // A single word wider than the line (a long path): cut into it, a little before the match.
        let segments = matches.map { match in
            (text.index(match.lowerBound, offsetBy: -12, limitedBy: text.startIndex) ?? text.startIndex)
                ..< (text.index(match.upperBound, offsetBy: 3, limitedBy: text.endIndex) ?? text.endIndex)
        }
        return build(segments, in: text, cutBefore: cutBefore).parts
    }

    /// The parts for `segments`, and the text they show before the tail, for measuring.
    private static func build(_ segments: [Range<String.Index>], in text: String, cutBefore: Bool) -> (parts: [Part], shown: String) {
        var merged: [Range<String.Index>] = []
        for segment in segments.sorted(by: { $0.lowerBound < $1.lowerBound }) {
            // Next to each other, or only a space apart: one stretch.
            if let last = merged.last,
               segment.lowerBound <= (last.upperBound < text.endIndex ? text.index(after: last.upperBound) : last.upperBound) {
                merged[merged.count - 1] = last.lowerBound ..< max(last.upperBound, segment.upperBound)
            } else {
                merged.append(segment)
            }
        }
        var parts: [Part] = []
        var shown = ""
        if cutBefore || merged[0].lowerBound > text.startIndex {
            parts.append(.gap)
            shown += "… "
        }
        for (index, segment) in merged.enumerated() {
            if index > 0 {
                parts.append(.gap)
                shown += " … "
            }
            let piece = String(text[segment])
            // The last stretch runs on to the message's end, for the line to cut; only what's
            // before the tail has to fit.
            parts.append(.text(index == merged.count - 1 ? piece + text[segment.upperBound...] : piece))
            shown += piece
        }
        return (parts, shown)
    }

    /// Where the word holding `index` starts.
    private static func wordStart(before index: String.Index, in text: String) -> String.Index {
        var start = index
        while start > text.startIndex, text[text.index(before: start)] != " " {
            start = text.index(before: start)
        }
        return start
    }

    /// Where the word holding the character before `index` ends.
    private static func wordEnd(after index: String.Index, in text: String) -> String.Index {
        var end = index
        while end < text.endIndex, text[end] != " " {
            end = text.index(after: end)
        }
        return end
    }
}

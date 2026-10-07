import Foundation

/// What find looks for (FEATURES.md → F16): plain words, matched as libghostty's search matches
/// them (`FindMatcher`), or a pattern, with `.*` on. A pattern is ICU's, as `NSRegularExpression`
/// reads it, case-insensitive unless it starts with `(?-i)`, and matched line by line, so a match
/// never crosses a line's end (DESIGNS.md → Find, regular expressions).
public struct FindQuery: Sendable {
    public let words: String
    public let isPattern: Bool
    private let expression: Expression?

    /// `NSRegularExpression` is immutable and safe to share across threads (Apple's docs), but
    /// isn't marked Sendable.
    private struct Expression: @unchecked Sendable {
        let value: NSRegularExpression
    }

    /// Nil for no words, or for a pattern that isn't one (yet: `warn(` while it's being typed).
    public init?(words: String, isPattern: Bool) {
        guard !words.isEmpty else { return nil }
        self.words = words
        self.isPattern = isPattern
        if isPattern {
            guard let expression = try? NSRegularExpression(pattern: words, options: [.caseInsensitive]) else { return nil }
            self.expression = Expression(value: expression)
        } else {
            expression = nil
        }
    }

    /// Where the query matches in one line, as UTF-16 ranges, left to right. Plain words count a
    /// match at every place one starts, overlapping ones too, as the engine does; a pattern's
    /// matches don't overlap, and one that matches nothing (`a*` before a b) isn't counted.
    public func ranges(in line: String) -> [Range<Int>] {
        guard let expression else {
            let needle = Array(words.utf16)
            return FindMatcher.starts(of: needle, in: Array(line.utf16)).map { $0 ..< $0 + needle.count }
        }
        let whole = NSRange(location: 0, length: (line as NSString).length)
        return expression.value.matches(in: line, range: whole).compactMap { match in
            match.range.length > 0 ? match.range.location ..< match.range.location + match.range.length : nil
        }
    }

    /// How many matches `text` holds, line by line.
    public func count(in text: String) -> Int {
        guard isPattern else { return FindMatcher.count(of: words, in: text) }
        var count = 0
        text.enumerateLines { line, _ in count += ranges(in: line).count }
        return count
    }
}

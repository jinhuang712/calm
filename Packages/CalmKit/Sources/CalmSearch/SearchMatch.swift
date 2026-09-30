import Foundation

/// Where a word the user typed counts as found (FEATURES.md → F7). One rule for the index and for
/// what search marks on screen, so every mark is a match and every match can be marked.
public enum SearchMatch {
    /// One or two letters or digits match only where a word starts: "d" finds "Draft" and
    /// "default", not the d inside "hardware", which every session holds. From three characters
    /// on, a match anywhere counts. A term that starts in another script (Chinese, say) matches
    /// anywhere at any length: its words aren't set apart by spaces.
    public static func startsWords(_ term: String) -> Bool {
        guard term.count < 3, let first = term.unicodeScalars.first else { return false }
        return first.isASCII && CharacterSet.alphanumerics.contains(first)
    }

    /// Whether `text` holds `term` under the rule, ignoring case and accents.
    public static func contains(_ text: String, _ term: String) -> Bool {
        firstRange(of: term, in: text) != nil
    }

    public static func firstRange(of term: String, in text: String) -> Range<String.Index>? {
        ranges(of: term, in: text, firstOnly: true).first
    }

    /// Every match of every term in `text`, in order, with overlapping ones merged: what to mark.
    public static func ranges(of terms: [String], in text: String) -> [Range<String.Index>] {
        let all = terms.flatMap { ranges(of: $0, in: text, firstOnly: false) }.sorted { $0.lowerBound < $1.lowerBound }
        var merged: [Range<String.Index>] = []
        for range in all {
            if let last = merged.last, range.lowerBound <= last.upperBound {
                merged[merged.count - 1] = last.lowerBound ..< max(last.upperBound, range.upperBound)
            } else {
                merged.append(range)
            }
        }
        return merged
    }

    private static func ranges(of term: String, in text: String, firstOnly: Bool) -> [Range<String.Index>] {
        guard !term.isEmpty else { return [] }
        let wordStart = startsWords(term)
        var found: [Range<String.Index>] = []
        var from = text.startIndex
        while from < text.endIndex,
              let range = text.range(of: term, options: [.caseInsensitive, .diacriticInsensitive], range: from ..< text.endIndex) {
            if !wordStart || range.lowerBound == text.startIndex || !isWordCharacter(text[text.index(before: range.lowerBound)]) {
                found.append(range)
                if firstOnly {
                    break
                }
            }
            from = range.upperBound > range.lowerBound ? range.upperBound : text.index(after: range.lowerBound)
        }
        return found
    }

    static func isWordCharacter(_ character: Character) -> Bool {
        character.isLetter || character.isNumber
    }
}

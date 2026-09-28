import Foundation

/// Values read from the text of a Ghostty config, for the few that Ghostty's C API can't return
/// (repeatable keys have no C value).
public enum GhosttyConfigText {
    /// The terminal's main font: the first `font-family` after the last empty one, since Ghostty
    /// adds each line as a fallback and `font-family =` clears the list. `nil` when the config
    /// leaves it at Ghostty's default.
    public static func fontFamily(in text: String) -> String? {
        var families: [String] = []
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.hasPrefix("#"), let equals = trimmed.firstIndex(of: "="),
                  trimmed[..<equals].trimmingCharacters(in: .whitespaces) == "font-family" else { continue }
            var value = trimmed[trimmed.index(after: equals)...].trimmingCharacters(in: .whitespaces)
            if value.count >= 2, value.hasPrefix("\""), value.hasSuffix("\"") {
                value = String(value.dropFirst().dropLast())
            }
            if value.isEmpty {
                families.removeAll()
            } else {
                families.append(value)
            }
        }
        return families.first
    }
}

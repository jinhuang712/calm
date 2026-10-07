import Foundation

/// Find's map (FEATURES.md → F16, UIUX.md → Find): every line of the scrollback with a match, and
/// the row it starts on, so the map along the pane's edge can put a tick there. Made from the
/// scrollback's text as libghostty reads it (`GHOSTTY_POINT_SCREEN`): soft-wrapped rows joined,
/// one line per line of output, so a line's rows are its width over the pane's columns.
public struct FindMap: Equatable, Sendable {
    /// A line with matches.
    public struct Line: Equatable, Sendable {
        /// The row it starts on, counted from the top of the scrollback.
        public let row: Int
        /// Its number, from 1 at the top of the scrollback.
        public let number: Int
        /// How many matches it has, left to right.
        public let matches: Int
        /// Its text, cut for the map's tag.
        public let text: String
    }

    public let lines: [Line]
    /// The rows the scrollback's text fills.
    public let rows: Int
    /// The matches in all the lines.
    public let matches: Int

    /// The tag's longest text.
    static let tagLength = 64

    public init(lines: [Line], rows: Int) {
        self.lines = lines
        self.rows = rows
        matches = lines.reduce(0) { $0 + $1.matches }
    }

    /// The map of `words` in the scrollback's `text`, in a pane `columns` wide. One pass over the
    /// bytes, matching as the engine does (`FindMatcher`); a line's width is its byte count unless
    /// it has more than ASCII (then its characters' cells), since this runs over megabytes.
    public static func scan(_ text: String, words: String, columns: Int) -> FindMap {
        FindQuery(words: words, isPattern: false).map { scan(text, query: $0, columns: columns) } ?? FindMap(lines: [], rows: 0)
    }

    /// The map of `query` in the scrollback's `text`. A pattern is matched line by line on the
    /// line's characters, which is slower than the bytes plain words are matched on; both run off
    /// the main thread.
    public static func scan(_ text: String, query: FindQuery, columns: Int) -> FindMap {
        let needle = Array(query.words.utf8).map(fold)
        guard !needle.isEmpty, columns > 0 else { return FindMap(lines: [], rows: 0) }
        var text = text
        return text.withUTF8 { bytes in
            var lines: [Line] = []
            var row = 0
            var number = 1
            var start = 0
            while start < bytes.count {
                var end = start
                var isASCII = true
                while end < bytes.count, bytes[end] != 0x0A {
                    if bytes[end] >= 0x80 {
                        isASCII = false
                    }
                    end += 1
                }
                let line = UnsafeBufferPointer(rebasing: bytes[start ..< end])
                // A line ends at a newline, so it's whole UTF-8, as the text was.
                let width = isASCII ? line.count : cells(String(bytes: line, encoding: .utf8) ?? "")
                let count = query.isPattern
                    ? query.ranges(in: String(bytes: line, encoding: .utf8) ?? "").count
                    : matches(of: needle, in: line)
                if count > 0 {
                    let words = (String(bytes: line, encoding: .utf8) ?? "").trimmingCharacters(in: .whitespaces)
                    lines.append(Line(row: row, number: number, matches: count, text: String(words.prefix(tagLength))))
                }
                row += max(1, (width + columns - 1) / columns)
                number += 1
                start = end + 1
            }
            return FindMap(lines: lines, rows: row)
        }
    }

    /// Which line holds the match `selected`, counted from the newest (libghostty's index).
    public func line(holding selected: Int) -> Int? {
        var remaining = matches - 1 - selected
        guard remaining >= 0 else { return nil }
        for (index, line) in lines.enumerated() {
            if remaining < line.matches {
                return index
            }
            remaining -= line.matches
        }
        return nil
    }

    /// libghostty's index of the first match on `line`, counted from the newest: where a click
    /// on its tick goes.
    public func selection(of line: Int) -> Int? {
        guard lines.indices.contains(line) else { return nil }
        let before = lines[..<line].reduce(0) { $0 + $1.matches }
        return matches - 1 - before
    }

    /// The ticks for a map `height` points tall over `total` rows: one per slot of `slot` points
    /// holding a line, with how many lines share it (they draw darker), top to bottom.
    public func ticks(height: Double, total: Int, slot: Double = 2) -> [(y: Double, lines: Int)] {
        guard height > 0, total > 0 else { return [] }
        var ticks: [(y: Double, lines: Int)] = []
        for line in lines {
            let y = min((Double(line.row) / Double(total) * height / slot).rounded(.down) * slot, max(height - slot, 0))
            if let last = ticks.last, last.y == y {
                ticks[ticks.count - 1].lines += 1
            } else {
                ticks.append((y, 1))
            }
        }
        return ticks
    }

    /// Where `line`'s tick is on a map `height` points tall over `total` rows.
    public func y(of line: Int, height: Double, total: Int) -> Double? {
        guard lines.indices.contains(line), total > 0 else { return nil }
        return min(Double(lines[line].row) / Double(total) * height, height)
    }

    /// The line whose tick is nearest `y`, within `reach` points.
    public func line(near y: Double, height: Double, total: Int, reach: Double = 6) -> Int? {
        var best: (index: Int, distance: Double)?
        for index in lines.indices {
            guard let tick = self.y(of: index, height: height, total: total) else { continue }
            let distance = abs(tick - y)
            if distance <= reach, distance < (best?.distance ?? .infinity) {
                best = (index, distance)
            }
        }
        return best?.index
    }

    private static func matches(of needle: [UInt8], in line: UnsafeBufferPointer<UInt8>) -> Int {
        guard needle.count <= line.count else { return 0 }
        var count = 0
        let first = needle[0]
        for start in 0 ... line.count - needle.count where fold(line[start]) == first {
            var index = 1
            while index < needle.count, fold(line[start + index]) == needle[index] {
                index += 1
            }
            if index == needle.count {
                count += 1
            }
        }
        return count
    }

    private static func cells(_ line: String) -> Int {
        line.reduce(0) { $0 + CellWidth.of($1) }
    }

    private static func fold(_ byte: UInt8) -> UInt8 {
        (0x41 ... 0x5A).contains(byte) ? byte + 0x20 : byte
    }
}

import Foundation

/// Rows that one line of text goes on across because a program cut it, not because the terminal
/// wrapped it (FEATURES.md → F8). An agent's full-screen view lays its text out to its own width and
/// breaks a word longer than that (a URL, a long path) with a line break of its own, indenting the
/// rest; libghostty joins only what the terminal wrapped, so it sees two unrelated rows.
///
/// A row goes on in the next one when the program filled it: its text runs to the right edge, and
/// the next row starts a word after a short indent. That is a guess (a word that happens to end at
/// the edge looks the same), so callers accept a joined link only when it leads somewhere.
public enum HardWrap {
    /// How far from the last column a filled row may end: a scrollbar or a margin takes a column or two.
    static let edgeSlack = 3
    /// The most a continuation row may be indented; text set further in is not the rest of a word.
    static let maxIndent = 16

    /// The rows of one or more lines (as the terminal wrapped them), read as one.
    public struct Joined: Equatable, Sendable {
        public let rows: Range<Int>
        /// Rows that carry on from the row above: the indent in front of their text isn't part of it.
        public let continuations: Set<Int>

        /// Whether the link runs over one of the program's own line breaks.
        public func crosses(_ match: LinkMatch) -> Bool {
            match.runs.contains { run in
                continuations.contains(run.row) && match.runs.contains { $0.row == run.row - 1 }
            }
        }
    }

    /// The lines that carry on into the next one, each with the ones it carries on into. `lines` are the
    /// screen's rows grouped as the terminal wrapped them, top to bottom; lines the program didn't
    /// cut aren't returned.
    public static func joined(_ grid: TextGrid, lines: [Range<Int>], columns: Int) -> [Joined] {
        var joined: [Joined] = []
        var current: Joined?
        for (index, line) in lines.enumerated() {
            if let open = current {
                current = Joined(rows: open.rows.lowerBound ..< line.upperBound, continuations: open.continuations.union([line.lowerBound]))
            }
            let carriesOn = index + 1 < lines.count && goesOn(grid, row: line.upperBound - 1, columns: columns)
            if carriesOn {
                current = current ?? Joined(rows: line, continuations: [])
            } else if let done = current {
                joined.append(done)
                current = nil
            }
        }
        return joined
    }

    /// Whether the program filled `row` and went on in the next one.
    static func goesOn(_ grid: TextGrid, row: Int, columns: Int) -> Bool {
        guard grid.cells.indices.contains(row), grid.cells.indices.contains(row + 1),
              let last = grid.cells[row].lastIndex(where: { $0.map { !$0.isWhitespace } ?? false }),
              let width = grid.cells[row][last].map({ max(CellWidth.of($0), 1) }),
              last + width >= columns - edgeSlack
        else { return false }
        // The next row's text starts a word, not far in.
        let next = grid.cells[row + 1]
        guard let start = next.firstIndex(where: { $0.map { !$0.isWhitespace } ?? false }) else { return false }
        return start <= maxIndent
    }
}

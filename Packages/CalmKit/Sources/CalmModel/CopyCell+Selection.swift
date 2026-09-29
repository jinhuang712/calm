import Foundation

/// An ⌥-drag inside a table cell (FEATURES.md → F9): text selected from one point to another in
/// reading order, never crossing the cell's own lines. A normal selection runs across a whole row,
/// so in a cell that wraps onto several lines it picks up the neighbouring cells' text too.
public extension CopyCell {
    /// What an ⌥-drag selected: the text (the cell's wrapped lines joined, as Copy Cell joins
    /// them) and the cells it covers, one run per line, for drawing it.
    struct Selection: Equatable, Sendable {
        public let text: String
        public let runs: [CellRun]
    }

    /// The part of `cell` between two grid points, in either order. Points outside the cell are
    /// held to it, as a text editor does past its text: beside a line, to that line's edge; above
    /// the cell, to its start; below it, to its end. Nil when that part is only blank space.
    static func selection(
        in grid: TextGrid,
        cell: Cell,
        from anchor: (row: Int, column: Int),
        to focus: (row: Int, column: Int),
    ) -> Selection? {
        let held = { (point: (row: Int, column: Int)) -> (row: Int, column: Int) in
            if point.row < cell.rows.lowerBound {
                return (cell.rows.lowerBound, cell.columns.lowerBound)
            }
            if point.row > cell.rows.upperBound {
                return (cell.rows.upperBound, cell.columns.upperBound - 1)
            }
            return (point.row, min(max(point.column, cell.columns.lowerBound), cell.columns.upperBound - 1))
        }
        var first = held(anchor), last = held(focus)
        if (last.row, last.column) < (first.row, first.column) {
            swap(&first, &last)
        }
        var pieces: [String] = []
        var runs: [CellRun] = []
        for row in first.row ... last.row {
            var start = row == first.row ? first.column : cell.columns.lowerBound
            let end = row == last.row ? last.column : cell.columns.upperBound - 1
            // A point on the second half of a wide character takes the whole character.
            if start > cell.columns.lowerBound, grid.character(row: row, column: start) == nil,
               let before = grid.character(row: row, column: start - 1), CellWidth.of(before) == 2 {
                start -= 1
            }
            guard let run = textRun(in: grid, row: row, columns: start ... end) else { continue }
            runs.append(run)
            pieces.append(grid.text(row: row, from: run.columns.lowerBound, to: run.columns.upperBound))
        }
        return pieces.isEmpty ? nil : Selection(text: join(pieces), runs: runs)
    }

    /// The columns of a line's text within `columns`, without the padding around it.
    private static func textRun(in grid: TextGrid, row: Int, columns: ClosedRange<Int>) -> CellRun? {
        let printed = columns.filter { column in
            grid.character(row: row, column: column).map { !$0.isWhitespace } ?? false
        }
        guard let start = printed.first, let last = printed.last,
              let character = grid.character(row: row, column: last)
        else { return nil }
        return CellRun(row: row, columns: start ..< last + CellWidth.of(character))
    }
}

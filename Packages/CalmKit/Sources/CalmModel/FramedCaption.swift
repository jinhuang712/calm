import Foundation

/// The caption of a framed tile on the screen, found from any cell inside the frame: what lets
/// ⌘ over a picture an agent draws (Calm's mod for Claude Code draws one per pasted image,
/// captioned `[Image #4]`) stand for its caption, whatever the picture's cells hold as text.
///
/// A tile is a box drawn with rounded corners (`╭╮╰╯`, `│`, `─`), as Ink draws a `round`
/// border; its caption is what `expression` matches on its last row inside the frame.
public enum FramedCaption {
    public static func caption(
        at cell: (row: Int, column: Int),
        in grid: TextGrid,
        matching expression: NSRegularExpression,
    ) -> LinkMatch? {
        guard let frame = frame(around: cell, in: grid) else { return nil }
        // At least the pointer's own row: the frame's walk starts there.
        let captionRow = frame.bottom - 1
        let inside = frame.left + 1 ..< frame.right
        let found = LinkMatcher.matches(of: expression, in: grid, rows: captionRow ..< captionRow + 1).filter { match in
            match.runs.allSatisfy { inside.contains($0.columns.lowerBound) && $0.columns.upperBound <= inside.upperBound }
        }
        return found.count == 1 ? found[0] : nil
    }

    private struct Frame {
        let top: Int
        let bottom: Int
        let left: Int
        let right: Int
    }

    /// The frame whose inside holds `cell`: the nearest `│` on each side of it, and the corners
    /// above and below in those columns, every row between them walled on both sides.
    private static func frame(around cell: (row: Int, column: Int), in grid: TextGrid) -> Frame? {
        guard grid.cells.indices.contains(cell.row) else { return nil }
        let row = grid.cells[cell.row]
        guard row.indices.contains(cell.column), !isBorder(row[cell.column]) else { return nil }
        guard let left = (0 ..< cell.column).last(where: { row[$0] == "│" }),
              let right = (cell.column + 1 ..< row.count).first(where: { row[$0] == "│" })
        else { return nil }
        func at(_ row: Int, _ column: Int) -> Character? {
            grid.cells.indices.contains(row) && grid.cells[row].indices.contains(column) ? grid.cells[row][column] : nil
        }
        var top = cell.row - 1
        while top >= 0, at(top, left) == "│", at(top, right) == "│" {
            top -= 1
        }
        var bottom = cell.row + 1
        while bottom < grid.cells.count, at(bottom, left) == "│", at(bottom, right) == "│" {
            bottom += 1
        }
        guard at(top, left) == "╭", at(top, right) == "╮", at(bottom, left) == "╰", at(bottom, right) == "╯" else { return nil }
        return Frame(top: top, bottom: bottom, left: left, right: right)
    }

    private static func isBorder(_ character: Character?) -> Bool {
        guard let character else { return false }
        return "╭╮╰╯│─".contains(character)
    }
}

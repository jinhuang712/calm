import Foundation

/// How many terminal cells a character takes: 2 for East Asian wide and fullwidth characters and
/// emoji, 0 for combining marks, 1 otherwise. An approximation of the terminal's own width
/// tables, good for the text agents draw in tables.
public enum CellWidth {
    public static func of(_ character: Character) -> Int {
        guard let scalar = character.unicodeScalars.first else { return 1 }
        if scalar.properties.generalCategory == .nonspacingMark || scalar.properties.generalCategory == .enclosingMark {
            return 0
        }
        if character.unicodeScalars.contains(where: \.properties.isEmojiPresentation) {
            return 2
        }
        switch scalar.value {
        case 0x1100 ... 0x115F, // Hangul Jamo
             0x2E80 ... 0x303E, // CJK radicals, punctuation
             0x3041 ... 0x33FF, // kana, CJK symbols
             0x3400 ... 0x4DBF, // CJK extension A
             0x4E00 ... 0x9FFF, // CJK unified ideographs
             0xA000 ... 0xA4CF, // Yi
             0xAC00 ... 0xD7A3, // Hangul syllables
             0xF900 ... 0xFAFF, // CJK compatibility ideographs
             0xFE30 ... 0xFE4F, // CJK compatibility forms
             0xFF00 ... 0xFF60, // fullwidth forms
             0xFFE0 ... 0xFFE6,
             0x20000 ... 0x3FFFD: // CJK extensions B and later
            return 2
        default:
            return 1
        }
    }
}

/// The terminal's visible text as cells: `cells[row][column]` is the character starting at that
/// cell, or nil for the second half of a wide character and for blank space.
public struct TextGrid: Equatable, Sendable {
    public private(set) var cells: [[Character?]]

    public init(lines: [String]) {
        cells = lines.map { line in
            var row: [Character?] = []
            for character in line {
                switch CellWidth.of(character) {
                case 0:
                    if let last = row.indices.last, let base = row[last] {
                        row[last] = Character(String(base) + String(character))
                    }
                case 2:
                    row.append(character)
                    row.append(nil)
                default:
                    row.append(character)
                }
            }
            return row
        }
    }

    public func character(row: Int, column: Int) -> Character? {
        guard cells.indices.contains(row), cells[row].indices.contains(column) else { return nil }
        return cells[row][column]
    }

    /// The text of `row` between two columns (exclusive), wide characters once.
    func text(row: Int, from start: Int, to end: Int) -> String {
        guard cells.indices.contains(row), start < end else { return "" }
        let line = cells[row]
        var text = ""
        for column in max(start, 0) ..< min(end, line.count) {
            if let character = line[column] {
                text.append(character)
            } else if column == 0 || line[column - 1] == nil || CellWidth.of(line[column - 1]!) < 2 {
                text.append(" ") // blank space (not the tail of a wide character)
            }
        }
        return text
    }
}

/// Copy Cell (FEATURES.md → F9): the text of one cell of a table drawn with box characters,
/// instead of whole rows. Pure over a text grid, so it's tested with fixtures of real tables.
public enum CopyCell {
    /// Characters that draw a table's vertical lines, including junctions and plain `|`.
    static let verticals: Set<Character> = [
        "│", "┃", "║", "┆", "┇", "┊", "┋", "╎", "╏", "|",
        "├", "┤", "┼", "┝", "┥", "┠", "┨", "╟", "╢", "╞", "╡", "╪", "╫", "╬", "┿", "╂", "╋",
        "┌", "┐", "└", "┘", "┬", "┴", "╭", "╮", "╰", "╯", "╔", "╗", "╚", "╝", "╦", "╩", "╠", "╣", "+",
    ]

    /// Characters of horizontal rules and their junctions.
    static let horizontals: Set<Character> = [
        "─", "━", "═", "┄", "┅", "┈", "┉", "╌", "╍", "-", "=", ":",
        "├", "┤", "┼", "┬", "┴", "┌", "┐", "└", "┘", "╭", "╮", "╰", "╯", "╞", "╡", "╪", "╟", "╢", "╫",
        "╔", "╗", "╚", "╝", "╦", "╩", "╠", "╣", "╬", "┝", "┥", "┿", "┠", "┨", "╂", "╋", "+", "|", "│", "║", "┃",
    ]

    /// The cell's text at `row`/`column`, or nil when the click isn't inside a drawn table
    /// (callers fall back to normal selection).
    public static func text(in grid: TextGrid, row: Int, column: Int) -> String? {
        guard grid.cells.indices.contains(row), !isRule(grid, row: row, from: 0, to: grid.cells[row].count),
              let (left, right) = borders(in: grid, row: row, column: column)
        else { return nil }
        // Up and down to the rules (or the table's end) that close this cell.
        var top = row
        while top > 0, isContent(grid, row: top - 1, left: left, right: right) {
            top -= 1
        }
        var bottom = row
        while bottom < grid.cells.count - 1, isContent(grid, row: bottom + 1, left: left, right: right) {
            bottom += 1
        }
        // With a rule only under the header, each line is a row of its own, except that a line whose
        // first column is empty continues the row above (a wrapped cell).
        if bottom > top, !hasRowRules(grid, row: row, border: left) {
            var start = row
            while start > top, firstCell(grid, row: start).isEmpty {
                start -= 1
            }
            var end = row
            while end < bottom, firstCell(grid, row: end + 1).isEmpty {
                end += 1
            }
            (top, bottom) = (start, end)
        }
        let lines = (top ... bottom)
            .map { grid.text(row: $0, from: left + 1, to: right).trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        return lines.isEmpty ? nil : join(lines)
    }

    /// The nearest vertical lines left and right of the column on its row.
    static func borders(in grid: TextGrid, row: Int, column: Int) -> (Int, Int)? {
        let line = grid.cells[row]
        guard line.indices.contains(column) || column >= 0, !(line.indices.contains(column) && isVertical(line[column])) else {
            return nil
        }
        var left = min(column, line.count) - 1
        while left >= 0, !isVertical(line[left]) {
            left -= 1
        }
        var right = column + 1
        while right < line.count, !isVertical(line[right]) {
            right += 1
        }
        guard left >= 0, right < line.count else { return nil }
        return (left, right)
    }

    /// A row inside the same cell: its borders are at the same columns and it isn't a rule.
    private static func isContent(_ grid: TextGrid, row: Int, left: Int, right: Int) -> Bool {
        isVertical(grid.character(row: row, column: left)) && isVertical(grid.character(row: row, column: right))
            && !isRule(grid, row: row, from: left, to: right + 1)
    }

    /// A horizontal rule between the columns: only rule characters (and at least one dash).
    private static func isRule(_ grid: TextGrid, row: Int, from start: Int, to end: Int) -> Bool {
        let characters = (start ..< end).compactMap { grid.character(row: row, column: $0) }
        let dashes = characters.count { "─━═┄┅┈┉╌╍-=".contains($0) }
        return dashes > 0 && characters.allSatisfy { horizontals.contains($0) || $0 == " " }
    }

    /// Whether the table draws rules between body rows: more rules than its top border, header
    /// rule and bottom border. The table is the run of lines with a line or junction at `border`.
    private static func hasRowRules(_ grid: TextGrid, row: Int, border: Int) -> Bool {
        var first = row
        while first > 0, isVertical(grid.character(row: first - 1, column: border)) {
            first -= 1
        }
        var last = row
        while last < grid.cells.count - 1, isVertical(grid.character(row: last + 1, column: border)) {
            last += 1
        }
        let rules = (first ... last).count { isRule(grid, row: $0, from: 0, to: grid.cells[$0].count) }
        return rules > 3
    }

    /// The text of a line's first column: between its first two vertical lines.
    private static func firstCell(_ grid: TextGrid, row: Int) -> String {
        guard grid.cells.indices.contains(row) else { return "" }
        let line = grid.cells[row]
        guard let start = line.firstIndex(where: isVertical),
              let end = line[(start + 1)...].firstIndex(where: isVertical)
        else { return "" }
        return grid.text(row: row, from: start + 1, to: end).trimmingCharacters(in: .whitespaces)
    }

    private static func isVertical(_ character: Character?) -> Bool {
        character.map { verticals.contains($0) } ?? false
    }

    /// Wrapped lines joined back: with a space, except between two wide (CJK) characters.
    static func join(_ lines: [String]) -> String {
        lines.dropFirst().reduce(lines[0]) { text, line in
            if let last = text.last, let first = line.first, CellWidth.of(last) == 2, CellWidth.of(first) == 2 {
                return text + line
            }
            return text + " " + line
        }
    }
}

import Foundation

/// Find in a session (FEATURES.md → F16): where the words are in the terminal's text, matched
/// as libghostty's search matches them, so the matches Calm marks are the ones the engine counts
/// (DESIGNS.md → Find). The engine compares bytes with only A to Z folded (`indexOfIgnoreCase`),
/// counts a match at every place one starts, overlapping ones too (it looks again one byte past
/// a match's start), and reads a line the terminal wrapped as one.
public enum FindMatcher {
    /// Where `words` start in `text`, as offsets into its UTF-16 code units, oldest first.
    /// Matching code units is the engine's byte matching: both spell the same characters, and
    /// only A to Z fold, which are one unit in either.
    public static func starts(of words: [UInt16], in text: [UInt16]) -> [Int] {
        guard let first = words.first, words.count <= text.count else { return [] }
        let folded = words.map(fold)
        var starts: [Int] = []
        for start in 0 ... text.count - words.count where fold(text[start]) == fold(first) {
            var index = 1
            while index < folded.count, fold(text[start + index]) == folded[index] {
                index += 1
            }
            if index == folded.count {
                starts.append(start)
            }
        }
        return starts
    }

    /// How many times `words` appear in `text`, as the engine counts them.
    public static func count(of words: String, in text: String) -> Int {
        starts(of: Array(words.utf16), in: Array(text.utf16)).count
    }

    /// The matches in one line of the screen (`rows`, which the terminal wrapped from one line, or
    /// a single row), left to right, each as the cells it covers, one run per row.
    public static func matches(of words: String, in grid: TextGrid, rows: Range<Int>) -> [[CellRun]] {
        let needle = Array(words.utf16)
        guard !needle.isEmpty else { return [] }
        var units: [UInt16] = []
        // The cells each code unit belongs to: a wide character's two, a combining mark's base.
        var cells: [CellRun] = []
        for row in rows where grid.cells.indices.contains(row) {
            for (column, character) in grid.cells[row].enumerated() {
                guard let character else { continue } // the second half of a wide character
                let width = max(CellWidth.of(character), 1)
                for unit in String(character).utf16 {
                    units.append(unit)
                    cells.append(CellRun(row: row, columns: column ..< column + width))
                }
            }
        }
        return starts(of: needle, in: units).map { start in
            var runs: [CellRun] = []
            for cell in cells[start ..< start + needle.count] {
                if let last = runs.last, last.row == cell.row {
                    let columns = last.columns.lowerBound ..< max(last.columns.upperBound, cell.columns.upperBound)
                    runs[runs.count - 1] = CellRun(row: cell.row, columns: columns)
                } else {
                    runs.append(cell)
                }
            }
            return runs
        }
    }

    private static func fold(_ unit: UInt16) -> UInt16 {
        (0x41 ... 0x5A).contains(unit) ? unit + 0x20 : unit
    }
}

public extension CellRun {
    /// What's left of these cells once `others` are taken out: none, one or more runs on this row.
    func subtracting(_ others: [CellRun]) -> [CellRun] {
        var pieces = [columns]
        for other in others where other.row == row {
            pieces = pieces.flatMap { piece -> [Range<Int>] in
                guard piece.overlaps(other.columns) else { return [piece] }
                let before = piece.lowerBound ..< max(piece.lowerBound, other.columns.lowerBound)
                let after = min(piece.upperBound, other.columns.upperBound) ..< piece.upperBound
                return [before, after].filter { !$0.isEmpty }
            }
        }
        return pieces.map { CellRun(row: row, columns: $0) }
    }
}

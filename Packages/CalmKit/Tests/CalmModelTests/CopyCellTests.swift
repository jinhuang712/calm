@testable import CalmModel
import Foundation
import Testing

struct CopyCellTests {
    private func grid(_ fixture: String) throws -> TextGrid {
        let url = try #require(Bundle.module.url(forResource: fixture, withExtension: "txt", subdirectory: "Fixtures/copy-cell"))
        return try TextGrid(lines: String(contentsOf: url, encoding: .utf8).components(separatedBy: "\n"))
    }

    /// The cell position of `text` on the first line containing it (plus `offset` cells).
    private func position(of text: String, in grid: TextGrid, offset: Int = 1) throws -> (row: Int, column: Int) {
        for (row, cells) in grid.cells.enumerated() {
            let line = cells.compactMap(\.self).map(String.init).joined()
            guard let range = line.range(of: text) else { continue }
            let column = line[..<range.lowerBound].reduce(0) { $0 + CellWidth.of($1) }
            return (row, column + offset)
        }
        Issue.record("\(text) not found")
        throw CancellationError()
    }

    private func copy(_ text: String, in fixture: String) throws -> String? {
        let grid = try grid(fixture)
        let (row, column) = try position(of: text, in: grid)
        return CopyCell.text(in: grid, row: row, column: column)
    }

    @Test func `claude code tables: one cell, wrapped lines joined`() throws {
        #expect(try copy("Strength", in: "claude-code") == "Strength")
        #expect(try copy("Sessions grouped", in: "claude-code") == "Sessions grouped by project, calm attention")
        // Clicking the wrapped second line gives the same cell.
        #expect(try copy("project, calm", in: "claude-code") == "Sessions grouped by project, calm attention")
        #expect(try copy("Building", in: "claude-code") == "Building")
        #expect(try copy("Warp", in: "claude-code") == "Warp")
    }

    /// Claude Code's full-screen view (`"tui": "fullscreen"`, 2.1.284), 60 columns wide, as its
    /// own bytes drew it: indented two columns, a rule between every row.
    @Test func `claude code full-screen tables`() throws {
        #expect(try copy("Blocks and AI", in: "claude-code-fullscreen") == "Blocks and AI")
        #expect(try copy("Shipped", in: "claude-code-fullscreen") == "Shipped")
        #expect(try copy("calm attention", in: "claude-code-fullscreen") == "Sessions grouped by project, calm attention")
        #expect(try copy("未处理", in: "claude-code-fullscreen") == "未处理的问题需要复核和跟进")
    }

    @Test func `a cell knows the lines and columns it covers`() throws {
        let grid = try grid("claude-code-fullscreen")
        let (row, column) = try position(of: "calm attention", in: grid)
        let cell = try #require(CopyCell.cell(in: grid, row: row, column: column))
        // Both lines of the wrapped cell, and the columns between its two vertical lines.
        #expect(cell.rows == row - 1 ... row)
        let line = String(grid.cells[row].compactMap(\.self))
        let borders = line.indices.filter { line[$0] == "│" }.map { line.distance(from: line.startIndex, to: $0) }
        #expect(cell.columns == borders[1] + 1 ..< borders[2])
        // The same cell from its first line.
        let first = try position(of: "Sessions grouped", in: grid)
        #expect(CopyCell.cell(in: grid, row: first.row, column: first.column) == cell)
    }

    /// An ⌥-drag from the first cell showing `from` to the one showing `to` (plus `offset` cells).
    private func select(
        from: String,
        to: String,
        offset: Int = 0,
        in fixture: String = "claude-code-fullscreen",
    ) throws -> CopyCell.Selection? {
        let grid = try grid(fixture)
        let start = try position(of: from, in: grid, offset: 0)
        let end = try position(of: to, in: grid, offset: offset)
        let cell = try #require(CopyCell.cell(in: grid, row: start.row, column: start.column))
        return CopyCell.selection(in: grid, cell: cell, from: start, to: end)
    }

    @Test func `an option-drag selects inside one cell, across its wrapped lines`() throws {
        // From "grouped" on the first line to the end of "calm" on the second: only this cell's
        // text, although the rows go on through the Status column.
        let wrapped = try #require(try select(from: "grouped", to: "calm attention", offset: 3))
        #expect(wrapped.text == "grouped by project, calm")
        #expect(wrapped.runs.count == 2)
        // Backwards gives the same.
        #expect(try select(from: "calm attention", to: "grouped", offset: 0)?.text == "grouped by project, c")
        // Part of one line.
        #expect(try select(from: "Blocks", to: "and", offset: 2)?.text == "Blocks and")
    }

    @Test func `an option-drag past the cell's lines stays inside it`() throws {
        // Dragged on into the Status column, and below the table: held to the cell's edges.
        #expect(try select(from: "Sessions", to: "Building")?.text == "Sessions grouped by project,")
        #expect(try select(from: "Sessions", to: "Want me")?.text == "Sessions grouped by project, calm attention")
        #expect(try select(from: "Blocks", to: "Shipped")?.text == "Blocks and AI")
    }

    @Test func `an option-drag over chinese takes whole characters`() throws {
        // Starting on the second half of 处 still takes 处.
        let grid = try grid("claude-code-fullscreen")
        let start = try position(of: "处", in: grid, offset: 1) // the character's second cell
        let end = try position(of: "题", in: grid, offset: 0)
        let cell = try #require(CopyCell.cell(in: grid, row: start.row, column: start.column))
        #expect(CopyCell.selection(in: grid, cell: cell, from: start, to: end)?.text == "处理的问题")
    }

    @Test func `chinese cells join without spaces`() throws {
        #expect(try copy("审核记录", in: "claude-code") == "审核记录")
        #expect(try copy("未处理", in: "claude-code") == "未处理的问题需要复核和跟进")
        #expect(try copy("待办", in: "claude-code") == "待办")
    }

    @Test func `header-only tables: each line is a row unless it continues one`() throws {
        #expect(try copy("Teerb", in: "header-only") == "Teerb")
        #expect(try copy("JetBrains", in: "header-only") == "JetBrains Mono")
        #expect(try copy("Soft palettes", in: "header-only") == "Soft palettes only, low contrast and saturation")
        #expect(try copy("contrast and", in: "header-only") == "Soft palettes only, low contrast and saturation")
        #expect(try copy("motion", in: "header-only") == "motion")
    }

    @Test func `markdown pipe tables`() throws {
        #expect(try copy("yes", in: "markdown") == "yes")
        #expect(try copy("~/.codex", in: "markdown") == "~/.codex/sessions")
        #expect(try copy("Agent", in: "markdown") == "Agent")
    }

    @Test func `outside a table there is nothing to copy`() throws {
        let grid = try grid("claude-code")
        let (row, column) = try position(of: "comparison", in: grid)
        #expect(CopyCell.text(in: grid, row: row, column: column) == nil)
        let rule = try position(of: "┼", in: grid, offset: 2)
        #expect(CopyCell.text(in: grid, row: rule.row, column: rule.column) == nil)
        let border = try position(of: "│ Calm", in: grid, offset: 0)
        #expect(CopyCell.text(in: grid, row: border.row, column: border.column) == nil)
        #expect(CopyCell.text(in: grid, row: 999, column: 0) == nil)
    }

    @Test func `cell widths`() {
        #expect(CellWidth.of("a") == 1)
        #expect(CellWidth.of("审") == 2)
        #expect(CellWidth.of("Ｗ") == 2)
        #expect(CellWidth.of("🚀") == 2)
        #expect(CellWidth.of("│") == 1)
        let grid = TextGrid(lines: ["a审b"])
        #expect(grid.cells[0] == ["a", "审", nil, "b"])
    }
}

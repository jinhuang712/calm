@testable import CalmModel
import Testing

struct FindMapTests {
    /// Ten columns wide: the long line fills three rows, the wide characters' line two.
    private let text = "build\nError: one\n" + String(repeating: "x", count: 25) + "error\n日本語日本語 error\n\naaaa\n"

    @Test func `lines with matches, the row each starts on through wraps, and their numbers`() {
        let map = FindMap.scan(text, words: "error", columns: 10)
        #expect(map.lines.map(\.row) == [1, 2, 5])
        #expect(map.lines.map(\.number) == [2, 3, 4])
        #expect(map.lines.map(\.matches) == [1, 1, 1])
        #expect(map.lines.first?.text == "Error: one")
        // build 1, Error 1, the long line 3, the wide one 2 (12 + 6 cells), the empty one 1, aaaa 1.
        #expect(map.rows == 9)
        #expect(map.matches == 3)
    }

    @Test func `overlapping matches count as the engine counts them`() {
        let map = FindMap.scan(text, words: "aa", columns: 10)
        #expect(map.lines.count == 1)
        #expect(map.lines.first?.matches == 3)
        #expect(map.lines.first?.row == 8)
    }

    @Test func `the engine's index, newest first, to a line and back`() {
        let map = FindMap(lines: [
            .init(row: 0, number: 1, matches: 2, text: ""),
            .init(row: 10, number: 11, matches: 1, text: ""),
            .init(row: 20, number: 21, matches: 3, text: ""),
        ], rows: 30)
        #expect(map.matches == 6)
        #expect(map.line(holding: 0) == 2) // the newest match is on the last line
        #expect(map.line(holding: 2) == 2)
        #expect(map.line(holding: 3) == 1)
        #expect(map.line(holding: 5) == 0)
        #expect(map.line(holding: 6) == nil)
        // A click goes to the line's first match: its leftmost, the oldest on it.
        #expect(map.selection(of: 0) == 5)
        #expect(map.selection(of: 1) == 3)
        #expect(map.selection(of: 2) == 2)
    }

    @Test func `lines sharing a slot make one darker tick, and the pointer finds the nearest`() {
        let map = FindMap(lines: [
            .init(row: 0, number: 1, matches: 1, text: ""),
            .init(row: 1, number: 2, matches: 1, text: ""),
            .init(row: 2, number: 3, matches: 1, text: ""),
            .init(row: 500, number: 501, matches: 1, text: ""),
            .init(row: 999, number: 1000, matches: 1, text: ""),
        ], rows: 1000)
        let ticks = map.ticks(height: 100, total: 1000)
        #expect(ticks.map(\.y) == [0, 50, 98])
        #expect(ticks.map(\.lines) == [3, 1, 1])
        #expect(map.line(near: 52, height: 100, total: 1000) == 3)
        #expect(map.line(near: 30, height: 100, total: 1000) == nil)
    }
}

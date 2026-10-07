@testable import CalmModel
import Testing

struct FindMatcherTests {
    @Test func `letters fold from A to Z and nothing else, as the engine compares`() {
        #expect(FindMatcher.count(of: "error", in: "Error: ERROR, error.") == 3)
        // Only ASCII letters fold: É and é are different bytes to the engine.
        #expect(FindMatcher.count(of: "é", in: "É é") == 1)
        #expect(FindMatcher.count(of: "", in: "anything") == 0)
        #expect(FindMatcher.count(of: "longer than the text", in: "short") == 0)
    }

    @Test func `overlapping matches each count, the engine looks again one past a start`() {
        #expect(FindMatcher.count(of: "aa", in: "aaaa") == 3)
        #expect(FindMatcher.starts(of: Array("aba".utf16), in: Array("ababa".utf16)) == [0, 2])
    }

    @Test func `a match's cells, wide characters and a wrapped line`() {
        // Row 0 wraps into row 1: "say 日本語" then "語 again" on the next row.
        let grid = TextGrid(lines: ["say 日本", "語 again 日本語"])
        let matches = FindMatcher.matches(of: "日本語", in: grid, rows: 0 ..< 2)
        #expect(matches == [
            [CellRun(row: 0, columns: 4 ..< 8), CellRun(row: 1, columns: 0 ..< 2)],
            [CellRun(row: 1, columns: 9 ..< 15)],
        ])
        #expect(FindMatcher.matches(of: "AGAIN", in: grid, rows: 1 ..< 2) == [[CellRun(row: 1, columns: 3 ..< 8)]])
    }

    @Test func `cells with a link's dots taken out where find marks them`() {
        let link = CellRun(row: 2, columns: 0 ..< 20)
        #expect(link.subtracting([CellRun(row: 2, columns: 4 ..< 11)]) == [
            CellRun(row: 2, columns: 0 ..< 4), CellRun(row: 2, columns: 11 ..< 20),
        ])
        #expect(link.subtracting([CellRun(row: 3, columns: 4 ..< 11)]) == [link])
        #expect(link.subtracting([CellRun(row: 2, columns: 0 ..< 30)]).isEmpty)
    }
}

@testable import CalmModel
import Testing

struct FindQueryTests {
    @Test func `plain words match as the engine does, overlaps and all`() throws {
        let plain = try #require(FindQuery(words: "aa", isPattern: false))
        #expect(plain.ranges(in: "aaaa") == [0 ..< 2, 1 ..< 3, 2 ..< 4])
        #expect(FindQuery(words: "", isPattern: false) == nil)
    }

    @Test func `a pattern finds every kind of match, case aside unless it says otherwise`() throws {
        let pattern = try #require(FindQuery(words: #"(error|warn)\w*"#, isPattern: true))
        #expect(pattern.ranges(in: "warnings treated as Errors") == [0 ..< 8, 20 ..< 26])
        let strict = try #require(FindQuery(words: "(?-i)Error", isPattern: true))
        #expect(strict.ranges(in: "error Error ERROR") == [6 ..< 11])
    }

    @Test func `a pattern half typed isn't one, and a match of nothing isn't counted`() throws {
        #expect(FindQuery(words: "warn(", isPattern: true) == nil)
        // As plain words it is just text.
        #expect(FindQuery(words: "warn(", isPattern: false) != nil)
        let stars = try #require(FindQuery(words: "a*", isPattern: true))
        #expect(stars.ranges(in: "baa b") == [1 ..< 3])
    }

    @Test func `a pattern counts line by line and never across a line's end`() throws {
        let pattern = try #require(FindQuery(words: "end.start", isPattern: true))
        #expect(pattern.count(in: "the end\nstart here") == 0)
        let words = try #require(FindQuery(words: #"\d+ms"#, isPattern: true))
        #expect(words.count(in: "took 12ms\nthen 340ms and 7ms\n") == 3)
    }

    @Test func `a pattern's cells, through a wrapped line and wide characters`() throws {
        let grid = TextGrid(lines: ["日本 err", "or 1 error2"])
        let pattern = try #require(FindQuery(words: #"error\d?"#, isPattern: true))
        #expect(FindMatcher.matches(of: pattern, in: grid, rows: 0 ..< 2) == [
            [CellRun(row: 0, columns: 5 ..< 8), CellRun(row: 1, columns: 0 ..< 2)],
            [CellRun(row: 1, columns: 5 ..< 11)],
        ])
    }

    @Test func `the map takes a pattern too`() throws {
        let pattern = try #require(FindQuery(words: #"warn\w*"#, isPattern: true))
        let map = FindMap.scan("ok\nwarning: one\nok\nWARN and warned\n", query: pattern, columns: 80)
        #expect(map.lines.map(\.number) == [2, 4])
        #expect(map.matches == 3)
    }
}

extension FindQuery: Equatable {
    public static func == (lhs: FindQuery, rhs: FindQuery) -> Bool {
        lhs.words == rhs.words && lhs.isPattern == rhs.isPattern
    }
}

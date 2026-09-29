@testable import CalmModel
import Testing

struct HardWrapTests {
    private let columns = 40

    /// What a full-screen program draws for `text` at `width` columns: a word longer than a row is
    /// cut where the row ends, and the rest goes on in the next row after `indent`.
    private func cut(_ text: String, width: Int, indent: Int) -> [String] {
        var rows = [String(text.prefix(width))]
        var rest = text.dropFirst(width)
        while !rest.isEmpty {
            rows.append(String(repeating: " ", count: indent) + rest.prefix(width - indent))
            rest = rest.dropFirst(width - indent)
        }
        return rows
    }

    private func oneLineEach(_ rows: [String]) -> [Range<Int>] {
        rows.indices.map { $0 ..< $0 + 1 }
    }

    private func links(_ rows: [String], columns: Int? = nil) -> [String] {
        let grid = TextGrid(lines: rows)
        return HardWrap.joined(grid, lines: oneLineEach(rows), columns: columns ?? self.columns).flatMap { joined in
            LinkMatcher.matches(in: grid, rows: joined.rows, continuations: joined.continuations)
                .filter(joined.crosses)
                .map(\.text)
        }
    }

    @Test func `reads a path the program cut across two rows as one`() {
        let rows = cut("● Wrote /Users/dev/projects/calm/notes/plan.md ok", width: 40, indent: 2)
        #expect(rows.count == 2)
        #expect(links(rows).first?.hasPrefix("/Users/dev/projects/calm/notes/plan.md") == true)
    }

    @Test func `reads a url over three rows`() {
        let url = "https://example.com/a/very/long/path/that/goes/on/and/on/for/a/while/until/it/ends.html"
        let rows = cut(url, width: 40, indent: 2)
        #expect(rows.count == 3)
        #expect(links(rows) == [url])
    }

    @Test func `puts each piece of a cut link on its own row`() {
        let rows = cut("See https://example.com/a/very/long/path/that/goes/on.html", width: 40, indent: 4)
        let grid = TextGrid(lines: rows)
        let joined = HardWrap.joined(grid, lines: oneLineEach(rows), columns: columns)
        let match = joined.flatMap { LinkMatcher.matches(in: grid, rows: $0.rows, continuations: $0.continuations) }.first
        // The indent isn't part of the link: its second piece starts where the text does.
        #expect(match?.runs.map(\.row) == [0, 1])
        #expect(match?.runs.last?.columns.lowerBound == 4)
    }

    @Test func `accepts a row that ends a column or two short of the edge`() {
        let rows = ["xxxxx /Users/dev/projects/calm/notes/", "  plan.md"]
        // 40 columns: the first row is 37 wide, inside the slack.
        #expect(links(rows) == ["/Users/dev/projects/calm/notes/plan.md"])
    }

    @Test func `leaves a row that stops well before the edge alone`() {
        let rows = ["Wrote /Users/dev/notes/pla", "  n.md and more"]
        #expect(HardWrap.joined(TextGrid(lines: rows), lines: oneLineEach(rows), columns: columns).isEmpty)
    }

    @Test func `leaves text set far in on the next row alone`() {
        let rows = [String(repeating: "y", count: 40), String(repeating: " ", count: 30) + "z"]
        #expect(HardWrap.joined(TextGrid(lines: rows), lines: oneLineEach(rows), columns: columns).isEmpty)
    }

    @Test func `leaves a row that ends the screen or is followed by a blank row alone`() {
        let full = String(repeating: "y", count: 40)
        #expect(HardWrap.joined(TextGrid(lines: [full]), lines: [0 ..< 1], columns: columns).isEmpty)
        #expect(HardWrap.joined(TextGrid(lines: [full, ""]), lines: [0 ..< 1, 1 ..< 2], columns: columns).isEmpty)
    }

    @Test func `does not count a link inside one row as cut`() {
        let rows = cut("see /tmp/one.txt and then a long tail of words after that", width: 40, indent: 2)
        #expect(links(rows).isEmpty)
    }

    @Test func `joins lines the terminal wrapped with lines the program cut`() {
        // Rows 0 and 1 are one line the terminal wrapped; row 2 carries it on after a cut.
        let rows = [
            "abc " + String(repeating: "p", count: 36),
            String(repeating: "q", count: 40),
            "  rest",
        ]
        let lines = [0 ..< 2, 2 ..< 3]
        let joined = HardWrap.joined(TextGrid(lines: rows), lines: lines, columns: columns)
        #expect(joined == [HardWrap.Joined(rows: 0 ..< 3, continuations: [2])])
    }

    @Test func `counts a wide character's two cells at the edge`() {
        let rows = [String(repeating: "a", count: 38) + "文", "  rest"]
        #expect(HardWrap.joined(TextGrid(lines: rows), lines: oneLineEach(rows), columns: columns).count == 1)
    }
}

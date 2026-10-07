@testable import CalmModel
import Foundation
import Testing

struct LinkMatcherTests {
    private func first(_ line: String) -> String? {
        LinkMatcher.links(in: line).first
    }

    /// Cases from Ghostty's own tests for the pattern (src/config/url.zig, MIT; see NOTICE), so the
    /// ICU version keeps matching what libghostty's ⌘-click matches.
    @Test func `matches what ghostty matches`() {
        let cases: [(String, String)] = [
            ("hello https://example.com world", "https://example.com"),
            ("https://example.com/foo(bar) more", "https://example.com/foo(bar)"),
            ("Link inside (https://example.com) parens", "https://example.com"),
            ("Link period https://example.com. More text.", "https://example.com"),
            ("Link trailing comma https://example.com, more text.", "https://example.com"),
            ("match with query url https://example.com?query=1&other=2 and more text.", "https://example.com?query=1&other=2"),
            (
                "url with dashes [mode 2027](https://github.com/contour-terminal/terminal-unicode-core) for better unicode support",
                "https://github.com/contour-terminal/terminal-unicode-core",
            ),
            ("square brackets https://example.com/[foo] and more", "https://example.com/[foo]"),
            ("match tel:+18005551234 tel links", "tel:+18005551234"),
            ("Serving HTTP on :: port 8000 (http://[::]:8000/)", "http://[::]:8000/"),
            ("IPv6 address https://[2001:db8::1]:8080/path", "https://[2001:db8::1]:8080/path"),
            ("/tmp/test.txt http://www.google.com", "/tmp/test.txt"),
            ("/Users/ghostty.user/code/../example.py hello world", "/Users/ghostty.user/code/../example.py"),
            ("first time ../example.py contributor ", "../example.py"),
            ("[link](/home/user/ghostty.user/example)", "/home/user/ghostty.user/example"),
            ("./spaces-end.   ", "./spaces-end."),
            ("../test folder/file.txt", "../test folder/file.txt"),
            ("/tmp/test  folder/file.txt", "/tmp/test"),
            ("diff --git a/src/font/shaper/harfbuzz.zig b/src/font/shaper/harfbuzz.zig", "a/src/font/shaper/harfbuzz.zig"),
            ("/tmp/foo /tmp/bar", "/tmp/foo"),
            ("app/folder/file.rb:1", "app/folder/file.rb:1"),
            ("modified:   src/config/url.zig", "src/config/url.zig"),
            ("lib/ghostty/terminal.zig:42:10", "lib/ghostty/terminal.zig:42:10"),
            ("src/foo.c,baz.txt", "src/foo.c"),
            ("open ~/Documents/notes.md please", "~/Documents/notes.md"),
            ("directory: ~/src/ghostty-org/ghostty", "~/src/ghostty-org/ghostty"),
            ("project dir: $PWD/src/ghostty/main.zig", "$PWD/src/ghostty/main.zig"),
            ("foo/$BAR/baz", "foo/$BAR/baz"),
            ("loaded from .local/share/ghostty/state.db now", ".local/share/ghostty/state.db"),
            ("  - shared/src/foo/SomeItem.m:12, shared/src/", "shared/src/foo/SomeItem.m:12"),
            ("2024/report.txt", "2024/report.txt"),
            ("/tmp/foo bar,baz", "/tmp/foo bar"),
            ("./.config/ghostty: Needs upstream (main)", "./.config/ghostty"),
        ]
        for (line, expected) in cases {
            #expect(first(line) == expected, "\(line)")
        }
    }

    @Test func `leaves alone what ghostty leaves alone`() {
        for line in [
            "input/output",
            "foo/bar",
            "$10/bar",
            "$10/bar.txt",
            "foo/bar,baz.txt",
            "foo$BAR/baz.txt",
            "foo~/bar.txt",
            "// foo bar",
            "//foo",
        ] {
            #expect(LinkMatcher.links(in: line).isEmpty, "\(line)")
        }
    }

    @Test func `every link in a line, left to right`() {
        #expect(LinkMatcher.links(in: "zmx (https://zmx.sh, https://github.com/neurosnap/zmx), MIT License.")
            == ["https://zmx.sh", "https://github.com/neurosnap/zmx"])
    }

    /// Real screen text: a Claude Code edit, git status, grep and git log output (and one line with
    /// wide characters).
    @Test func `finds the links on an agent's screen with their cells`() throws {
        let url = try #require(Bundle.module.url(forResource: "agent-screen", withExtension: "txt", subdirectory: "Fixtures/links"))
        let grid = try TextGrid(lines: String(contentsOf: url, encoding: .utf8).components(separatedBy: "\n"))
        let matches = grid.cells.indices.flatMap { LinkMatcher.matches(in: grid, row: $0) }
        let spec = "plugins/billing/workbench/packages/desktop/e2e/workbench.spec.ts"
        #expect(matches.map(\.text) == [
            spec, spec,
            "Packages/CalmKit/Sources/CalmModel/Link.swift",
            "Calm/Window/MainWindowController+Reading.swift:36",
            "Calm/Terminal/SurfaceEdgeColor.swift",
            "https://github.com/ghostty-org/ghostty",
            "https://zmx.sh", "https://github.com/neurosnap/zmx",
            "文档/说明.md", "https://example.com/说明",
        ])
        // "● Update(" is 9 cells; "  ⎿  Updated " is 13.
        #expect(matches[0].runs == [CellRun(row: 0, columns: 9 ..< 9 + spec.count)])
        #expect(matches[1].runs == [CellRun(row: 1, columns: 13 ..< 13 + spec.count)])
        // Chinese characters take two cells each.
        #expect(matches[8].runs == [CellRun(row: 12, columns: 9 ..< 21)])
        #expect(matches[9].runs == [CellRun(row: 12, columns: 28 ..< 52)])
    }

    @Test func `an agent's image tag is found by its own pattern, cells and all`() throws {
        let tag = try NSRegularExpression(pattern: #"\[Image #(\d+)\]"#)
        // The prompt as Claude Code draws it after two pastes (seen in Calm, 2026-10-06).
        let prompt = TextGrid(lines: ["❯ [Image #4] [Image #5] looks like this"])
        let found = LinkMatcher.matches(of: tag, in: prompt, rows: 0 ..< 1)
        #expect(found.map(\.text) == ["[Image #4]", "[Image #5]"])
        #expect(found.map(\.runs) == [[CellRun(row: 0, columns: 2 ..< 12)], [CellRun(row: 0, columns: 13 ..< 23)]])
        // Wide characters before it move its cells, not its text.
        let wide = LinkMatcher.matches(of: tag, in: TextGrid(lines: ["看这个 [Image #1]"]), rows: 0 ..< 1)
        #expect(wide.first?.runs == [CellRun(row: 0, columns: 7 ..< 17)])
        // A tag the terminal wrapped is one tag on two rows.
        let wrapped = LinkMatcher.matches(of: tag, in: TextGrid(lines: ["see [Ima", "ge #12] now"]), rows: 0 ..< 2)
        #expect(wrapped.map(\.text) == ["[Image #12]"])
        #expect(wrapped.first?.runs == [CellRun(row: 0, columns: 4 ..< 8), CellRun(row: 1, columns: 0 ..< 7)])
        // Links don't count as tags, nor tags as links.
        #expect(LinkMatcher.matches(of: tag, in: TextGrid(lines: ["see ./Image.png"]), rows: 0 ..< 1).isEmpty)
        #expect(LinkMatcher.matches(in: prompt, row: 0).isEmpty)
    }

    @Test func `a link the terminal wrapped onto the next row is one link on two rows`() {
        let grid = TextGrid(lines: ["see Packages/CalmKit/Sou", "rces/Marks/spinner.png ok"])
        let matches = LinkMatcher.matches(in: grid, rows: 0 ..< 2)
        #expect(matches.map(\.text) == ["Packages/CalmKit/Sources/Marks/spinner.png"])
        #expect(matches.first?.runs == [CellRun(row: 0, columns: 4 ..< 24), CellRun(row: 1, columns: 0 ..< 22)])
        #expect(matches.first?.covers(row: 1, column: 3) == true)
        #expect(matches.first?.covers(row: 1, column: 23) == false)
    }

    @Test func `a match cut to a prefix keeps its start`() throws {
        let grid = TextGrid(lines: ["   ~/dev/文档 and then"])
        let match = try #require(LinkMatcher.matches(in: grid, row: 0).first)
        #expect(match.text == "~/dev/文档 and then")
        let cut = match.prefix(8)
        #expect(cut.text == "~/dev/文档")
        #expect(cut.runs == [CellRun(row: 0, columns: 3 ..< 13)])
    }
}

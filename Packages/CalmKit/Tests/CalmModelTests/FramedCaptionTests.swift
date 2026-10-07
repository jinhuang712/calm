@testable import CalmModel
import Foundation
import Testing

struct FramedCaptionTests {
    private let tag: NSRegularExpression

    init() throws {
        tag = try NSRegularExpression(pattern: #"\[Image #(\d+)\]"#)
    }

    /// A cell of a picture in the kitty graphics protocol's Unicode placeholders: U+10EEEE with
    /// diacritics for its row and column, one cell wide.
    private let pixel = "\u{10EEEE}\u{0305}\u{0305}"

    /// Two tiles as Calm's mod draws them with Ink's round border: a wide picture, and one as
    /// narrow as its caption. Laid out by hand, not captured from a screen.
    private var screen: [String] {
        let wide = String(repeating: pixel, count: 16)
        let narrow = "   " + String(repeating: pixel, count: 4) + "   "
        return [
            "╭────────────────╮ ╭──────────╮",
            "│\(wide)│ │\(narrow)│",
            "│\(wide)│ │\(narrow)│",
            "│   [Image #1]   │ │[Image #2]│",
            "╰────────────────╯ ╰──────────╯",
            "❯ [Image #1] [Image #2] which one?",
        ]
    }

    @Test func `a cell of a picture stands for its tile's caption`() throws {
        let grid = TextGrid(lines: screen)
        let first = try #require(FramedCaption.caption(at: (row: 1, column: 5), in: grid, matching: tag))
        #expect(first.text == "[Image #1]")
        #expect(first.runs == [CellRun(row: 3, columns: 4 ..< 14)])
        let second = try #require(FramedCaption.caption(at: (row: 2, column: 23), in: grid, matching: tag))
        #expect(second.text == "[Image #2]")
        // The caption row itself, and blank cells beside a narrow picture.
        #expect(FramedCaption.caption(at: (row: 3, column: 2), in: grid, matching: tag)?.text == "[Image #1]")
        #expect(FramedCaption.caption(at: (row: 1, column: 20), in: grid, matching: tag)?.text == "[Image #2]")
    }

    @Test func `nothing on the frame, between tiles, or outside any frame`() {
        let grid = TextGrid(lines: screen)
        #expect(FramedCaption.caption(at: (row: 1, column: 0), in: grid, matching: tag) == nil) // │
        #expect(FramedCaption.caption(at: (row: 0, column: 5), in: grid, matching: tag) == nil) // ─
        #expect(FramedCaption.caption(at: (row: 2, column: 18), in: grid, matching: tag) == nil) // the gap
        #expect(FramedCaption.caption(at: (row: 5, column: 4), in: grid, matching: tag) == nil) // the prompt
    }

    @Test func `a box that isn't closed, or holds two captions, gives nothing`() {
        let open = TextGrid(lines: ["╭──────────╮", "│  picture │", "│[Image #1]│"])
        #expect(FramedCaption.caption(at: (row: 1, column: 3), in: open, matching: tag) == nil)
        let two = TextGrid(lines: [
            "╭─────────────────────╮",
            "│       picture       │",
            "│[Image #1] [Image #2]│",
            "╰─────────────────────╯",
        ])
        #expect(FramedCaption.caption(at: (row: 1, column: 3), in: two, matching: tag) == nil)
    }
}

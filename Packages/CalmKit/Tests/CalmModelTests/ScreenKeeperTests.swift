@testable import CalmModel
import Foundation
import Testing

struct ScreenKeeperTests {
    private static let words = ["alpha", "bravo", "charlie", "delta", "echo", "foxtrot", "golf", "hotel", "india", "juliet", "kilo"]

    /// Line `number` of an answer. A word each, not only a number: rows that differ only in
    /// digits count as changed in place.
    private func line(_ number: Int) -> String {
        "line \(number) \(Self.words[number % Self.words.count]) of the answer"
    }

    private func text(_ numbers: Range<Int>) -> [String] {
        numbers.map(line)
    }

    /// A full-screen program's view of a long answer, as an agent shows a conversation: a title
    /// row, a scrolling region of `height` rows from line `first`, then a blank row, the prompt
    /// and a status row.
    private func view(_ first: Int, height: Int = 10, status: String = "esc to interrupt") -> [String] {
        ["Agent v2"] + text(first ..< first + height) + ["", "> ", status]
    }

    private func time(_ seconds: Int) -> Date {
        Date(timeIntervalSince1970: TimeInterval(1_800_000_000 + seconds))
    }

    @Test func `lines that scroll off the top are kept in order, the title and prompt never`() {
        var keeper = ScreenKeeper()
        keeper.see(view(0), columns: 80, at: time(0))
        keeper.see(view(1), columns: 80, at: time(1))
        keeper.see(view(4), columns: 80, at: time(2))
        keeper.see(view(6), columns: 80, at: time(3))
        #expect(keeper.lines.map(\.text) == text(0 ..< 6))
        #expect(keeper.lines.map(\.startsPart) == [true, false, false, false, false, false])
    }

    @Test func `each line keeps when it was first on screen`() {
        var keeper = ScreenKeeper()
        keeper.see(view(0), columns: 80, at: time(0))
        keeper.see(view(3), columns: 80, at: time(10)) // 10 to 12 come in
        keeper.see(view(12), columns: 80, at: time(20)) // a jump: the view that went is kept
        #expect(keeper.lines.map(\.text) == text(0 ..< 13))
        #expect(keeper.lines.map(\.shown) == Array(repeating: time(0), count: 10) + Array(repeating: time(10), count: 3))
    }

    @Test func `scrolling back and forth keeps each line once`() {
        var keeper = ScreenKeeper()
        keeper.see(view(0), columns: 80, at: time(0))
        keeper.see(view(5), columns: 80, at: time(1))
        keeper.see(view(2), columns: 80, at: time(2)) // back three
        keeper.see(view(4), columns: 80, at: time(3)) // forward two: kept already
        keeper.see(view(8), columns: 80, at: time(4)) // on past where it was
        #expect(keeper.lines.map(\.text) == text(0 ..< 8))
    }

    @Test func `a spinner, a timer and a status bar changing in place keep nothing`() {
        var keeper = ScreenKeeper()
        keeper.see(view(0, status: "✻ Working… (1s)"), columns: 80, at: time(0))
        keeper.see(view(0, status: "✽ Working… (2s)"), columns: 80, at: time(1))
        keeper.see(view(0, status: "✻ Working… (13s)"), columns: 80, at: time(2))
        keeper.see(view(0, status: "esc to interrupt"), columns: 80, at: time(3))
        #expect(keeper.isEmpty)
    }

    @Test func `a replaced view keeps the view that went, without the rows that stayed`() {
        var keeper = ScreenKeeper()
        keeper.see(view(0), columns: 80, at: time(0))
        let help = ["Agent v2"] + (0 ..< 10).map { "/\(Self.words[$0])  does \(Self.words[$0])" } + ["", "> ", "esc to interrupt"]
        keeper.see(help, columns: 80, at: time(5))
        #expect(keeper.lines.map(\.text) == text(0 ..< 10))
        // Back to the answer: the help went, and starts a part of its own.
        keeper.see(view(0), columns: 80, at: time(9))
        #expect(keeper.lines.count == 20)
        #expect(keeper.lines[10].text == "/alpha  does alpha")
        #expect(keeper.lines[10].startsPart)
        #expect(keeper.lines[10].shown == time(5))
    }

    @Test func `a flick back further than the view keeps nothing it kept already`() {
        var keeper = ScreenKeeper()
        keeper.see(view(0), columns: 80, at: time(0))
        for first in 1 ... 30 {
            keeper.see(view(first), columns: 80, at: time(first))
        }
        #expect(keeper.lines.map(\.text) == text(0 ..< 30))
        // Twenty back at once: the view that went (30 to 39) was never kept, so now it is.
        keeper.see(view(10), columns: 80, at: time(40))
        #expect(keeper.lines.map(\.text) == text(0 ..< 40))
        // To the end again, and on: nothing twice.
        keeper.see(view(30), columns: 80, at: time(41))
        keeper.see(view(32), columns: 80, at: time(42))
        keeper.see(view(35), columns: 80, at: time(43))
        #expect(keeper.lines.map(\.text) == text(0 ..< 40))
        keeper.see(view(45), columns: 80, at: time(44))
        #expect(keeper.lines.map(\.text) == text(0 ..< 45))
    }

    @Test func `a jump further than the view keeps the view that went and starts a part`() {
        var keeper = ScreenKeeper()
        keeper.see(view(0), columns: 80, at: time(0))
        keeper.see(view(2), columns: 80, at: time(1))
        keeper.see(view(40), columns: 80, at: time(2)) // 12 to 39 came and went between reads
        keeper.see(view(42), columns: 80, at: time(3))
        #expect(keeper.lines.map(\.text) == text(0 ..< 12) + text(40 ..< 42))
        #expect(keeper.lines[12].startsPart)
        #expect(!keeper.lines[2].startsPart)
    }

    @Test func `a new size keeps nothing: the program draws its view again`() {
        var keeper = ScreenKeeper()
        keeper.see(view(0), columns: 80, at: time(0))
        keeper.see(view(0, height: 13), columns: 80, at: time(1))
        keeper.see(view(0, height: 13).map { String($0.prefix(12)) }, columns: 12, at: time(2))
        #expect(keeper.isEmpty)
    }

    @Test func `when the program leaves its screen, its last view is kept`() {
        var keeper = ScreenKeeper()
        keeper.see(view(0), columns: 80, at: time(0))
        keeper.see(view(3), columns: 80, at: time(1))
        keeper.finish()
        #expect(keeper.lines.map(\.text) == text(0 ..< 3) + ["Agent v2"] + text(3 ..< 13) + ["", ">", "esc to interrupt"])
        // The next program's lines start a part.
        keeper.see(["vim", "first", "second", "third"], columns: 80, at: time(5))
        keeper.finish()
        #expect(keeper.lines.suffix(4).map(\.text) == ["vim", "first", "second", "third"])
        #expect(keeper.lines[keeper.lines.count - 4].startsPart)
    }

    @Test func `a view redrawn row by row in place, as pi draws, counts as a scroll`() {
        var keeper = ScreenKeeper()
        // pi rewrites every row of its region with the content moved: only the text tells.
        keeper.see(view(0), columns: 80, at: time(0))
        keeper.see(view(4), columns: 80, at: time(1))
        #expect(keeper.lines.map(\.text) == text(0 ..< 4))
    }

    @Test func `blank lines between kept lines stay, at a part's ends they don't`() {
        var keeper = ScreenKeeper()
        keeper.see(["title", "", "one", "", "two", "", "three", "", "> "], columns: 80, at: time(0))
        keeper.see(["title", "a", "b", "c", "d", "e", "f", "g", "> "], columns: 80, at: time(1))
        #expect(keeper.lines.map(\.text) == ["one", "", "two", "", "three"])
    }

    @Test func `over the limit the oldest lines go`() {
        var keeper = ScreenKeeper(limit: 100)
        keeper.see(view(0), columns: 80, at: time(0))
        for first in stride(from: 3, through: 300, by: 3) {
            keeper.see(view(first), columns: 80, at: time(first))
        }
        #expect(keeper.lines.count <= 110)
        #expect(keeper.lines.last?.text == line(299))
        #expect(keeper.dropped + keeper.lines.count == 300)
        // It still knows where the view is after dropping: back and forth keeps nothing twice.
        keeper.see(view(297), columns: 80, at: time(400))
        keeper.see(view(303), columns: 80, at: time(401))
        #expect(keeper.lines.last?.text == line(302))
        #expect(keeper.dropped + keeper.lines.count == 303)
    }

    @Test func `a row that changed but for its digits changed in place`() {
        #expect(ScreenKeeper.sameButDigits("✻ Working… (12s · ↓ 1.2k tokens)", "✻ Working… (13s · ↓ 1.4k tokens)"))
        #expect(!ScreenKeeper.sameButDigits("line 4 echo of the answer", "/alpha  does alpha"))
        #expect(ScreenKeeper.trimmed("text   ") == "text")
    }
}

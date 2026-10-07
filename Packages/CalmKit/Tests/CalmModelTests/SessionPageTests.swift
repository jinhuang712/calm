@testable import CalmModel
import Foundation
import Testing

struct SessionPageTests {
    private func time(_ seconds: Int) -> Date {
        Date(timeIntervalSince1970: TimeInterval(1_800_000_000 + seconds))
    }

    /// A program's screen: a title, `rows` of its answer, a prompt.
    private func view(_ rows: [String]) -> [String] {
        ["Agent"] + rows + ["", "> "]
    }

    @Test func `the shell's output, then what the program showed, then its screen now`() {
        let words = ["alpha", "bravo", "charlie", "delta", "echo", "foxtrot", "golf", "hotel"]
        var keeper = ScreenKeeper()
        // The shell had three lines, its command the last, when the program took the screen.
        keeper.startProgram(shellLines: 3)
        keeper.see(view(Array(words[0 ..< 6])), columns: 80, at: time(0))
        keeper.see(view(Array(words[2 ..< 8])), columns: 80, at: time(5)) // alpha and bravo scrolled off
        let page = SessionPage(shell: "$ ls\nfile.txt\n$ agent\n\n\n", keeper: keeper, running: true)
        #expect(page.lines.map(\.text) == ["$ ls", "file.txt", "$ agent", "alpha", "bravo", "Agent"] + words[2 ..< 8] + ["", ">"])
        #expect(page.lines[3].mark == time(0))
        #expect(page.lines.count(where: { $0.mark != nil }) == 1)
        #expect(page.screenCount == 9)
        #expect(page.moreCount == 5)
        #expect(page.since == time(0))
    }

    @Test func `a screen that went back to lines kept already isn't on the page twice`() {
        let words = ["alpha", "bravo", "charlie", "delta", "echo", "foxtrot", "golf", "hotel"]
        var keeper = ScreenKeeper()
        keeper.startProgram(shellLines: 0)
        keeper.see(Array(words[0 ..< 4]), columns: 80, at: time(0))
        keeper.see(Array(words[4 ..< 8]), columns: 80, at: time(1)) // a jump: alpha to delta kept
        keeper.see(Array(words[0 ..< 4]), columns: 80, at: time(2)) // and back: echo to hotel kept
        let page = SessionPage(shell: nil, keeper: keeper, running: true)
        #expect(page.lines.map(\.text) == words)
        #expect(page.screenCount == 0)
    }

    @Test func `after the program quits, the shell's output since comes after what it showed`() {
        var keeper = ScreenKeeper()
        keeper.startProgram(shellLines: 1)
        keeper.see(["one", "two", "three", "four"], columns: 80, at: time(0))
        keeper.finish()
        let page = SessionPage(shell: "$ prog\n$ echo done\ndone\n$ ", keeper: keeper, running: false)
        #expect(page.lines.map(\.text) == ["$ prog", "one", "two", "three", "four", "$ echo done", "done", "$"])
        #expect(page.lines[1].mark == time(0))
        #expect(page.screenCount == 0)
    }

    @Test func `two programs each sit where they started in the shell's output`() {
        var keeper = ScreenKeeper()
        keeper.startProgram(shellLines: 1)
        keeper.see(["first program", "its line"], columns: 80, at: time(0))
        keeper.finish()
        keeper.startProgram(shellLines: 3)
        keeper.see(["second program", "its own line"], columns: 80, at: time(60))
        keeper.finish()
        let page = SessionPage(shell: "$ a\n$ b\nbetween\n$ ", keeper: keeper, running: false)
        #expect(page.lines.map(\.text) == [
            "$ a", "first program", "its line", "$ b", "between", "second program", "its own line", "$",
        ])
        #expect(page.lines.compactMap(\.mark) == [time(0), time(60)])
    }

    @Test func `kept lines with no start known go after the shell's output`() {
        var keeper = ScreenKeeper()
        keeper.see(["one", "two", "three"], columns: 80, at: time(0))
        keeper.finish()
        let page = SessionPage(shell: "$ x", keeper: keeper, running: false)
        #expect(page.lines.map(\.text) == ["$ x", "one", "two", "three"])
    }

    @Test func `no shell text: only what the program showed`() {
        var keeper = ScreenKeeper()
        keeper.startProgram(shellLines: 0)
        keeper.see(["only", "this"], columns: 80, at: time(0))
        let page = SessionPage(shell: nil, keeper: keeper, running: true)
        #expect(page.lines.map(\.text) == ["only", "this"])
        #expect(page.moreCount == 0)
    }

    @Test func `the shell's lines lose trailing spaces and the blank rows at the end`() {
        #expect(SessionPage.shellLines("a  \n\nb\n  \n\n") == ["a", "", "b"])
        #expect(SessionPage.shellLines("") == [])
    }
}

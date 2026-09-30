@testable import Calm
import Testing

struct CommandMatcherTests {
    let commands = [
        PaletteCommand(id: "split-right", title: "Split Right", detail: "Split the terminal to the right.") {},
        PaletteCommand(id: "split-down", title: "Split Down", detail: "Split the terminal down.") {},
        PaletteCommand(id: "clear", title: "Clear Screen", detail: "Clear the screen and scrollback.") {},
        PaletteCommand(id: "tab", title: "New Tab", detail: "Open a new tab.") {},
    ]

    @Test func `an empty query keeps every command in order`() {
        #expect(CommandMatcher.filter(commands, query: "  ").map(\.id) == commands.map(\.id))
    }

    @Test func `substring matches rank by position`() {
        let titles = CommandMatcher.filter(commands, query: "split").map(\.title)
        #expect(titles == ["Split Right", "Split Down"])
    }

    @Test func `letters in order match across words`() {
        let titles = CommandMatcher.filter(commands, query: "clsc").map(\.title)
        #expect(titles == ["Clear Screen"])
    }

    @Test func `title matches beat description matches`() {
        let titles = CommandMatcher.filter(commands, query: "scroll").map(\.title)
        #expect(titles == ["Clear Screen"])
        let tab = CommandMatcher.filter(commands, query: "tab").map(\.title)
        #expect(tab.first == "New Tab")
    }

    /// "split" is a scattered subsequence of this sentence (s-p-l-i-t across "mouse … reported …
    /// terminal applications"), and used to put the row on screen.
    @Test func `scattered letters don't match a description`() {
        let mouse = PaletteCommand(
            id: "mouse", title: "Toggle Mouse Reporting",
            detail: "Toggle whether mouse events are reported to terminal applications.",
        ) {}
        #expect(CommandMatcher.filter([mouse], query: "split").isEmpty)
        #expect(CommandMatcher.filter([mouse], query: "events are").map(\.title) == ["Toggle Mouse Reporting"])
    }

    @Test func `no match returns nothing`() {
        #expect(CommandMatcher.filter(commands, query: "zzz").isEmpty)
    }
}

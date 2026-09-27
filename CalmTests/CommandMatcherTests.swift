@testable import Calm
import Testing

struct CommandMatcherTests {
    let commands = [
        TerminalCommand(title: "Split Right", detail: "Split the terminal to the right.", action: "new_split:right", shortcut: "⌘D"),
        TerminalCommand(title: "Split Down", detail: "Split the terminal down.", action: "new_split:down", shortcut: "⇧⌘D"),
        TerminalCommand(title: "Clear Screen", detail: "Clear the screen and scrollback.", action: "clear_screen", shortcut: "⌘K"),
        TerminalCommand(title: "New Tab", detail: "Open a new tab.", action: "new_tab", shortcut: "⌘T"),
    ]

    @Test func `an empty query keeps every command in order`() {
        #expect(CommandMatcher.filter(commands, query: "  ") == commands)
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

    @Test func `no match returns nothing`() {
        #expect(CommandMatcher.filter(commands, query: "zzz").isEmpty)
    }

    @Test func `unsupported actions are hidden`() {
        #expect(!TerminalConfig.isSupported("check_for_updates"))
        #expect(!TerminalConfig.isSupported("prompt_surface_title"))
        #expect(TerminalConfig.isSupported("new_split:right"))
    }
}

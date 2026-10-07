@testable import Calm
import Foundation
import Testing

/// A pane that records the binding actions find sends it.
@MainActor
private final class FakePane: FindTarget {
    let id = UUID()
    var actions: [String] = []
    /// What the pane was last told to mark.
    var marks: (words: String?, selected: Int?) = (nil, nil)

    func perform(_ action: String) -> Bool {
        actions.append(action)
        return true
    }

    func markFind(_ words: String?, selected: Int?) {
        marks = (words, selected)
    }
}

@MainActor
struct FindModelTests {
    @Test func `a full-screen program's screen: the count says on screen, the note only when nothing matches`() {
        let find = FindModel(), pane = FakePane()
        find.handle(.start(needle: ""), from: pane)
        find.query = "segfault"
        find.handle(.fullScreen(true), from: pane)
        find.handle(.total(0), from: pane)
        #expect(find.countText == "None on screen")
        #expect(find.showsNote)
        #expect(find.noteText == "This program draws its own screen, so only what's on it can be searched.")
        find.agentName = "Claude Code"
        #expect(find.noteText == "Claude Code keeps the conversation, not the terminal.")
        find.query = "error"
        find.handle(.total(3), from: pane)
        #expect(find.countText == "3 on screen")
        #expect(!find.showsNote)
        find.handle(.selected(0), from: pane)
        #expect(find.countText == "1 of 3 on screen")
        // The program quits: its own screen again, with its scrollback.
        find.handle(.fullScreen(false), from: pane)
        #expect(find.countText == "1 of 3")
        find.close()
        #expect(!find.isFullScreen && find.agentName == nil && !find.showsNote)
    }

    @Test func `the searched pane marks the words and the current match, and nothing once find closes`() {
        let find = FindModel(), pane = FakePane()
        find.handle(.start(needle: ""), from: pane)
        #expect(pane.marks.words == nil) // no words yet
        find.query = "error"
        #expect(pane.marks.words == "error" && pane.marks.selected == nil)
        find.handle(.total(3), from: pane)
        find.handle(.selected(0), from: pane)
        #expect(pane.marks.words == "error" && pane.marks.selected == 0)
        find.close()
        #expect(pane.marks.words == nil && pane.marks.selected == nil)
    }

    @Test func `⌘F opens find with no words, and ⌘F again closes it and ends the search`() {
        let find = FindModel(), pane = FakePane()
        find.handle(.start(needle: ""), from: pane)
        #expect(find.isOpen && find.isSearching(pane))
        #expect(find.focusRequest == 1)
        #expect(pane.actions == ["search:"])
        find.handle(.start(needle: ""), from: pane)
        #expect(!find.isOpen)
        #expect(pane.actions.last == "end_search")
    }

    @Test func `typing searches, and the first count selects the newest match`() {
        let find = FindModel(), pane = FakePane()
        find.handle(.start(needle: ""), from: pane)
        find.query = "error"
        #expect(pane.actions.last == "search:error")
        #expect(find.countText == "")
        find.handle(.total(11), from: pane)
        #expect(pane.actions.last == "navigate_search:next")
        #expect(find.countText == "11 matches")
        find.handle(.selected(0), from: pane)
        #expect(find.countText == "1 of 11")
        #expect(find.newerDisabled && !find.olderDisabled)
        // A later count doesn't move the current match.
        find.handle(.total(12), from: pane)
        #expect(pane.actions.filter { $0 == "navigate_search:next" }.count == 1)
    }

    @Test func `stepping goes back in time with ↵ and forward with ⇧↵, and stops at the ends`() {
        let find = FindModel(), pane = FakePane()
        find.handle(.start(needle: "error"), from: pane)
        find.handle(.total(3), from: pane)
        find.handle(.selected(2), from: pane)
        #expect(find.countText == "3 of 3")
        #expect(find.olderDisabled && !find.newerDisabled)
        find.step(.older)
        find.step(.newer)
        #expect(pane.actions.suffix(2) == ["navigate_search:next", "navigate_search:previous"])
    }

    @Test func `nothing found says so`() {
        let find = FindModel(), pane = FakePane()
        find.handle(.start(needle: "segfault"), from: pane)
        find.handle(.total(0), from: pane)
        #expect(find.countText == "No matches")
        #expect(find.olderDisabled && find.newerDisabled)
    }

    @Test func `the pane's last words come back when find opens there again`() {
        let find = FindModel(), pane = FakePane()
        find.handle(.start(needle: ""), from: pane)
        find.query = "error"
        find.close()
        #expect(!find.isOpen)
        find.handle(.start(needle: ""), from: pane)
        #expect(find.query == "error")
        #expect(pane.actions.last == "search:error")
        #expect(find.focusRequest == 2)
    }

    @Test func `⌘E searches for the selected text`() {
        let find = FindModel(), pane = FakePane()
        find.handle(.start(needle: "lastError"), from: pane)
        #expect(find.isOpen && find.query == "lastError")
        #expect(pane.actions == ["search:lastError"])
        // ⌘E again with other text replaces the words; it doesn't close find.
        find.handle(.start(needle: "badJSON"), from: pane)
        #expect(find.isOpen && pane.actions.last == "search:badJSON")
    }

    @Test func `typing into the searched pane closes find; other panes don't`() {
        let find = FindModel(), pane = FakePane(), other = FakePane()
        find.handle(.start(needle: "error"), from: pane)
        find.didType(in: other)
        #expect(find.isOpen)
        find.didType(in: pane)
        #expect(!find.isOpen && pane.actions.last == "end_search")
    }

    @Test func `the keyboard moving to another pane closes find`() {
        let find = FindModel(), pane = FakePane(), other = FakePane()
        find.handle(.start(needle: "error"), from: pane)
        find.focusDidMove(to: pane)
        #expect(find.isOpen)
        find.focusDidMove(to: other)
        #expect(!find.isOpen && pane.actions.last == "end_search")
    }

    @Test func `opening find on another pane ends the first pane's search`() {
        let find = FindModel(), pane = FakePane(), other = FakePane()
        find.handle(.start(needle: "error"), from: pane)
        find.handle(.start(needle: ""), from: other)
        #expect(pane.actions.last == "end_search")
        #expect(find.isSearching(other))
    }

    @Test func `a search libghostty ended on its own just puts the field away`() {
        let find = FindModel(), pane = FakePane()
        find.handle(.start(needle: "error"), from: pane)
        find.handle(.end, from: pane)
        #expect(!find.isOpen)
        #expect(!pane.actions.contains("end_search"))
    }

    @Test func `another pane's counts don't reach the field`() {
        let find = FindModel(), pane = FakePane(), other = FakePane()
        find.handle(.start(needle: "error"), from: pane)
        find.handle(.total(5), from: other)
        #expect(find.total == nil)
    }

    @Test func `the field narrows to 240 before the title gives way, and never outgrows the row`() {
        func width(_ row: CGFloat, _ title: CGFloat) -> CGFloat {
            SessionTitleView.findFieldWidth(row: row, title: title, gap: 8, widest: 340, narrowest: 240)
        }
        #expect(width(860, 300) == 340) // room for both
        #expect(width(600, 300) == 292) // the field gives way first
        #expect(width(500, 300) == 240) // down to 240; the title gives way from here
        #expect(width(200, 300) == 200) // never wider than the row
    }
}

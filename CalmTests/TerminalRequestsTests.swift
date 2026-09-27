@testable import Calm
import CalmModel
import Foundation
import GhosttyKit
import Testing

struct TerminalRequestsTests {
    @Test func `ghostty numbers tabs from one`() {
        #expect(SessionTarget(ghostty_action_goto_tab_e(rawValue: 1)) == .position(0))
        #expect(SessionTarget(ghostty_action_goto_tab_e(rawValue: 9)) == .position(8))
        #expect(SessionTarget(ghostty_action_goto_tab_e(rawValue: 0)) == nil)
        #expect(SessionTarget(GHOSTTY_GOTO_TAB_PREVIOUS) == .previous)
        #expect(SessionTarget(GHOSTTY_GOTO_TAB_NEXT) == .next)
        #expect(SessionTarget(GHOSTTY_GOTO_TAB_LAST) == .last)
    }

    @Test func `session targets pick an index`() {
        #expect(SessionTarget.previous.index(from: 0, count: 3) == 2)
        #expect(SessionTarget.next.index(from: 2, count: 3) == 0)
        #expect(SessionTarget.last.index(from: 0, count: 3) == 2)
        #expect(SessionTarget.position(0).index(from: 2, count: 3) == 0)
        // Past the end goes to the last session, as in Ghostty.
        #expect(SessionTarget.position(8).index(from: 0, count: 3) == 2)
        #expect(SessionTarget.next.index(from: 0, count: 0) == nil)
    }

    @Test func `split and focus directions`() {
        #expect(PaneFocusTarget(GHOSTTY_GOTO_SPLIT_LEFT) == .toward(.left))
        #expect(PaneFocusTarget(GHOSTTY_GOTO_SPLIT_NEXT) == .next)
        #expect(SplitTree<UUID>.Direction(GHOSTTY_SPLIT_DIRECTION_DOWN) == .down)
        #expect(SplitTree<UUID>.Direction(GHOSTTY_RESIZE_SPLIT_UP) == .up)
    }
}

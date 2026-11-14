@testable import CalmModel
import Foundation
import Testing

/// The phases of a restart and what moves a session from one to the next (specs/FEATURES.md → F12).
/// `#expect` can't call a mutating method, so each event's answer is read into a `let` first.
struct RestartTrackerTests {
    private let a = UUID()
    private let b = UUID()

    @Test func `asking between turns starts at once and sets no phase yet`() {
        var tracker = RestartTracker()
        let asked = tracker.ask(a, midTurn: false)
        #expect(asked == .startNow)
        #expect(tracker[a] == nil)
        #expect(tracker.isEmpty)
    }

    @Test func `asking mid-turn waits for the turn to end`() {
        var tracker = RestartTracker()
        let asked = tracker.ask(a, midTurn: true)
        #expect(asked == .waitsForTurn)
        #expect(tracker[a] == .afterTurn)
        #expect(tracker.waiting == [a])
    }

    @Test func `asking again while one waits or runs changes nothing`() {
        var tracker = RestartTracker()
        _ = tracker.ask(a, midTurn: true)
        let whileWaiting = tracker.ask(a, midTurn: false)
        #expect(whileWaiting == .underWay)
        #expect(tracker[a] == .afterTurn)

        tracker.quitting(a)
        let whileRunning = tracker.ask(a, midTurn: true)
        #expect(whileRunning == .underWay)
        #expect(tracker[a] == .restarting)
    }

    @Test func `quitting starts a restart from either footing`() {
        var tracker = RestartTracker()
        tracker.quitting(a)
        #expect(tracker[a] == .restarting)

        _ = tracker.ask(b, midTurn: true)
        tracker.quitting(b)
        #expect(tracker[b] == .restarting)
        #expect(tracker.waiting.isEmpty)
    }

    @Test func `a waiting restart can be taken back and one under way cannot`() {
        var tracker = RestartTracker()
        _ = tracker.ask(a, midTurn: true)
        let tookBack = tracker.takeBack(a)
        #expect(tookBack)
        #expect(tracker[a] == nil)

        tracker.quitting(a)
        let tookBackRunning = tracker.takeBack(a)
        let tookBackNone = tracker.takeBack(b)
        #expect(!tookBackRunning)
        #expect(tracker[a] == .restarting)
        #expect(!tookBackNone)
    }

    @Test func `the agent coming back ends a restart under way and leaves a waiting one`() {
        var tracker = RestartTracker()
        tracker.quitting(a)
        tracker.agentBack(a)
        #expect(tracker[a] == nil)

        _ = tracker.ask(b, midTurn: true)
        tracker.agentBack(b)
        #expect(tracker[b] == .afterTurn)
    }

    @Test func `an agent that exits by itself ends a waiting restart and not one under way`() {
        var tracker = RestartTracker()
        _ = tracker.ask(a, midTurn: true)
        tracker.agentExited(a)
        #expect(tracker[a] == nil)

        tracker.quitting(b)
        tracker.agentExited(b)
        #expect(tracker[b] == .restarting)
    }

    @Test func `ending a restart clears it from either phase`() {
        var tracker = RestartTracker()
        _ = tracker.ask(a, midTurn: true)
        tracker.quitting(b)
        tracker.end(a)
        tracker.end(b)
        #expect(tracker.isEmpty)
    }

    @Test func `one session's events leave the others alone`() {
        var tracker = RestartTracker()
        _ = tracker.ask(a, midTurn: true)
        tracker.quitting(b)
        tracker.end(b)
        tracker.agentBack(b)
        #expect(tracker[a] == .afterTurn)
        #expect(tracker.waiting == [a])
    }
}

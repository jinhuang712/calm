@testable import CalmModel
import Foundation
import Testing

/// What a transcript's newest turn does to a session's state, for agents with no hook or
/// extension of their own to say they are working (FEATURES.md → F5).
struct TranscriptTurnTests {
    private let now = Date()

    private func tail(_ turn: TurnPhase?) -> TranscriptTail {
        TranscriptTail(turn: turn)
    }

    private func change(
        _ turn: TurnPhase?,
        from state: SessionState,
        report: StatusReport? = nil,
        written: Date? = nil,
    ) -> SessionState? {
        tail(turn).stateChange(from: state, after: report, transcriptWritten: written ?? now)
    }

    @Test func `a turn that has started makes an idle, done or failed session work`() {
        for state in [SessionState.idle, .done, .failed] {
            #expect(change(.inProgress, from: state) == .working, "\(state)")
        }
    }

    @Test func `a turn in progress changes nothing while the session already works or needs you`() {
        #expect(change(.inProgress, from: .working) == nil)
        // An ask is waiting, mid-turn: it stays until the turn ends.
        #expect(change(.inProgress, from: .needsYou) == nil)
    }

    @Test func `a turn that has finished ends the work, or the wait`() {
        #expect(change(.finished, from: .working) == .done)
        #expect(change(.finished, from: .needsYou) == .done)
        for state in [SessionState.idle, .done, .failed] {
            #expect(change(.finished, from: state) == nil, "\(state)")
        }
    }

    @Test func `a turn that failed ends the work as failed`() {
        #expect(change(.failed, from: .working) == .failed)
        #expect(change(.failed, from: .needsYou) == .failed)
        #expect(change(.failed, from: .idle) == nil)
    }

    @Test func `a transcript that says nothing about the turn changes nothing`() {
        for state in [SessionState.idle, .working, .needsYou, .done, .failed] {
            #expect(change(nil, from: state) == nil, "\(state)")
        }
    }

    @Test func `an agent's own hook report outranks the transcript`() {
        let hook = StatusReport(state: .working, source: .hook, date: now.addingTimeInterval(-60))
        #expect(change(.finished, from: .working, report: hook) == nil)
        #expect(change(.inProgress, from: .idle, report: hook) == nil)
    }

    @Test func `a terminal signal doesn't outrank it`() {
        let signal = StatusReport(state: .done, source: .terminal, date: now.addingTimeInterval(-60))
        #expect(change(.inProgress, from: .done, report: signal) == .working)
    }

    @Test func `a reading older than the latest report is stale`() {
        // The desktop notification for the finished turn arrived first; a transcript read that
        // was written before it must not put the session back to work.
        let reported = now
        let signal = StatusReport(state: .done, source: .terminal, date: reported)
        #expect(change(.inProgress, from: .done, report: signal, written: reported.addingTimeInterval(-1)) == nil)
        #expect(change(.inProgress, from: .done, report: signal, written: reported.addingTimeInterval(1)) == .working)
    }

    @Test func `the phase is saved with the tail, and older files without it still load`() throws {
        let tail = TranscriptTail(lastMessage: "hi", turn: .inProgress)
        let decoded = try JSONDecoder().decode(TranscriptTail.self, from: JSONEncoder().encode(tail))
        #expect(decoded.turn == .inProgress)
        let old = try JSONDecoder().decode(TranscriptTail.self, from: Data(#"{"interrupted":false,"lastMessage":"hi"}"#.utf8))
        #expect(old.turn == nil)
    }
}

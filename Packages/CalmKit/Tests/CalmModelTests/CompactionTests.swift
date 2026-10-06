@testable import CalmModel
import Foundation
import Testing

/// A compaction on a session card (UIUX.md → Session cards): the order of events is the one
/// Claude Code 2.1.291 sends (captured 2026-10-06), and the sizes are a real one's.
struct CompactionTests {
    private let start = Date(timeIntervalSince1970: 1_000_000)

    /// A Claude Code session whose last reply saw 968,495 tokens.
    private func workspace(state: SessionState = .working) -> (Workspace, Session.ID) {
        var workspace = Workspace()
        let id = workspace.newSession(in: "/tmp/app", gitRoot: { _ in nil }).id
        workspace.startAgentRun(id, AgentRun(kind: .claudeCode, processID: 1))
        workspace.updateTranscriptTail(id, TranscriptTail(lastMessage: "Running the suite before the docs.", contextTokens: 968_495))
        if state != .idle {
            workspace.report(id, StatusReport(state: state, source: .hook, date: start - 60), focusedSessionID: nil)
        }
        return (workspace, id)
    }

    private func hook(
        _ state: SessionState, _ message: String? = nil, _ compaction: CompactionReport? = nil, at seconds: TimeInterval,
    ) -> StatusReport {
        StatusReport(state: state, message: message, source: .hook, date: start + seconds, compaction: compaction)
    }

    /// The transcript once the compaction is recorded: 968,495 → 13,000 tokens.
    private func recorded(at seconds: TimeInterval) -> TranscriptTail {
        TranscriptTail(
            lastMessage: "Running the suite before the docs.", contextTokens: 968_495,
            lastCompaction: CompactedContext(date: start + seconds, tokensBefore: 968_495, tokensAfter: 13000),
            newestMessageAt: start - 1,
        )
    }

    @Test func `while Claude compacts mid-turn, the card says so and the bar is full`() {
        var (workspace, id) = workspace()
        workspace.report(id, hook(.working, nil, .started(.auto), at: 0), focusedSessionID: nil)
        let session = workspace.session(id)
        #expect(session?.state == .working)
        #expect(session?.isCompacting == true)
        #expect(session?.workingStep == "Compacting")
        #expect(session?.compactionBar(now: start + 90) == .full(tokens: 968_495))
        #expect(session?.compactionBar(now: start + 90)?.label == "968k")
        // It runs until the agent says it ended, however long.
        #expect(session?.compactionBarEnds == nil)
    }

    @Test func `once over, the bar drains to what was kept and goes after five seconds`() {
        var (workspace, id) = workspace()
        workspace.report(id, hook(.working, nil, .started(.auto), at: 0), focusedSessionID: nil)
        workspace.report(id, hook(.working, nil, .ended(.auto), at: 99), focusedSessionID: nil)
        // Ended, nothing recorded yet: held full a moment instead of going and coming back.
        #expect(workspace.session(id)?.compactionBar(now: start + 99.5) == .full(tokens: 968_495))
        #expect(workspace.session(id)?.isCompacting == false)
        workspace.updateTranscriptTail(id, recorded(at: 99))
        let session = workspace.session(id)
        #expect(session?.compactionBar(now: start + 100) == .drained(from: 968_495, to: 13000))
        #expect(session?.compactionBar(now: start + 100)?.label == "968k → 13k")
        #expect(session?.compactionBarEnds == start + 104)
        #expect(session?.compactionBar(now: start + 104) == nil)
        // The turn goes on with its own step.
        #expect(session?.workingStep == nil)
    }

    @Test func `a record read before the agent's report ends it too`() {
        var (workspace, id) = workspace()
        workspace.report(id, hook(.working, nil, .started(.auto), at: 0), focusedSessionID: nil)
        workspace.updateTranscriptTail(id, recorded(at: 99))
        #expect(workspace.session(id)?.isCompacting == false)
        #expect(workspace.session(id)?.compactionBar(now: start + 100) == .drained(from: 968_495, to: 13000))
        // The report that follows changes nothing it said.
        workspace.report(id, hook(.working, nil, .ended(.auto), at: 99.02), focusedSessionID: nil)
        #expect(workspace.session(id)?.compaction?.endedAt == start + 99)
    }

    @Test func `a compact you typed ends as done, saying so, and its bar stays until you move on`() {
        var (workspace, id) = workspace(state: .idle)
        // `/compact` sends no prompt hook: its start is what makes the card busy.
        workspace.report(id, hook(.working, nil, .started(.manual), at: 0), focusedSessionID: nil)
        #expect(workspace.session(id)?.isCompacting == true)
        workspace.report(id, hook(.done, "Conversation compacted.", .ended(.manual), at: 108), focusedSessionID: nil)
        workspace.updateTranscriptTail(id, recorded(at: 108))
        var session = workspace.session(id)
        #expect(session?.state == .done)
        // The last thing Claude said came before the compaction.
        #expect(session?.recap == "Conversation compacted.")
        #expect(session?.compactionBar(now: start + 3600) == .drained(from: 968_495, to: 13000))
        #expect(session?.compactionBarEnds == nil)
        workspace.settle(id)
        session = workspace.session(id)
        #expect(session?.state == .idle)
        #expect(session?.compactionBar(now: start + 3600) == nil)
        #expect(session?.recap == "Running the suite before the docs.")
    }

    @Test func `a starting compaction isn't taken for a repeat of the working it already was`() {
        var (workspace, id) = workspace()
        workspace.report(id, hook(.working, at: 0), focusedSessionID: nil)
        workspace.report(id, hook(.working, nil, .started(.auto), at: 1), focusedSessionID: nil)
        #expect(workspace.session(id)?.isCompacting == true)
    }

    @Test func `pressing Esc cancels a compact with no hook, and the transcript's next message says so`() {
        var (workspace, id) = workspace(state: .idle)
        workspace.report(id, hook(.working, nil, .started(.manual), at: 0), focusedSessionID: nil)
        // Bookkeeping while it runs (a queued prompt) is no message: still compacting.
        var tail = TranscriptTail(lastMessage: "Running the suite before the docs.", contextTokens: 968_495, newestMessageAt: start - 0.04)
        workspace.updateTranscriptTail(id, tail)
        #expect(workspace.session(id)?.isCompacting == true)
        tail.newestMessageAt = start + 1.8
        workspace.updateTranscriptTail(id, tail, readAt: start + 2)
        let session = workspace.session(id)
        #expect(session?.compaction == nil)
        #expect(session?.state == .idle)
        #expect(session?.compactionBar(now: start + 3) == nil)
    }

    @Test func `pressing Esc mid-turn leaves the state to the turn's interruption`() {
        var (workspace, id) = workspace()
        workspace.report(id, hook(.working, nil, .started(.auto), at: 0), focusedSessionID: nil)
        let interrupted = TranscriptTail(lastMessage: "Running the suite before the docs.", interrupted: true, newestMessageAt: start + 3)
        workspace.updateTranscriptTail(id, interrupted)
        #expect(workspace.session(id)?.compaction == nil)
        #expect(workspace.session(id)?.state == .idle)
    }

    @Test func `an earlier compaction's record isn't this one's end`() {
        var (workspace, id) = workspace()
        workspace.updateTranscriptTail(id, recorded(at: -3600))
        workspace.report(id, hook(.working, nil, .started(.auto), at: 0), focusedSessionID: nil)
        workspace.report(id, hook(.working, nil, .ended(.auto), at: 99), focusedSessionID: nil)
        #expect(workspace.session(id)?.compaction?.tokensAfter == nil)
        #expect(workspace.session(id)?.compactionBar(now: start + 100) == .full(tokens: 968_495))
        // With nothing ever recorded (no transcript), the bar goes when a drained one would.
        #expect(workspace.session(id)?.compactionBar(now: start + 104) == nil)
    }

    @Test func `the turn ending while it runs ends it, and so does the agent leaving`() {
        var (workspace, id) = workspace()
        workspace.report(id, hook(.working, nil, .started(.auto), at: 0), focusedSessionID: nil)
        workspace.report(id, hook(.failed, "Overloaded", at: 5), focusedSessionID: nil)
        #expect(workspace.session(id)?.compaction == nil)
        workspace.report(id, hook(.working, nil, .started(.auto), at: 10), focusedSessionID: nil)
        workspace.endAgentRun(id)
        #expect(workspace.session(id)?.compaction == nil)
    }

    @Test func `it isn't saved`() throws {
        var (workspace, id) = workspace()
        workspace.report(id, hook(.working, nil, .started(.auto), at: 0), focusedSessionID: nil)
        let data = try JSONEncoder().encode(workspace)
        let loaded = try JSONDecoder().decode(Workspace.self, from: data)
        #expect(loaded.session(id)?.compaction == nil)
        #expect(loaded.session(id)?.state == .working)
    }

    @Test func `sizes read the way people say them`() {
        #expect(CompactionBar.tokens(850) == "850")
        #expect(CompactionBar.tokens(1192) == "1.2k")
        #expect(CompactionBar.tokens(5000) == "5k")
        #expect(CompactionBar.tokens(13000) == "13k")
        #expect(CompactionBar.tokens(16939) == "17k")
        #expect(CompactionBar.tokens(968_495) == "968k")
        #expect(CompactionBar.tokens(999_700) == "1M")
        #expect(CompactionBar.tokens(1_250_000) == "1.3M")
        #expect(CompactionBar.drained(from: 968_495, to: 13000).fraction == 13000.0 / 968_495)
        #expect(CompactionBar.full(tokens: nil).label == nil)
    }

    @Test func `reports pass through calm hook by name`() {
        for report in [CompactionReport.started(.manual), .started(.auto), .ended(.manual), .ended(.auto)] {
            #expect(CompactionReport(reportName: report.reportName) == report)
        }
        #expect(CompactionReport.started(.manual).reportName == "start:manual")
        #expect(CompactionReport(reportName: "start:later") == nil)
        #expect(CompactionReport(reportName: "begin:auto") == nil)
    }
}

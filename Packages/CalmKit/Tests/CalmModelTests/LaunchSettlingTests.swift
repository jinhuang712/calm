@testable import CalmModel
import Foundation
import Testing

struct LaunchSettlingTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    /// A workspace with one session running Claude Code as pid 100, in `state` since ten minutes ago.
    private func fixture(
        _ state: SessionState, pid: Int32 = 100, reportedAt: Date? = nil,
    ) -> (workspace: Workspace, id: Session.ID) {
        var workspace = Workspace()
        let id = workspace.newSession(in: "/tmp/a", gitRoot: { _ in nil }).id
        workspace.startAgentRun(id, AgentRun(kind: .claudeCode, processID: pid))
        let date = reportedAt ?? now.addingTimeInterval(-600)
        workspace.report(id, StatusReport(state: state, source: .hook, date: date), focusedSessionID: nil)
        return (workspace, id)
    }

    private func running(_ pid: Int32 = 100, _ status: AgentLiveStatus? = nil, kind: AgentKind = .claudeCode) -> AgentAtLaunch {
        .running(kind: kind, processID: pid, status: status)
    }

    private func status(_ phase: AgentLiveStatus.Phase, secondsAgo: TimeInterval) -> AgentLiveStatus {
        AgentLiveStatus(phase: phase, since: now.addingTimeInterval(-secondsAgo))
    }

    @Test func `a run whose agent is gone ends, and its working becomes idle`() {
        var (workspace, id) = fixture(.working)
        workspace.settleSavedRun(id, found: .gone, savedAt: now, now: now)
        #expect(workspace.session(id)?.agent == nil)
        #expect(workspace.session(id)?.state == .idle)
    }

    @Test func `a run whose agent is gone leaves needs you and done as they were`() {
        for state in [SessionState.needsYou, .done] {
            var (workspace, id) = fixture(state)
            workspace.settleSavedRun(id, found: .gone, savedAt: now, now: now)
            #expect(workspace.session(id)?.agent == nil)
            #expect(workspace.session(id)?.state == state)
        }
    }

    @Test func `the same agent still running keeps its run, tail and state`() {
        var (workspace, id) = fixture(.working)
        workspace.updateTranscriptTail(id, TranscriptTail(title: "Fix the race", lastMessage: "Reading the log"))
        let since = workspace.session(id)?.stateSince
        workspace.settleSavedRun(id, found: running(100, status(.busy, secondsAgo: 400)), savedAt: now, now: now)
        let session = workspace.session(id)
        #expect(session?.agent?.tail?.title == "Fix the race")
        #expect(session?.agent?.processID == 100)
        #expect(session?.state == .working)
        // Agreeing with what was saved changes nothing, not even when the state began.
        #expect(session?.stateSince == since)
    }

    @Test func `a run first known from its hooks takes the process the probe found`() {
        var (workspace, id) = fixture(.working, pid: 0)
        workspace.settleSavedRun(id, found: running(4242, status(.busy, secondsAgo: 400)), savedAt: now, now: now)
        #expect(workspace.session(id)?.agent?.processID == 4242)
        #expect(workspace.session(id)?.state == .working)
    }

    @Test func `another agent, or another process, ends the saved run`() {
        var (workspace, id) = fixture(.working)
        workspace.settleSavedRun(id, found: running(100, kind: .codex), savedAt: now, now: now)
        #expect(workspace.session(id)?.agent == nil)
        #expect(workspace.session(id)?.state == .idle)

        var (other, otherID) = fixture(.working)
        other.settleSavedRun(otherID, found: running(555, status(.busy, secondsAgo: 5)), savedAt: now, now: now)
        #expect(other.session(otherID)?.agent == nil)
        #expect(other.session(otherID)?.state == .idle)
    }

    @Test func `a session with no saved run is left to the probe`() {
        var workspace = Workspace()
        let id = workspace.newSession(in: "/tmp/a", gitRoot: { _ in nil }).id
        workspace.settleSavedRun(id, found: running(), savedAt: now, now: now)
        #expect(workspace.session(id)?.agent == nil)
        #expect(workspace.session(id)?.state == .idle)
    }

    @Test func `an agent that says idle corrects a stale working, since it said so`() {
        var (workspace, id) = fixture(.working)
        workspace.settleSavedRun(id, found: running(100, status(.idle, secondsAgo: 60)), savedAt: now, now: now)
        let session = workspace.session(id)
        #expect(session?.state == .idle)
        #expect(session?.stateSince == now.addingTimeInterval(-60))
        // The agent still runs, so hooks keep speaking for the row.
        #expect(session?.agent != nil)
        #expect(session?.lastReport?.source == .hook)
    }

    @Test func `an agent that says busy lights up an idle, done or failed row since it said so`() {
        for state in [SessionState.idle, .done, .failed] {
            var (workspace, id) = fixture(state, reportedAt: now.addingTimeInterval(-600))
            workspace.settleSavedRun(id, found: running(100, status(.busy, secondsAgo: 64)), savedAt: now, now: now)
            let session = workspace.session(id)
            #expect(session?.state == .working, "from \(state)")
            #expect(session?.stateSince == now.addingTimeInterval(-64))
        }
    }

    @Test func `a status older than the last report is not believed`() {
        // Hooks reported working a minute ago; the file says idle since ten minutes ago.
        var (workspace, id) = fixture(.working, reportedAt: now.addingTimeInterval(-60))
        workspace.settleSavedRun(id, found: running(100, status(.idle, secondsAgo: 600)), savedAt: now, now: now)
        #expect(workspace.session(id)?.state == .working)
    }

    @Test func `a status a moment before the report still counts as after it`() {
        // The agent writes its file, then runs the hook: the report can come a few tenths later.
        var (workspace, id) = fixture(.idle, reportedAt: now.addingTimeInterval(-60))
        let status = AgentLiveStatus(phase: .busy, since: now.addingTimeInterval(-60.4))
        workspace.settleSavedRun(id, found: running(100, status), savedAt: now, now: now)
        #expect(workspace.session(id)?.state == .working)
    }

    @Test func `needs you is left to hooks whatever the agent says`() {
        for phase in [AgentLiveStatus.Phase.busy, .idle, .waiting] {
            var (workspace, id) = fixture(.needsYou)
            workspace.settleSavedRun(id, found: running(100, status(phase, secondsAgo: 5)), savedAt: now, now: now)
            #expect(workspace.session(id)?.state == .needsYou, "\(phase)")
        }
    }

    @Test func `waiting changes no row yet`() {
        for state in [SessionState.idle, .working, .done] {
            var (workspace, id) = fixture(state)
            workspace.settleSavedRun(id, found: running(100, status(.waiting, secondsAgo: 5)), savedAt: now, now: now)
            #expect(workspace.session(id)?.state == state, "\(state)")
        }
    }

    @Test func `with no status, a saved working stands only if it was saved moments ago`() {
        var (fresh, freshID) = fixture(.working)
        fresh.settleSavedRun(freshID, found: running(), savedAt: now.addingTimeInterval(-5), now: now)
        #expect(fresh.session(freshID)?.state == .working)
        #expect(fresh.session(freshID)?.agent != nil)

        var (stale, staleID) = fixture(.working)
        stale.settleSavedRun(staleID, found: running(), savedAt: now.addingTimeInterval(-3600), now: now)
        #expect(stale.session(staleID)?.state == .idle)
        // Idle, but the agent is still there: the row keeps its mark.
        #expect(stale.session(staleID)?.agent != nil)

        var (unknown, unknownID) = fixture(.working)
        unknown.settleSavedRun(unknownID, found: running(), savedAt: nil, now: now)
        #expect(unknown.session(unknownID)?.state == .idle)
    }

    @Test func `with no status, done and needs you stand however old they are`() {
        for state in [SessionState.done, .needsYou, .failed] {
            var (workspace, id) = fixture(state)
            workspace.settleSavedRun(id, found: running(), savedAt: now.addingTimeInterval(-86400), now: now)
            #expect(workspace.session(id)?.state == state)
        }
    }
}

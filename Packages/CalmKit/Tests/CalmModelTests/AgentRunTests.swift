@testable import CalmModel
import Foundation
import Testing

struct AgentRunTests {
    private func workspaceWithSession() -> (Workspace, Session.ID) {
        var workspace = Workspace()
        let id = workspace.newSession(in: "/tmp/a", gitRoot: { _ in nil }).id
        return (workspace, id)
    }

    @Test func `hooks can start a run the probe later completes`() {
        var (workspace, id) = workspaceWithSession()
        workspace.noteAgentSession(id, kind: .claudeCode, agentSessionID: "abc", transcriptPath: "/tmp/abc.jsonl")
        workspace.report(id, StatusReport(state: .working, source: .hook), focusedSessionID: nil)
        #expect(workspace.session(id)?.agent?.processID == 0)

        workspace.startAgentRun(id, AgentRun(kind: .claudeCode, processID: 4242))
        let run = workspace.session(id)?.agent
        #expect(run?.processID == 4242)
        #expect(run?.transcriptPath == "/tmp/abc.jsonl")
        // The hook's state survives: filling in the process isn't a new run.
        #expect(workspace.session(id)?.state == .working)
        #expect(workspace.session(id)?.lastReport?.source == .hook)
    }

    @Test func `a different agent replaces the run`() {
        var (workspace, id) = workspaceWithSession()
        workspace.startAgentRun(id, AgentRun(kind: .claudeCode, processID: 1))
        workspace.report(id, StatusReport(state: .working, source: .hook), focusedSessionID: nil)
        workspace.startAgentRun(id, AgentRun(kind: .codex, processID: 2))
        #expect(workspace.session(id)?.agent?.kind == .codex)
        #expect(workspace.session(id)?.state == .idle)
    }

    @Test func `ending a run clears it`() {
        var (workspace, id) = workspaceWithSession()
        workspace.startAgentRun(id, AgentRun(kind: .pi, processID: 7))
        workspace.endAgentRun(id)
        #expect(workspace.session(id)?.agent == nil)
    }
}

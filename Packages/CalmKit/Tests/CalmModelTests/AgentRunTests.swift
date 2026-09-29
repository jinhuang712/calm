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

    @Test func `a read card shows the agent's summary, one with news shows its latest message`() {
        var (workspace, id) = workspaceWithSession()
        workspace.startAgentRun(id, AgentRun(kind: .claudeCode, processID: 1))
        workspace.updateTranscriptTail(
            id,
            TranscriptTail(lastMessage: "Caveats on option two.", summary: "You're picking a library. Next, benchmark it."),
        )
        workspace.report(id, StatusReport(state: .done, message: "Caveats on option two.", source: .hook), focusedSessionID: nil)
        // Done and not yet seen: what it just said is the news.
        #expect(workspace.session(id)?.recap == "Caveats on option two.")
        workspace.report(id, StatusReport(state: .idle, source: .hook), focusedSessionID: nil)
        #expect(workspace.session(id)?.recap == "You're picking a library. Next, benchmark it.")
        workspace.report(id, StatusReport(state: .needsYou, message: "Allow Bash: swift test", source: .hook), focusedSessionID: nil)
        #expect(workspace.session(id)?.recap == "Allow Bash: swift test")
    }

    @Test func `an idle card with no summary keeps the latest message`() {
        var (workspace, id) = workspaceWithSession()
        workspace.startAgentRun(id, AgentRun(kind: .codex, processID: 1))
        workspace.updateTranscriptTail(id, TranscriptTail(lastMessage: "Fixed the login test."))
        #expect(workspace.session(id)?.state == .idle)
        #expect(workspace.session(id)?.recap == "Fixed the login test.")
    }

    @Test func `a report is the session's unless another agent has the foreground`() {
        // The incident (2026-09-30): Claude Code ran `pi -p` in its Bash tool, and pi's report
        // turned the session's row into pi's, "done" included.
        #expect(!AgentKind.pi.speaksForSession(whileForeground: .claudeCode))
        #expect(AgentKind.claudeCode.speaksForSession(whileForeground: .claudeCode))
        for kind in AgentKind.allCases {
            for other in AgentKind.allCases where other != kind {
                #expect(!kind.speaksForSession(whileForeground: other), "\(kind) while \(other)")
            }
        }
    }

    @Test func `a report stands while no agent is recognised in the foreground`() {
        // A wrapper script, or a shell the probe hasn't looked at yet: degrade to the old way.
        for kind in AgentKind.allCases {
            #expect(kind.speaksForSession(whileForeground: nil), "\(kind)")
        }
    }

    @Test func `ending a run clears it`() {
        var (workspace, id) = workspaceWithSession()
        workspace.startAgentRun(id, AgentRun(kind: .pi, processID: 7))
        workspace.endAgentRun(id)
        #expect(workspace.session(id)?.agent == nil)
    }

    @Test func `a search result is running in a session when its agent there is that conversation`() {
        var session = Session(projectID: UUID(), workingDirectory: "/tmp/a")
        #expect(!session.runs(transcriptPath: "/t/one.jsonl", agentSessionID: "one"))
        var run = AgentRun(kind: .claudeCode, processID: 7)
        run.transcriptPath = "/t/one.jsonl"
        run.agentSessionID = "one"
        session.agent = run
        #expect(session.runs(transcriptPath: "/t/one.jsonl", agentSessionID: nil))
        // The agent's own id matches before its transcript is known, as with hooks alone.
        #expect(session.runs(transcriptPath: "/t/elsewhere.jsonl", agentSessionID: "one"))
        #expect(!session.runs(transcriptPath: "/t/two.jsonl", agentSessionID: "two"))
        #expect(!session.runs(transcriptPath: "/t/two.jsonl", agentSessionID: nil))
    }

    @Test func `a conversation whose agent exited isn't running, though its session is still open`() {
        var session = Session(projectID: UUID(), workingDirectory: "/tmp/a")
        session.lastConversation = AgentConversation(kind: .claudeCode, agentSessionID: "one", transcriptPath: "/t/one.jsonl")
        #expect(!session.runs(transcriptPath: "/t/one.jsonl", agentSessionID: "one"))
    }
}

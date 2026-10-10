@testable import CalmAgents
import CalmModel
import Foundation
import Testing

struct SessionCopyTests {
    private func session(agent: AgentRun? = nil, last: AgentConversation? = nil, scratch: Bool = false) -> Session {
        var session = Session(projectID: UUID(), title: "zsh", workingDirectory: "/Users/ada/dev/calm")
        session.agent = agent
        session.lastConversation = last
        session.scratchFolder = scratch ? "/Users/ada/.local/share/calm/scratch/1" : nil
        return session
    }

    private func run(_ kind: AgentKind, id: String?, transcript: String? = nil) -> AgentRun {
        var run = AgentRun(kind: kind, processID: 42)
        run.agentSessionID = id
        run.transcriptPath = transcript
        return run
    }

    @Test func `a running agent gives its id and the command that resumes it`() {
        let session = session(agent: run(.claudeCode, id: "abc-123"))
        #expect(SessionCopy.sessionID.text(for: session) == "abc-123")
        #expect(SessionCopy.resumeCommand.text(for: session) == "claude --resume 'abc-123'")
    }

    @Test func `the copied command starts the agent the way it was started`() {
        var running = run(.claudeCode, id: "abc-123")
        running.options = ["--dangerously-skip-permissions"]
        #expect(SessionCopy.resumeCommand.text(for: session(agent: running)) == "claude --dangerously-skip-permissions --resume 'abc-123'")
    }

    @Test func `an ended conversation can still be copied`() {
        let last = AgentConversation(kind: .codex, agentSessionID: "019a", transcriptPath: nil)
        let session = session(last: last)
        #expect(SessionCopy.sessionID.text(for: session) == "019a")
        #expect(SessionCopy.resumeCommand.text(for: session) == "codex resume '019a'")
    }

    @Test func `claude's id comes from its transcript's name when the hook gave none`() {
        let session = session(agent: run(.claudeCode, id: nil, transcript: "/x/def-456.jsonl"))
        #expect(SessionCopy.sessionID.text(for: session) == "def-456")
        #expect(SessionCopy.resumeCommand.text(for: session) == "claude --resume 'def-456'")
    }

    @Test func `a shell with no agent has no id or command`() {
        let session = session()
        #expect(SessionCopy.sessionID.text(for: session) == nil)
        #expect(SessionCopy.resumeCommand.text(for: session) == nil)
        #expect(SessionCopy.folderPath.text(for: session) == "/Users/ada/dev/calm")
    }

    @Test func `codex without an id has nothing to copy`() {
        let session = session(agent: run(.codex, id: nil, transcript: "/x/rollout.jsonl"))
        #expect(SessionCopy.sessionID.text(for: session) == nil)
        #expect(SessionCopy.resumeCommand.text(for: session) == nil)
    }

    @Test func `a scratch session gives no folder`() {
        #expect(SessionCopy.folderPath.text(for: session(scratch: true)) == nil)
    }
}

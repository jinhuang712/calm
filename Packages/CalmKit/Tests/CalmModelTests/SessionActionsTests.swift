@testable import CalmModel
import Foundation
import Testing

struct SessionActionsTests {
    private func workspace() -> (Workspace, Session.ID) {
        var workspace = Workspace()
        let project = Project(path: "/tmp/app")
        workspace.projects = [project]
        let session = Session(projectID: project.id, title: "zsh", workingDirectory: "/tmp/app")
        workspace.sessions = [session]
        return (workspace, session.id)
    }

    @Test func `a name wins over every other title, and an empty one gives it back`() throws {
        var (workspace, id) = workspace()
        workspace.rename(id, to: "  Payments  ")
        var session = try #require(workspace.session(id))
        #expect(session.customName == "Payments")
        #expect(session.displayTitle == "Payments")
        #expect(session.title(agentTitle: "Fix the flaky test") == "Payments")

        workspace.rename(id, to: " ")
        session = try #require(workspace.session(id))
        #expect(session.customName == nil)
        #expect(session.title(agentTitle: "Fix the flaky test") == "Fix the flaky test")
        #expect(session.title(agentTitle: "") == "zsh")
    }

    @Test func `an agent that exits leaves its conversation to resume, and a new one to fork`() throws {
        var (workspace, id) = workspace()
        var run = AgentRun(kind: .claudeCode, processID: 42)
        workspace.startAgentRun(id, run)
        #expect(workspace.session(id)?.conversation == nil) // nothing known about it yet
        run.agentSessionID = "abc"
        run.transcriptPath = "/tmp/abc.jsonl"
        workspace.sessions[0].agent = run
        #expect(workspace.session(id)?.conversation?.agentSessionID == "abc")
        #expect(workspace.session(id)?.resumableConversation == nil) // still running

        workspace.endAgentRun(id)
        let session = try #require(workspace.session(id))
        #expect(session.agent == nil)
        #expect(session.resumableConversation == AgentConversation(
            kind: .claudeCode,
            agentSessionID: "abc",
            transcriptPath: "/tmp/abc.jsonl",
        ))
        #expect(session.conversation == session.lastConversation)

        // A run nothing was learned about doesn't replace the last conversation.
        workspace.startAgentRun(id, AgentRun(kind: .codex, processID: 7))
        workspace.endAgentRun(id)
        #expect(workspace.session(id)?.lastConversation?.agentSessionID == "abc")
    }

    @Test func `older state files without the new fields still load`() throws {
        let (workspace, id) = workspace()
        let data = try JSONEncoder().encode(workspace)
        var object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        var sessions = try #require(object["sessions"] as? [[String: Any]])
        sessions[0].removeValue(forKey: "customName")
        sessions[0].removeValue(forKey: "lastConversation")
        object["sessions"] = sessions
        let decoded = try JSONDecoder().decode(Workspace.self, from: JSONSerialization.data(withJSONObject: object))
        #expect(decoded.session(id)?.customName == nil)
        #expect(decoded.session(id)?.lastConversation == nil)
    }

    @Test(arguments: [
        "✳ Fix the flaky test",
        "◐ Fix the flaky test",
        "◓◑  Fix the flaky test",
        "⠂ Fix the flaky test",
        "Fix the flaky test",
    ])
    func `a shell title loses an agent's status glyph`(raw: String) throws {
        var (workspace, id) = workspace()
        workspace.setTitle(id, raw)
        #expect(try #require(workspace.session(id)).displayTitle == "Fix the flaky test")
    }

    @Test func `a glyph inside a title stays, and a saved title with one reads clean`() throws {
        #expect(Session.shellTitle("Build ✳ ship") == "Build ✳ ship")
        let (workspace, id) = workspace()
        var session = try #require(workspace.session(id))
        session.title = "◑ Settings page redesign"
        #expect(session.displayTitle == "Settings page redesign")
        session.title = "✳"
        #expect(session.displayTitle == "app")
    }
}

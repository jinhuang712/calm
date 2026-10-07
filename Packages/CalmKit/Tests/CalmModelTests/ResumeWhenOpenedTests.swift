@testable import CalmModel
import Foundation
import Testing

/// A shell that went with an agent in it (the Mac restarted): the conversation resumes the first
/// time the session opens (FEATURES.md → F3).
struct ResumeWhenOpenedTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    /// A workspace with one session running Claude Code, its conversation known when `named`.
    private func fixture(named: Bool = true) -> (workspace: Workspace, id: Session.ID) {
        var workspace = Workspace()
        let id = workspace.newSession(in: "/tmp/a", gitRoot: { _ in nil }).id
        var run = AgentRun(kind: .claudeCode, processID: 100)
        if named {
            run.agentSessionID = "abc"
            run.transcriptPath = "/x/abc.jsonl"
        }
        workspace.startAgentRun(id, run)
        workspace.report(id, StatusReport(state: .working, source: .hook, date: now.addingTimeInterval(-600)), focusedSessionID: nil)
        return (workspace, id)
    }

    @Test func `a run whose shell went resumes its conversation once, as the session opens`() {
        var (workspace, id) = fixture()
        workspace.settleSavedRun(id, found: .gone, shellGone: true, savedAt: now, now: now)
        #expect(workspace.session(id)?.agent == nil)
        #expect(workspace.session(id)?.resumesWhenOpened == true)

        let conversation = workspace.takeConversationToResume(id)
        #expect(conversation?.agentSessionID == "abc")
        #expect(conversation?.kind == .claudeCode)
        #expect(workspace.session(id)?.resumesWhenOpened == nil)
        #expect(workspace.takeConversationToResume(id) == nil)
    }

    @Test func `an agent that ended in a shell still there stays ended`() {
        var (workspace, id) = fixture()
        workspace.settleSavedRun(id, found: .gone, shellGone: false, savedAt: now, now: now)
        #expect(workspace.session(id)?.resumesWhenOpened == nil)
        #expect(workspace.takeConversationToResume(id) == nil)
        // It can still be resumed by hand, from the session menu.
        #expect(workspace.session(id)?.resumableConversation?.agentSessionID == "abc")
    }

    @Test func `an agent still running in a listed shell is no reason to resume`() {
        var (workspace, id) = fixture()
        workspace.settleSavedRun(
            id,
            found: .running(kind: .claudeCode, processID: 100, status: nil),
            shellGone: false,
            savedAt: now,
            now: now,
        )
        #expect(workspace.session(id)?.agent != nil)
        #expect(workspace.session(id)?.resumesWhenOpened == nil)
    }

    @Test func `a run with no known conversation never resumes an older one`() {
        var (workspace, id) = fixture(named: false)
        // An earlier conversation in the same session, already ended.
        workspace.sessions[0].lastConversation = AgentConversation(kind: .claudeCode, agentSessionID: "older", transcriptPath: nil)
        workspace.settleSavedRun(id, found: .gone, shellGone: true, savedAt: now, now: now)
        #expect(workspace.session(id)?.resumesWhenOpened == nil)
        #expect(workspace.takeConversationToResume(id) == nil)
    }

    @Test func `an agent started meanwhile takes the place of the resume`() {
        var (workspace, id) = fixture()
        workspace.settleSavedRun(id, found: .gone, shellGone: true, savedAt: now, now: now)
        workspace.startAgentRun(id, AgentRun(kind: .claudeCode, processID: 200))
        #expect(workspace.takeConversationToResume(id) == nil)
        #expect(workspace.session(id)?.resumesWhenOpened == nil)
    }

    @Test func `the mark is saved, and older state files read as no mark`() throws {
        var (workspace, id) = fixture()
        workspace.settleSavedRun(id, found: .gone, shellGone: true, savedAt: now, now: now)
        let data = try JSONEncoder().encode(workspace)
        let decoded = try JSONDecoder().decode(Workspace.self, from: data)
        #expect(decoded.session(id)?.resumesWhenOpened == true)

        var (plain, plainID) = fixture()
        plain.settleSavedRun(plainID, found: .gone, savedAt: now, now: now)
        let plainData = try JSONEncoder().encode(plain)
        // Nothing written for a session without the mark, so state files stay as they were.
        #expect(String(bytes: plainData, encoding: .utf8)?.contains("resumesWhenOpened") == false)
        #expect(try JSONDecoder().decode(Workspace.self, from: plainData).session(plainID)?.resumesWhenOpened == nil)
    }
}

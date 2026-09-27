@testable import CalmModel
import Foundation
import Testing

struct AttentionTests {
    /// A workspace with two sessions; the user is looking at `watched`.
    private struct Fixture {
        var workspace = Workspace()
        let watched: Session.ID
        let other: Session.ID

        init() {
            watched = workspace.newSession(in: "/tmp/a", gitRoot: { _ in nil }).id
            other = workspace.newSession(in: "/tmp/b", gitRoot: { _ in nil }).id
        }
    }

    private func hook(_ state: SessionState, _ message: String? = nil) -> StatusReport {
        StatusReport(state: state, message: message, source: .hook)
    }

    private func terminal(_ state: SessionState) -> StatusReport {
        StatusReport(state: state, source: .terminal)
    }

    @Test func `needs you in another session notifies once`() {
        let fixture = Fixture()
        var workspace = fixture.workspace
        let (watched, other) = (fixture.watched, fixture.other)
        #expect(workspace.report(other, hook(.needsYou, "Allow edit?"), focusedSessionID: watched) == .notify)
        #expect(workspace.session(other)?.state == .needsYou)
        #expect(workspace.session(other)?.lastReport?.message == "Allow edit?")
        // Repeating it, or asking again while still waiting, doesn't notify again.
        #expect(workspace.report(other, hook(.needsYou, "Allow edit?"), focusedSessionID: watched) == .none)
        #expect(workspace.report(other, hook(.needsYou, "Allow bash?"), focusedSessionID: watched) == .none)
    }

    @Test func `needs you in the session you are looking at stays quiet`() {
        let fixture = Fixture()
        var workspace = fixture.workspace
        let watched = fixture.watched
        #expect(workspace.report(watched, hook(.needsYou), focusedSessionID: watched) == .none)
        #expect(workspace.session(watched)?.state == .needsYou)
    }

    @Test func `leaving needs you takes the notification back`() {
        let fixture = Fixture()
        var workspace = fixture.workspace
        let (watched, other) = (fixture.watched, fixture.other)
        workspace.report(other, hook(.needsYou), focusedSessionID: watched)
        #expect(workspace.report(other, hook(.working), focusedSessionID: watched) == .withdraw)
        #expect(workspace.session(other)?.state == .working)
    }

    @Test func `done and failed never interrupt and settle when seen`() {
        let fixture = Fixture()
        var workspace = fixture.workspace
        let (watched, other) = (fixture.watched, fixture.other)
        #expect(workspace.report(other, hook(.done, "All tests pass."), focusedSessionID: watched) == .none)
        #expect(workspace.session(other)?.state == .done)
        #expect(workspace.report(watched, hook(.failed), focusedSessionID: watched) == .none)
        #expect(workspace.session(watched)?.state == .idle)
        workspace.select(other)
        #expect(workspace.session(other)?.state == .idle)
        #expect(workspace.session(other)?.lastReport?.message == "All tests pass.")
    }

    @Test func `terminal guesses don't override hooks until the agent exits`() {
        let fixture = Fixture()
        var workspace = fixture.workspace
        let (watched, other) = (fixture.watched, fixture.other)
        workspace.report(other, hook(.working), focusedSessionID: watched)
        #expect(workspace.report(other, terminal(.needsYou), focusedSessionID: watched) == .none)
        #expect(workspace.session(other)?.state == .working)

        workspace.endAgentRun(other)
        #expect(workspace.session(other)?.state == .idle)
        #expect(workspace.report(other, terminal(.needsYou), focusedSessionID: watched) == .notify)
    }

    @Test func `waiting sessions are listed oldest first`() {
        let fixture = Fixture()
        var workspace = fixture.workspace
        let (watched, other) = (fixture.watched, fixture.other)
        workspace.report(
            other,
            StatusReport(state: .needsYou, source: .hook, date: Date(timeIntervalSince1970: 200)),
            focusedSessionID: nil,
        )
        workspace.report(
            watched,
            StatusReport(state: .needsYou, source: .hook, date: Date(timeIntervalSince1970: 100)),
            focusedSessionID: nil,
        )
        #expect(workspace.sessionsNeedingYou.map(\.id) == [watched, other])
    }

    @Test func `unknown sessions are ignored`() {
        let fixture = Fixture()
        var workspace = fixture.workspace
        let watched = fixture.watched
        #expect(workspace.report(UUID(), hook(.needsYou), focusedSessionID: watched) == .none)
    }

    @Test func `state names from hooks`() {
        #expect(SessionState(reportName: "needs-you") == .needsYou)
        #expect(SessionState(reportName: "NEEDS_YOU") == .needsYou)
        #expect(SessionState(reportName: "waiting") == .needsYou)
        #expect(SessionState(reportName: "stop") == .done)
        #expect(SessionState(reportName: "error") == .failed)
        #expect(SessionState(reportName: "busy") == .working)
        #expect(SessionState(reportName: "sleepy") == nil)
        for state in SessionState.allCases {
            #expect(SessionState(reportName: state.reportName) == state)
        }
    }

    @Test func `blank messages are dropped and reports survive saving`() throws {
        #expect(StatusReport(state: .done, message: "  \n", source: .hook).message == nil)
        let fixture = Fixture()
        var workspace = fixture.workspace
        let (watched, other) = (fixture.watched, fixture.other)
        workspace.report(other, hook(.needsYou, "Allow edit?"), focusedSessionID: watched)
        let decoded = try JSONDecoder().decode(Workspace.self, from: JSONEncoder().encode(workspace))
        #expect(decoded.session(other)?.lastReport?.message == "Allow edit?")
    }

    @Test func `older state files without reports still load`() throws {
        let json = """
        {"id": "6F9619FF-8B86-D011-B42D-00C04FC964FF", "projectID": "6F9619FF-8B86-D011-B42D-00C04FC964FE",
         "title": "", "workingDirectory": "/tmp", "isPinned": false, "state": "idle", "createdAt": 0}
        """
        let session = try JSONDecoder().decode(Session.self, from: Data(json.utf8))
        #expect(session.lastReport == nil)
    }
}

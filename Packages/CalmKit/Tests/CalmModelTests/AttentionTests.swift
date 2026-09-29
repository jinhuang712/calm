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

    @Test func `a state keeps the time it began, however often it's reported`() {
        let fixture = Fixture()
        var workspace = fixture.workspace
        let (watched, other) = (fixture.watched, fixture.other)
        let start = Date(timeIntervalSince1970: 1000)
        workspace.report(other, StatusReport(state: .working, source: .hook, date: start), focusedSessionID: watched)
        workspace.report(
            other,
            StatusReport(state: .working, message: "Reading files", source: .hook, date: start + 60),
            focusedSessionID: watched,
        )
        #expect(workspace.session(other)?.stateSince == start)
        workspace.report(other, StatusReport(state: .done, source: .hook, date: start + 120), focusedSessionID: watched)
        #expect(workspace.session(other)?.stateSince == start + 120)
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

    @Test func `done and failed never interrupt and settle once the user moves on`() {
        let fixture = Fixture()
        var workspace = fixture.workspace
        let (watched, other) = (fixture.watched, fixture.other)
        workspace.select(watched)
        #expect(workspace.report(other, hook(.done, "All tests pass."), focusedSessionID: watched) == .none)
        #expect(workspace.session(other)?.state == .done)
        // Finishing where the user is looking stays *failed* until they leave.
        #expect(workspace.report(watched, hook(.failed), focusedSessionID: watched) == .none)
        #expect(workspace.session(watched)?.state == .failed)

        // Arriving keeps *done* while it's read; leaving settles the session left behind.
        workspace.select(other)
        #expect(workspace.session(other)?.state == .done)
        #expect(workspace.session(watched)?.state == .idle)
        workspace.select(watched)
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

    @Test func `shells a turn leaves running show while it is done, and no longer`() {
        let fixture = Fixture()
        var workspace = fixture.workspace
        let (watched, other) = (fixture.watched, fixture.other)
        let start = Date(timeIntervalSince1970: 1000)
        func done(_ shells: Int, at date: Date) -> StatusReport {
            StatusReport(state: .done, message: "Built.", source: .hook, date: date, backgroundShells: shells)
        }
        workspace.report(other, done(2, at: start), focusedSessionID: watched)
        #expect(workspace.session(other)?.shellsStillRunning == 2)

        // The same words with fewer shells is news; the state keeps the time it began.
        workspace.report(other, done(1, at: start + 60), focusedSessionID: watched)
        #expect(workspace.session(other)?.shellsStillRunning == 1)
        #expect(workspace.session(other)?.stateSince == start)

        // Leaving the card settles it to idle, and the footnote goes with the state.
        workspace.select(other)
        workspace.select(watched)
        #expect(workspace.session(other)?.state == .idle)
        #expect(workspace.session(other)?.shellsStillRunning == 0)
    }

    @Test func `only a done hook report carries shells, and a new report clears them`() {
        let fixture = Fixture()
        var workspace = fixture.workspace
        let (watched, other) = (fixture.watched, fixture.other)
        workspace.report(other, StatusReport(state: .done, source: .hook, backgroundShells: 2), focusedSessionID: watched)
        workspace.report(other, hook(.working), focusedSessionID: watched)
        #expect(workspace.session(other)?.shellsStillRunning == 0)

        // A terminal guess isn't the agent speaking, so its count isn't shown.
        workspace.endAgentRun(other)
        workspace.report(other, StatusReport(state: .done, source: .terminal, backgroundShells: 3), focusedSessionID: watched)
        #expect(workspace.session(other)?.shellsStillRunning == 0)
        #expect(StatusReport(state: .done, source: .hook, backgroundShells: -4).backgroundShells == 0)
    }

    @Test func `the shell count is a snapshot and isn't saved`() throws {
        let fixture = Fixture()
        var workspace = fixture.workspace
        let (watched, other) = (fixture.watched, fixture.other)
        let report = StatusReport(state: .done, message: "Built.", source: .hook, backgroundShells: 2)
        workspace.report(other, report, focusedSessionID: watched)
        let decoded = try JSONDecoder().decode(Workspace.self, from: JSONEncoder().encode(workspace))
        #expect(decoded.session(other)?.state == .done)
        #expect(decoded.session(other)?.lastReport?.message == "Built.")
        #expect(decoded.session(other)?.shellsStillRunning == 0)
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

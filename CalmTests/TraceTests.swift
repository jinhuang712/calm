@testable import Calm
import CalmModel
import Foundation
import Testing

struct TraceTests {
    @Test func `an offset reads in seconds, to the hundredth`() {
        #expect(Trace.offset(.zero) == "+0.00")
        #expect(Trace.offset(.milliseconds(2114)) == "+2.11")
        #expect(Trace.offset(.milliseconds(99)) == "+0.10")
        #expect(Trace.offset(.seconds(125)) == "+125.00")
    }

    @Test func `a span reads in whole milliseconds`() {
        #expect(Trace.milliseconds(.milliseconds(12)) == "12 ms")
        #expect(Trace.milliseconds(.seconds(2)) == "2000 ms")
        #expect(Trace.milliseconds(.microseconds(400)) == "0 ms")
    }

    @Test func `what the launch pass found is described without the agent's words`() {
        let status = AgentLiveStatus(phase: .busy, since: Date())
        #expect(Trace.describe(AgentAtLaunch.gone) == "agent gone")
        #expect(Trace.describe(AgentAtLaunch.running(kind: .claudeCode, processID: 4242, status: status)) == "running as 4242, says busy")
        #expect(Trace.describe(AgentAtLaunch.running(kind: .claudeCode, processID: 4242, status: nil)) == "running as 4242, no status")
    }

    @Test func `a session is named by the first eight hex digits of its id`() throws {
        let id = try #require(UUID(uuidString: "68B8D9E3-05FF-4BF6-A9C0-9E167413981B"))
        #expect(Trace.id(id) == "68b8d9e3")
    }

    @Test func `a session is described by what its row shows`() {
        var session = Session(projectID: UUID(), workingDirectory: "/tmp", state: .working)
        #expect(Trace.describe(session) == "working, no agent")
        session.agent = AgentRun(kind: .claudeCode, processID: 42)
        #expect(Trace.describe(session) == "working, claudeCode")
        #expect(Trace.describe(nil) == "gone")
    }

    @Test func `a state that stayed is named once, one that moved shows both`() {
        #expect(Trace.transition(.working, .working) == "working")
        #expect(Trace.transition(.working, .idle) == "working → idle")
        #expect(Trace.transition(nil, .idle) == "gone → idle")
    }

    @Test func `a transcript tail is described by which fields it held, not what they said`() {
        #expect(Trace.fields(of: TranscriptTail()) == "nothing")
        let tail = TranscriptTail(
            title: "secret title", lastMessage: "secret recap", step: "secret step",
            progress: TodoProgress(done: 3, total: 5), interrupted: true,
        )
        #expect(Trace.fields(of: tail) == "title, recap, step, todos 3/5, interrupted")
        #expect(Trace.fields(of: TranscriptTail(turn: .inProgress)) == "turn inProgress")
    }

    @Test func `the trace never carries what an agent or the user wrote`() {
        // Titles and messages are the only free text a session holds; the description is built
        // from the state and the agent's name alone.
        var session = Session(projectID: UUID(), title: "secret title", workingDirectory: "/tmp/secret-folder")
        session.customName = "secret name"
        session.lastReport = StatusReport(state: .done, message: "secret message", source: .hook)
        #expect(!Trace.describe(session).contains("secret"))
    }
}

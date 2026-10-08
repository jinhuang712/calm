@testable import CalmModel
import Foundation
import Testing

struct LiveLineTests {
    private let start = Date(timeIntervalSinceReferenceDate: 800_000_000)

    private func at(_ seconds: TimeInterval) -> Date {
        start + seconds
    }

    private func read(_ file: String) -> ActivityChange {
        .began(AgentActivity("Reading \(file)", group: "Reading # files"))
    }

    private func run(_ words: String) -> ActivityChange {
        .began(AgentActivity(words, group: "Running # commands"))
    }

    @Test func `a turn starts thinking, and its first step shows once the hold is over`() {
        var line = LiveLine(thinkingAt: at(0))
        #expect(line.words(at: at(0)) == "Thinking")
        line.apply(run("Running swift test"), at: at(0.5))
        #expect(line.words(at: at(1.9)) == "Thinking")
        #expect(line.nextChange(after: at(0.5)) == at(2))
        #expect(line.words(at: at(2)) == "Running swift test")
    }

    @Test func `of several steps inside the hold, the latest shows`() {
        var line = LiveLine(thinkingAt: at(-10))
        line.apply(run("Running swift test"), at: at(0))
        line.apply(.began(AgentActivity("Editing UIUX.md", group: "Editing # files")), at: at(0.5))
        line.apply(.began(AgentActivity("Searching the web")), at: at(1))
        #expect(line.words(at: at(1.5)) == "Running swift test")
        #expect(line.words(at: at(2)) == "Searching the web")
    }

    @Test func `a burst of one kind adds up, each file once`() {
        var line = LiveLine(thinkingAt: at(-10))
        line.apply(read("Workspace.swift"), at: at(0))
        line.apply(read("SessionCard.swift"), at: at(0.05))
        line.apply(read("SessionCard.swift"), at: at(0.06))
        line.apply(read("LiveLine.swift"), at: at(0.1))
        #expect(line.words(at: at(0.1)) == "Reading Workspace.swift")
        #expect(line.words(at: at(2)) == "Reading 3 files")
    }

    @Test func `steps a hold apart are separate`() {
        var line = LiveLine(thinkingAt: at(-10))
        line.apply(read("Workspace.swift"), at: at(0))
        line.apply(.ended, at: at(0.1))
        line.apply(read("SessionCard.swift"), at: at(3))
        #expect(line.words(at: at(3)) == "Reading SessionCard.swift")
    }

    @Test func `once the last step has ended and nothing follows, the agent is thinking`() {
        var line = LiveLine(thinkingAt: at(-10))
        line.apply(run("Running swift test"), at: at(0))
        line.apply(.ended, at: at(1))
        #expect(line.words(at: at(15.9)) == "Running swift test")
        #expect(line.nextChange(after: at(1)) == at(16))
        #expect(line.words(at: at(16)) == "Thinking")
        #expect(line.nextChange(after: at(16)) == nil)
    }

    @Test func `a step still running never reads as quiet`() {
        // A test run beside a quick read: the read ends, the tests go on and send nothing.
        var line = LiveLine(thinkingAt: at(-10))
        line.apply(run("Running the full test suite"), at: at(0))
        line.apply(read("Package.swift"), at: at(0.5))
        line.apply(.ended, at: at(0.6))
        #expect(line.words(at: at(60)) == "Reading Package.swift")
        #expect(line.nextChange(after: at(60)) == nil)
        line.apply(.ended, at: at(70))
        #expect(line.words(at: at(85)) == "Thinking")
    }

    @Test func `after a question is answered, nothing counts as running`() {
        // A denied tool call never ends; the answer is what moves the turn on.
        var line = LiveLine(thinkingAt: at(-10))
        line.apply(run("Running rm -rf build"), at: at(0))
        line.resume(at: at(10))
        #expect(line.words(at: at(25)) == "Thinking")
    }

    @Test func `a new prompt mid-turn says thinking, after the hold`() {
        var line = LiveLine(thinkingAt: at(-10))
        line.apply(run("Running swift test"), at: at(0))
        line.apply(.thinking, at: at(1))
        #expect(line.words(at: at(1)) == "Running swift test")
        #expect(line.words(at: at(2)) == "Thinking")
    }

    @Test func `the change travels as names and comes back the same`() {
        let changes: [ActivityChange] = [read("A.swift"), .ended, .thinking]
        for change in changes {
            var words: String?
            var group: String?
            if case let .began(activity) = change {
                words = activity.words
                group = activity.group
            }
            #expect(ActivityChange(reportName: change.reportName, words: words, group: group) == change)
        }
        #expect(ActivityChange(reportName: "began", words: nil, group: nil) == nil)
        #expect(ActivityChange(reportName: "paused", words: nil, group: nil) == nil)
    }

    // MARK: The session

    private func workspace() -> (Workspace, Session.ID) {
        var workspace = Workspace()
        let id = workspace.newSession(in: "/tmp/a", gitRoot: { _ in nil }).id
        workspace.startAgentRun(id, AgentRun(kind: .claudeCode, processID: 1))
        return (workspace, id)
    }

    private func hook(_ state: SessionState, at seconds: TimeInterval, _ message: String? = nil) -> StatusReport {
        StatusReport(state: state, message: message, source: .hook, date: at(seconds))
    }

    @Test func `a turn runs from going to work to the end, through a question`() {
        var (workspace, id) = workspace()
        workspace.report(id, hook(.working, at: 0), focusedSessionID: nil)
        #expect(workspace.session(id)?.turnStartedAt == at(0))
        #expect(workspace.session(id)?.cornerDate == at(0))
        workspace.report(id, hook(.needsYou, at: 60, "Allow Bash: swift test"), focusedSessionID: nil)
        workspace.report(id, hook(.working, at: 90), focusedSessionID: nil)
        // Still the turn that began at 0: the corner counts it whole.
        #expect(workspace.session(id)?.turnStartedAt == at(0))
        #expect(workspace.session(id)?.cornerDate == at(0))
        workspace.report(id, hook(.done, at: 120, "Fixed."), focusedSessionID: nil)
        #expect(workspace.session(id)?.turnStartedAt == nil)
        // Done: the corner says when it finished.
        #expect(workspace.session(id)?.cornerDate == at(120))
    }

    @Test func `the line follows the hooks while working, and starts over with each turn`() {
        // What the manager does with each report: the state change, then the hook's change.
        var line = LiveLine.after(nil, from: .idle, to: .working, change: .thinking, at: at(0))
        line = LiveLine.after(line, from: .working, to: .working, change: read("SessionCard.swift"), at: at(3))
        #expect(line?.words(at: at(3)) == "Reading SessionCard.swift")
        // A question keeps the turn's line; the answer resumes it.
        line = LiveLine.after(line, from: .working, to: .needsYou, change: nil, at: at(4))
        #expect(line?.words(at: at(4)) == "Reading SessionCard.swift")
        line = LiveLine.after(line, from: .needsYou, to: .working, change: nil, at: at(9))
        #expect(line?.words(at: at(24)) == "Thinking")
        line = LiveLine.after(line, from: .working, to: .done, change: nil, at: at(30))
        #expect(line == nil)
        // Not working: nothing to show, so nothing is kept.
        #expect(LiveLine.after(nil, from: .done, to: .done, change: read("Workspace.swift"), at: at(31)) == nil)
        // A new turn starts over, even from a line left behind.
        let left = LiveLine(thinkingAt: at(0))
        #expect(LiveLine.after(left, from: .idle, to: .working, change: nil, at: at(40)) == nil)
        // Heard mid-turn, with no prompt before it (Calm started after it): the step shows at once.
        let midTurn = LiveLine.after(nil, from: .working, to: .working, change: read("LiveLine.swift"), at: at(41))
        #expect(midTurn?.words(at: at(41)) == "Reading LiveLine.swift")
        #expect(LiveLine.after(nil, from: .working, to: .working, change: .ended, at: at(42)) == nil)
    }

    @Test func `the words are Compacting while the agent compacts, else the line's, else Working`() {
        var (workspace, id) = workspace()
        workspace.report(id, hook(.working, at: 0), focusedSessionID: nil)
        let session = workspace.session(id)
        #expect(session?.liveWords(nil, at: at(1)) == "Working")
        #expect(session?.liveWords(LiveLine(thinkingAt: at(0)), at: at(1)) == "Thinking")
        workspace.report(
            id, StatusReport(state: .working, source: .hook, date: at(2), compaction: .started(.auto)), focusedSessionID: nil,
        )
        #expect(workspace.session(id)?.liveWords(LiveLine(thinkingAt: at(0)), at: at(3)) == "Compacting")
    }

    @Test func `a prompt after a question left unanswered starts a new turn`() {
        // Esc on a permission prompt sends no hook: the session still says needs you.
        var (workspace, id) = workspace()
        workspace.report(id, hook(.working, at: 0), focusedSessionID: nil)
        workspace.report(id, hook(.needsYou, at: 60, "Allow Bash: rm -rf build"), focusedSessionID: nil)
        workspace.report(id, hook(.working, at: 3600), focusedSessionID: nil, newTurn: true)
        #expect(workspace.session(id)?.turnStartedAt == at(3600))
        let left = LiveLine.after(nil, from: .idle, to: .working, change: read("Old.swift"), at: at(1))
        let line = LiveLine.after(left, from: .needsYou, to: .working, change: .thinking, at: at(3600))
        #expect(line?.words(at: at(3600)) == "Thinking")
    }

    @Test func `an agent that leaves ends its turn`() {
        var (workspace, id) = workspace()
        workspace.report(id, hook(.working, at: 0), focusedSessionID: nil)
        workspace.endAgentRun(id)
        #expect(workspace.session(id)?.turnStartedAt == nil)
    }

    @Test func `the todo line counts and names the step`() {
        var (workspace, id) = workspace()
        workspace.updateTranscriptTail(id, TranscriptTail(step: "Adding a regression test", progress: TodoProgress(done: 3, total: 5)))
        #expect(workspace.session(id)?.todoLine == "3 of 5 · Adding a regression test")
        workspace.updateTranscriptTail(id, TranscriptTail(progress: TodoProgress(done: 5, total: 5)))
        #expect(workspace.session(id)?.todoLine == "5 of 5")
        workspace.updateTranscriptTail(id, TranscriptTail(step: "Orphan step"))
        #expect(workspace.session(id)?.todoLine == nil)
    }

    @Test func `the turn's start is saved`() throws {
        var (workspace, id) = workspace()
        workspace.report(id, hook(.working, at: 0), focusedSessionID: nil)
        let session = try #require(workspace.session(id))
        let decoded = try JSONDecoder().decode(Session.self, from: JSONEncoder().encode(session))
        #expect(decoded.turnStartedAt == at(0))
    }
}

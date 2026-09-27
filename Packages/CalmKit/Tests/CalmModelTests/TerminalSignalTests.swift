@testable import CalmModel
import Testing

struct TerminalSignalTests {
    private func agentNotification(_ body: String, title: String = "") -> TerminalSignal.Outcome {
        TerminalSignal.notification(title: title, body: body).outcome(currentState: .working, hasAgent: true)
    }

    @Test func `agents' notifications are read by their words`() {
        // Messages seen from Claude Code, Codex and omp (DESIGNS.md → Agents).
        #expect(agentNotification("Claude needs your permission to use Bash") == .report(
            .needsYou,
            message: "Claude needs your permission to use Bash",
        ))
        #expect(agentNotification("Approval requested: rm -rf build") == .report(.needsYou, message: "Approval requested: rm -rf build"))
        #expect(agentNotification("Claude is waiting for your input") == .report(.done, message: "Claude is waiting for your input"))
        #expect(agentNotification("Waiting for input") == .report(.done, message: "Waiting for input"))
        #expect(agentNotification("Stopped with error") == .report(.failed, message: "Stopped with error"))
        #expect(agentNotification("Complete") == .report(.done, message: "Complete"))
        // A finished turn's last message, whatever it says, is not an ask.
        #expect(agentNotification("I updated the README and ran the tests.") == .report(
            .done,
            message: "I updated the README and ran the tests.",
        ))
        #expect(agentNotification("", title: "Allow edit?") == .report(.needsYou, message: "Allow edit?"))
    }

    @Test func `progress means working, and clearing it means done`() {
        #expect(TerminalSignal.progress(.active).outcome(currentState: .idle, hasAgent: true) == .report(.working, message: nil))
        #expect(TerminalSignal.progress(.active).outcome(currentState: .working, hasAgent: true) == .ignore)
        #expect(TerminalSignal.progress(.cleared).outcome(currentState: .working, hasAgent: true) == .report(.done, message: nil))
        #expect(TerminalSignal.progress(.cleared).outcome(currentState: .needsYou, hasAgent: true) == .ignore)
        #expect(TerminalSignal.progress(.cleared).outcome(currentState: .working, hasAgent: false) == .report(.idle, message: nil))
        #expect(TerminalSignal.progress(.error).outcome(currentState: .working, hasAgent: true) == .report(.failed, message: nil))
        #expect(TerminalSignal.progress(.paused).outcome(currentState: .working, hasAgent: true) == .ignore)
    }

    @Test func `a bell only counts from a working agent`() {
        #expect(TerminalSignal.bell.outcome(currentState: .working, hasAgent: true) == .report(.needsYou, message: nil))
        #expect(TerminalSignal.bell.outcome(currentState: .done, hasAgent: true) == .ignore)
        #expect(TerminalSignal.bell.outcome(currentState: .idle, hasAgent: false) == .ignore)
    }

    @Test func `plain shells pass notifications on and mark long commands`() {
        #expect(TerminalSignal.notification(title: "Build", body: "done")
            .outcome(currentState: .idle, hasAgent: false) == .notify("Build: done"))
        #expect(TerminalSignal.notification(title: "", body: "").outcome(currentState: .idle, hasAgent: false) == .ignore)
        let long = TerminalSignal.commandFinished(exitCode: 0, duration: 42)
        #expect(long.outcome(currentState: .idle, hasAgent: false) == .report(.done, message: "Finished after 42 s"))
        let failed = TerminalSignal.commandFinished(exitCode: 2, duration: 75)
        #expect(failed.outcome(currentState: .idle, hasAgent: false) == .report(.failed, message: "Exited with 2 after 1 min 15 s"))
        #expect(TerminalSignal.commandFinished(exitCode: 0, duration: 3).outcome(currentState: .idle, hasAgent: false) == .ignore)
        #expect(long.outcome(currentState: .working, hasAgent: true) == .ignore)
    }
}

@testable import Calm
import CalmAgents
import CalmModel
import Testing

/// What the title strip's update hint says and does (UIUX.md → Title bar).
struct AgentUpdateHintTests {
    private let update = AgentUpdate(installed: "2.1.291", running: "2.1.285")

    @Test func `an older agent names the version waiting, and a click restarts it`() throws {
        let hint = try #require(AgentUpdateHint(agent: .claudeCode, state: .idle, update: update, phase: nil, canRestart: true))
        #expect(hint.label == "Claude Code 2.1.291")
        #expect(hint.action == "Restart Claude Code")
        #expect(!hint.cancels)
        #expect(hint.help == "Claude Code 2.1.285 runs here; 2.1.291 is installed.")
    }

    @Test func `mid-turn the click waits for the turn to end`() throws {
        for state in [SessionState.working, .needsYou] {
            let hint = try #require(AgentUpdateHint(agent: .claudeCode, state: state, update: update, phase: nil, canRestart: true))
            #expect(hint.action == "Restart After This Turn")
        }
    }

    @Test func `a waiting restart can be taken back, and one under way can't be clicked`() throws {
        let waiting = try #require(AgentUpdateHint(
            agent: .claudeCode,
            state: .working,
            update: update,
            phase: .afterTurn,
            canRestart: true,
        ))
        #expect(waiting.label == "Restarts after this turn")
        #expect(waiting.action == "Don't Restart")
        #expect(waiting.cancels)
        let underway = try #require(AgentUpdateHint(agent: .claudeCode, state: .idle, update: nil, phase: .restarting, canRestart: true))
        #expect(underway.label == "Restarting…")
        #expect(underway.action == nil)
    }

    @Test func `an agent Calm doesn't restart is only told about`() throws {
        let codex = AgentUpdate(installed: "0.160.1", running: nil)
        let hint = try #require(AgentUpdateHint(agent: .codex, state: .idle, update: codex, phase: nil, canRestart: false))
        #expect(hint.label == "Codex 0.160.1")
        #expect(hint.action == nil)
        #expect(hint.help == "An older Codex runs here; 0.160.1 is installed. Quit it and start it again to use the new one.")
    }

    @Test func `with no version in its path it says updated, and with no news nothing`() throws {
        let unnamed = AgentUpdate(installed: nil, running: nil)
        let hint = try #require(AgentUpdateHint(agent: .openCode, state: .idle, update: unnamed, phase: nil, canRestart: false))
        #expect(hint.label == "OpenCode updated")
        #expect(AgentUpdateHint(agent: .claudeCode, state: .idle, update: nil, phase: nil, canRestart: true) == nil)
    }
}

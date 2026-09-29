@testable import Calm
import CalmAgents
import CalmModel
import Foundation
import Testing

@MainActor
struct LaunchPassTests {
    private func process(_ name: String, pid: Int32 = 4242) -> ProcessSnapshot {
        ProcessSnapshot(processID: pid, executablePath: "/usr/local/bin/\(name)", arguments: [name])
    }

    private let busy = AgentLiveStatus(phase: .busy, since: Date(timeIntervalSince1970: 1_800_000_000))

    // MARK: What the pass decides

    @Test func `the saved agent is still there when it has the shell's foreground`() {
        var asked: [Int32] = []
        let found = LaunchPass.outcome(.claudeCode, foreground: process("claude")) { pid in
            asked.append(pid)
            return busy
        }
        #expect(found == .running(kind: .claudeCode, processID: 4242, status: busy))
        // The agent's own status is asked for the process that has the foreground.
        #expect(asked == [4242])
    }

    @Test func `an agent that says nothing is still there`() {
        let found = LaunchPass.outcome(.claudeCode, foreground: process("claude")) { _ in nil }
        #expect(found == .running(kind: .claudeCode, processID: 4242, status: nil))
    }

    @Test func `nothing in the foreground, or another program, means the agent is gone`() {
        var asked = false
        let status: (Int32) -> AgentLiveStatus? = { _ in
            asked = true
            return nil
        }
        #expect(LaunchPass.outcome(.claudeCode, foreground: nil, status: status) == .gone)
        #expect(LaunchPass.outcome(.claudeCode, foreground: process("vim"), status: status) == .gone)
        // Another agent has it: that is not the saved run's agent.
        #expect(LaunchPass.outcome(.claudeCode, foreground: process("codex"), status: status) == .gone)
        #expect(!asked)
    }

    // MARK: What the manager does with it

    /// A manager over a saved workspace with one Claude Code session, working since a minute ago.
    private func manager(state: SessionState = .working) throws -> (manager: SessionManager, id: Session.ID) {
        var workspace = Workspace()
        let id = workspace.newSession(in: "/tmp/a", gitRoot: { _ in nil }).id
        workspace.startAgentRun(id, AgentRun(kind: .claudeCode, processID: 4242))
        workspace.report(id, StatusReport(state: state, source: .hook, date: Date().addingTimeInterval(-60)), focusedSessionID: nil)
        let file = FileManager.default.temporaryDirectory.appending(path: "calm-launch-\(UUID().uuidString).json")
        let store = WorkspaceStore(fileURL: file)
        try store.save(workspace)
        // Not `restore()`: it also ends zmx sessions that no saved session names.
        return (SessionManager(store: store), id)
    }

    private func answer(_ id: Session.ID, _ found: AgentAtLaunch) -> LaunchPass.Answer {
        LaunchPass.Answer(outcomes: [id: found], shells: [:])
    }

    @Test func `a saved run is still there when the manager loads`() throws {
        let (manager, id) = try manager()
        #expect(manager.workspace.session(id)?.agent?.kind == .claudeCode)
        #expect(manager.workspace.session(id)?.state == .working)
        #expect(manager.stateSavedAt != nil)
        #expect(manager.confirming.isEmpty)
    }

    @Test func `a run whose agent is still there is kept as it was`() throws {
        let (manager, id) = try manager()
        manager.settleSavedRuns(answer(id, .running(kind: .claudeCode, processID: 4242, status: busy)))
        #expect(manager.workspace.session(id)?.agent?.kind == .claudeCode)
        #expect(manager.workspace.session(id)?.state == .working)
    }

    @Test func `a run whose agent is gone ends`() throws {
        let (manager, id) = try manager()
        manager.settleSavedRuns(answer(id, .gone))
        #expect(manager.workspace.session(id)?.agent == nil)
        #expect(manager.workspace.session(id)?.state == .idle)
    }

    @Test func `with no answer every saved run ends, as a launch always made it`() throws {
        let (manager, id) = try manager()
        manager.settleSavedRuns(nil)
        #expect(manager.workspace.session(id)?.agent == nil)
        #expect(manager.workspace.session(id)?.state == .idle)
    }

    @Test func `rows show as loading until the answer is applied`() throws {
        let (manager, id) = try manager()
        manager.beginConfirming([id])
        #expect(manager.confirming == [id])
        // The saved row is untouched while it loads.
        #expect(manager.workspace.session(id)?.state == .working)
        #expect(manager.workspace.session(id)?.agent != nil)
        manager.settleSavedRuns(answer(id, .gone), animated: false)
        #expect(manager.confirming.isEmpty)
    }

    @Test func `a quick answer doesn't flash the loading state`() {
        let minimum = SessionManager.minimumLoading
        // Just shown: nearly all of it is still to run. Long shown: none.
        #expect(SessionManager.remainingLoading(shown: .milliseconds(10)) == minimum - .milliseconds(10))
        #expect(SessionManager.remainingLoading(shown: minimum) == .zero)
        #expect(SessionManager.remainingLoading(shown: .seconds(3)) == .zero)
    }
}

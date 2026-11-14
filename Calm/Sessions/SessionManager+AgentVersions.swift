import CalmAgents
import CalmModel
import Foundation

/// Whether a running agent is older than the one installed (specs/FEATURES.md → F12): the title strip's update hint.
extension SessionManager {
    /// Checks each running agent against the installed one (`AgentUpdates`), from the probe every
    /// few seconds. Off the main thread: a program whose path names no version (OpenCode) is asked
    /// with `--version`, once per file. Only a change is published, so the title strip and the
    /// menu redraw only for news.
    func checkAgentVersions() {
        guard !checkingVersions else { return }
        struct Running: Sendable {
            var id: Session.ID
            var processID: Int32
            var kind: AgentKind
        }
        let agents = workspace.sessions.compactMap { session -> Running? in
            guard let agent = session.agent, agent.processID > 0 else { return nil }
            return Running(id: session.id, processID: agent.processID, kind: agent.kind)
        }
        guard !agents.isEmpty else {
            agentUpdates = [:]
            runningVersions = [:]
            return
        }
        checkingVersions = true
        Task.detached(priority: .utility) { [weak self] in
            var updates: [Session.ID: AgentUpdate] = [:]
            var versions: [Session.ID: String] = [:]
            for agent in agents {
                guard let process = ProcessInspector.snapshot(of: agent.processID), Agents.detect(process) == agent.kind,
                      let found = AgentUpdates.check(process)
                else { continue }
                updates[agent.id] = found.update
                versions[agent.id] = found.running
            }
            await self?.publishVersions(updates: updates, versions: versions)
        }
    }

    private func publishVersions(updates: [Session.ID: AgentUpdate], versions: [Session.ID: String]) {
        checkingVersions = false
        if updates != agentUpdates {
            for (id, update) in updates where agentUpdates[id] != update {
                Trace.note("update \(Trace.id(id)): \(update.running ?? "?") → \(update.installed ?? "?")")
            }
            agentUpdates = updates
        }
        if versions != runningVersions {
            runningVersions = versions
        }
    }
}

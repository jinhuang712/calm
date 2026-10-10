import CalmAgents
import CalmModel
import Darwin
import Foundation

/// Where a restart stands (FEATURES.md → F12).
enum RestartPhase: Equatable {
    /// Waiting for the agent's turn to end: a restart now would cut the turn off, or drop the
    /// question it is waiting on you for.
    case afterTurn
    /// Asked to quit; the command that starts it again follows once it has.
    case restarting
}

/// Restarting an agent on its conversation (FEATURES.md → F12, DESIGNS.md → Agents → Restart):
/// after an update, so the session runs the new version and carries on where it was. The agent
/// is asked to quit with its adapter's signal; once its process is gone, the command that starts
/// it again with the same options on the same conversation is typed into its shell. The session's
/// menu, ⌘P and the title strip's update hint call it; nothing restarts by itself.
extension SessionManager {
    /// The agent that a restart would start again here: one running, whose conversation is known
    /// and whose adapter knows how to quit it.
    nonisolated static func restartableAgent(_ session: Session) -> AgentKind? {
        guard let agent = session.agent, agent.processID > 0, agent.conversation != nil,
              Agents.adapter(for: agent.kind)?.quit != nil
        else { return nil }
        return agent.kind
    }

    /// Mid-turn: working, or waiting on a question the agent asked.
    nonisolated static func isMidTurn(_ state: SessionState) -> Bool {
        state == .working || state == .needsYou
    }

    /// Restarts the agent in `id`: now, or once its turn ends. False when it can't be restarted.
    @discardableResult
    func requestRestart(_ id: Session.ID) -> Bool {
        guard let session = workspace.session(id), Self.restartableAgent(session) != nil else { return false }
        guard restarts[id] == nil else { return true }
        if Self.isMidTurn(session.state) {
            restarts[id] = .afterTurn
            Trace.note("restart \(Trace.id(id)): after this turn")
        } else {
            beginRestart(id)
        }
        return true
    }

    /// Takes back a restart that is still waiting for the turn to end.
    func cancelRestart(_ id: Session.ID) {
        guard restarts[id] == .afterTurn else { return }
        restarts[id] = nil
        Trace.note("restart \(Trace.id(id)): taken back")
    }

    /// The sessions a Restart All for `kind` would restart.
    func restartableSessions(_ kind: AgentKind) -> [Session] {
        workspace.sessions.filter { Self.restartableAgent($0) == kind }
    }

    /// Restarts every session running `kind`, the busy ones after their turn.
    func restartAll(_ kind: AgentKind) {
        for session in restartableSessions(kind) {
            requestRestart(session.id)
        }
    }

    /// Starts the restarts whose turn has ended, and forgets those whose agent has gone. Called
    /// when a state changes and from the probe.
    func runDueRestarts() {
        for (id, phase) in restarts where phase == .afterTurn {
            guard let session = workspace.session(id), session.agent != nil else {
                restarts[id] = nil
                continue
            }
            if !Self.isMidTurn(session.state) {
                beginRestart(id)
            }
        }
    }

    /// Asks the agent to quit, after reading how it was started (its argv is gone once it quits).
    private func beginRestart(_ id: Session.ID) {
        guard let agent = workspace.session(id)?.agent, let adapter = Agents.adapter(for: agent.kind),
              let quit = adapter.quit,
              let process = ProcessInspector.snapshot(of: agent.processID), Agents.detect(process) == agent.kind,
              let command = adapter.restartCommand(
                  arguments: process.commandLine, agentSessionID: agent.agentSessionID, transcriptPath: agent.transcriptPath ?? "",
              )
        else {
            restarts[id] = nil
            Trace.note("restart \(Trace.id(id)): no agent process or command, nothing done")
            return
        }
        restarts[id] = .restarting
        let processID = process.processID
        Trace.note("restart \(Trace.id(id)): asking pid \(processID) to quit")
        var presses = 0
        switch quit {
        case let .signal(signal):
            Darwin.kill(processID, signal)
        case .controlC:
            pressControlC(in: id)
            presses = 1
        }
        Task { [weak self] in
            // The agents take under a second (Claude Code 0.3 s, Codex 0.5 s a press). One still
            // there after 5 s isn't quitting: leave it be.
            let started = ContinuousClock.now
            var lastPress = started
            while ProcessInspector.snapshot(of: processID) != nil, ContinuousClock.now < started + .seconds(5) {
                try? await Task.sleep(for: .milliseconds(50))
                // Again while it hasn't quit: a draft takes a press of its own.
                if case let .controlC(times) = quit, presses < times, ContinuousClock.now - lastPress >= .milliseconds(500),
                   ProcessInspector.snapshot(of: processID) != nil {
                    self?.pressControlC(in: id)
                    presses += 1
                    lastPress = .now
                }
            }
            self?.finishRestart(id, quit: ProcessInspector.snapshot(of: processID) == nil, command: command)
        }
    }

    /// ⌃C in a session's terminal, as the keyboard sends it: through its pane, or as the raw byte
    /// through zmx for a session with no pane. Self-tests press it too: it reaches only the stand-in
    /// in their own terminal.
    private func pressControlC(in id: Session.ID) {
        if let pane = panes[id] {
            pane.pressControlC()
        } else if let session = workspace.session(id), persistenceEnabled {
            PersistentShell.send(name: session.persistentName, text: "\u{3}")
        }
        if Headless.isOn {
            FileHandle.standardError.write(Data("calm-selftest: pressed ⌃C in \(id)\n".utf8))
        }
    }

    private func finishRestart(_ id: Session.ID, quit: Bool, command: String) {
        guard quit, restarts[id] == .restarting, workspace.session(id) != nil else {
            if restarts[id] == .restarting {
                endRestart(id)
            }
            Trace.note("restart \(Trace.id(id)): the agent didn't quit, nothing typed")
            return
        }
        type(command, into: id)
        Trace.note("restart \(Trace.id(id)): typed the command")
        // The probe ends the phase when it sees the agent again. A command that failed (the agent
        // printed an error and exited) mustn't leave the strip saying "Restarting…".
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(10))
            if self?.restarts[id] == .restarting {
                self?.endRestart(id)
            }
        }
    }

    /// Types a command into a session's shell and presses Return: through its pane, or through
    /// zmx for a session not opened since launch, which has no pane yet. Headless self-tests log
    /// it instead: it would start the user's real agent, on their account.
    func type(_ command: String, into id: Session.ID) {
        if Headless.isOn {
            FileHandle.standardError.write(Data("calm-selftest: would run in \(id): \(command)\n".utf8))
            return
        }
        if let pane = panes[id] {
            pane.run(command)
        } else if let session = workspace.session(id), persistenceEnabled {
            PersistentShell.send(name: session.persistentName, text: command + "\r")
        }
    }

    // MARK: Resume after a lost shell

    /// A session whose shell went with an agent in it (the Mac restarted) resumes the
    /// conversation as it first opens (FEATURES.md → F3). The surface exists from the pane's
    /// start, so the command waits in the terminal's input until the new shell reads it, as
    /// ⌘⇧T's does.
    func resumeIfShellWasLost(_ id: Session.ID) {
        var conversation: AgentConversation?
        changeWorkspace { conversation = $0.takeConversationToResume(id) }
        guard let conversation else { return }
        scheduleSave()
        guard let command = Agents.adapter(for: conversation.kind)?.resumeCommand(for: conversation) else { return }
        Trace.note("pane \(Trace.id(id)): its shell was lost with \(conversation.kind.displayName) in it, resuming")
        type(command, into: id)
    }

    /// Resume from the session menu: the conversation resumes once, by the menu, not again as
    /// the session opens.
    func forgetResumeWhenOpened(_ id: Session.ID) {
        if changeWorkspace({ _ = $0.takeConversationToResume(id) }) {
            scheduleSave()
        }
    }

    // MARK: Updates

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

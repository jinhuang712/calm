import CalmAgents
import CalmModel
import Darwin
import Foundation
import SwiftUI

/// Restarting an agent on its conversation (specs/FEATURES.md → F12, DESIGNS.md → An agent is quit in the way it quits cleanly):
/// after an update, so the session runs the new version and carries on where it was. The agent
/// is asked to quit with its adapter's signal; once its process is gone, the command that starts
/// it again with the same options on the same conversation is typed into its shell. The session's
/// menu, ⌘P and the title strip's update hint call it; nothing restarts by itself. Each session's
/// phase is kept by `restarts` (`RestartTracker`), which this file and `foregroundChanged` drive.
extension SessionManager {
    /// How long after its command is typed a restart waits to see the agent again, before it
    /// gives the agent up as not coming back (`endRestart`).
    private static let comeBackPatience = Duration.seconds(10)
    /// The card's change when a run ends, as `foregroundChanged` makes it for an agent that exits.
    private static let runEnds = Animation.easeInOut(duration: 0.25)

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
        switch restarts.ask(id, midTurn: Self.isMidTurn(session.state)) {
        case .underWay:
            break
        case .waitsForTurn:
            Trace.note("restart \(Trace.id(id)): after this turn")
        case .startNow:
            beginRestart(id)
        }
        return true
    }

    /// Takes back a restart that is still waiting for the turn to end.
    func cancelRestart(_ id: Session.ID) {
        if restarts.takeBack(id) {
            Trace.note("restart \(Trace.id(id)): taken back")
        }
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
        for id in restarts.waiting {
            guard let session = workspace.session(id), session.agent != nil else {
                restarts.end(id)
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
            restarts.end(id)
            Trace.note("restart \(Trace.id(id)): no agent process or command, nothing done")
            return
        }
        restarts.quitting(id)
        let processID = process.processID
        Trace.note("restart \(Trace.id(id)): asking pid \(processID) to quit")
        Task { [weak self] in
            let didQuit = await quit.perform(
                processID: processID,
                isRunning: { ProcessInspector.snapshot(of: $0) != nil },
                signal: { _ = Darwin.kill($0, $1) },
                pressControlC: { self?.pressControlC(in: id) },
                clock: ContinuousClock(),
            )
            self?.finishRestart(id, quit: didQuit, command: command)
        }
    }

    /// A restart that didn't bring the agent back: its run ends as if it had exited, so the card
    /// doesn't go on showing an agent that isn't there.
    func endRestart(_ id: Session.ID) {
        restarts.end(id)
        guard let agent = workspace.session(id)?.agent, ProcessInspector.snapshot(of: agent.processID) == nil else { return }
        // `changeWorkspace` writes only a change, and ending a run is one, so this is the write it was.
        changeWorkspace(animation: Self.runEnds) { $0.endAgentRun(id) }
        Trace.note("restart \(Trace.id(id)): the agent didn't come back")
        scheduleSave()
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
            try? await Task.sleep(for: Self.comeBackPatience)
            if self?.restarts[id] == .restarting {
                self?.endRestart(id)
            }
        }
    }
}

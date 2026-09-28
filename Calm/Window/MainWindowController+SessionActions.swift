import AppKit
import CalmAgents
import CalmModel

/// Session actions (FEATURES.md → F12): rename a session, resume the conversation that ended in
/// it, fork a conversation into a new split or tab, each with the agent's own command.
extension MainWindowController {
    enum ForkDestination {
        case split, tab
    }

    /// The command that resumes the conversation that ended in `session`, if its agent has one.
    static func resumeCommand(for session: Session) -> String? {
        session.resumableConversation.flatMap(resumeCommand)
    }

    static func resumeCommand(for conversation: AgentConversation) -> String? {
        Agents.adapter(for: conversation.kind)?
            .resumeCommand(agentSessionID: conversation.agentSessionID, transcriptPath: conversation.transcriptPath ?? "")
    }

    /// The command that forks `session`'s conversation (running or ended), if its agent can.
    static func forkCommand(for session: Session) -> String? {
        guard let conversation = session.conversation else { return nil }
        return Agents.adapter(for: conversation.kind)?
            .forkCommand(agentSessionID: conversation.agentSessionID, transcriptPath: conversation.transcriptPath ?? "")
    }

    func rename(_ id: Session.ID, to name: String?) {
        manager.rename(id, to: name)
        sidebarEditing.renamingSessionID = nil
    }

    /// Resumes the conversation that ended in `id`, in the same shell.
    func resumeConversation(in id: Session.ID) {
        guard let session = manager.workspace.session(id), let command = Self.resumeCommand(for: session) else { return }
        select(id)
        runAgentCommand(command, in: manager.panes[id])
    }

    /// ⌘⇧T: opens the session closed last again, and resumes the conversation of the agent that was
    /// running in it. The shell is a new one: closing ended the old.
    func reopenClosedSession() {
        guard let (session, conversation) = manager.reopenClosedSession() else { return }
        hideSettings()
        showSelectedLayout(animated: true)
        if let command = conversation.flatMap(Self.resumeCommand) {
            runAgentCommand(command, in: manager.panes[session.id])
        }
    }

    /// Forks `id`'s conversation into a new split beside it or a new tab, in the same folder.
    func forkConversation(of id: Session.ID, into destination: ForkDestination) {
        guard let session = manager.workspace.session(id), let command = Self.forkCommand(for: session) else { return }
        select(id)
        let pane: TerminalSurfaceView?
        switch destination {
        case .split:
            pane = manager.panes[id].flatMap { split($0, direction: .right) }
        case .tab:
            let forked = manager.newSession(in: session.workingDirectory)
            showSelectedLayout(animated: true)
            pane = manager.panes[forked.id]
        }
        runAgentCommand(command, in: pane)
    }

    /// Types an agent's command into a pane. Headless self-tests log it instead: it would start
    /// the user's real agent, on their account.
    func runAgentCommand(_ command: String, in pane: TerminalSurfaceView?) {
        guard let pane else { return }
        if Headless.isOn {
            FileHandle.standardError.write(Data("calm-selftest: would run in \(pane.id): \(command)\n".utf8))
            return
        }
        pane.run(command)
    }
}

/// The sidebar's inline rename (UIUX.md → Session cards): which session's name is being edited.
@MainActor
@Observable
final class SidebarEditing {
    var renamingSessionID: Session.ID?
}

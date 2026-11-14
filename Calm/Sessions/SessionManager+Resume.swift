import CalmAgents
import CalmModel
import Foundation

/// Getting a conversation back by typing its command into a session's shell (specs/FEATURES.md → F3, F12).
/// A restart, a resume, a fork and ⌘⇧T all end in `type`.
extension SessionManager {
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

    /// A session whose shell went with an agent in it (the Mac restarted) resumes the
    /// conversation as it first opens (specs/FEATURES.md → F3). The surface exists from the pane's
    /// start, so the command waits for the new shell (`TerminalSurfaceView.run`), as ⌘⇧T's does.
    func resumeIfShellWasLost(_ id: Session.ID) {
        var conversation: AgentConversation?
        changeWorkspace { conversation = $0.takeConversationToResume(id) }
        guard let conversation else { return }
        scheduleSave()
        guard let command = Agents.adapter(for: conversation.kind)?.resumeCommand(for: conversation, settings: settings) else { return }
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
}

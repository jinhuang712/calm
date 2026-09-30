import CalmAgents
import CalmModel
import Foundation

/// Which of a session's actions apply to it (FEATURES.md → F12). The card's right-click menu and
/// the ⌘P palette both read it, so the two can't drift: the agent-backed actions appear only where
/// its agent has the command, and the copy and Finder ones only where there is something to give.
@MainActor
struct SessionActionSet {
    /// The agent whose ended conversation can be resumed in this shell.
    let resumes: AgentKind?
    let forks: Bool
    let copies: [SessionCopy]
    let opensFolder: Bool
    /// A scratch session can be kept as a project.
    let keepsAsProject: Bool
    /// The transcript file, when the agent keeps its conversation in one Calm can read (Claude
    /// Code, Codex, pi) and it is still there: the palette opens it, and copies the last reply
    /// from it. OpenCode keeps its sessions in a database, so it has none.
    let transcriptFile: String?

    init(_ session: Session) {
        resumes = MainWindowController.resumeCommand(for: session) != nil ? session.resumableConversation?.kind : nil
        forks = MainWindowController.forkCommand(for: session) != nil
        copies = SessionCopy.allCases.filter { $0.text(for: session) != nil }
        opensFolder = !session.isScratch && !copies.isEmpty
        keepsAsProject = session.isScratch
        transcriptFile = Self.transcriptFile(of: session)
    }

    private static func transcriptFile(of session: Session) -> String? {
        guard let conversation = session.conversation, let path = conversation.transcriptPath,
              Agents.transcriptReader(for: conversation.kind)?.readsLastReply == true,
              FileManager.default.fileExists(atPath: path)
        else { return nil }
        return path
    }
}

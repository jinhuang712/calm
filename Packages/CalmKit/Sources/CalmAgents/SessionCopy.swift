import CalmModel
import Foundation

/// What a session's menu can copy (FEATURES.md → F12): the agent's own id for the conversation,
/// the command that resumes it, and the folder. Nil where the session has nothing to give.
public enum SessionCopy: Sendable, CaseIterable {
    case sessionID, resumeCommand, folderPath

    public var menuTitle: String {
        switch self {
        case .sessionID: "Copy Session ID"
        case .resumeCommand: "Copy Resume Command"
        case .folderPath: "Copy Folder Path"
        }
    }

    /// The quiet note shown by the pointer once it's copied.
    public var copiedNote: String {
        switch self {
        case .sessionID: "Session ID copied"
        case .resumeCommand: "Command copied"
        case .folderPath: "Path copied"
        }
    }

    public func text(for session: Session) -> String? {
        switch self {
        case .sessionID:
            guard let conversation = session.conversation else { return nil }
            if let id = conversation.agentSessionID, !id.isEmpty {
                return id
            }
            // Claude Code names its transcript after the session, as its resume command relies on.
            guard conversation.kind == .claudeCode, let path = conversation.transcriptPath else { return nil }
            let id = URL(filePath: path).deletingPathExtension().lastPathComponent
            return id.isEmpty ? nil : id
        case .resumeCommand:
            guard let conversation = session.conversation else { return nil }
            return Agents.adapter(for: conversation.kind)?.resumeCommand(for: conversation)
        case .folderPath:
            // A scratch session's folder is Calm's business and never shown.
            return session.isScratch ? nil : session.workingDirectory
        }
    }
}

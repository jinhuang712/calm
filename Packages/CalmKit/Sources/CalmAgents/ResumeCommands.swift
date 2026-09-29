import CalmModel
import Foundation

// How each agent resumes a past session (DESIGNS.md → Agents, research of 2026-09-27) and forks
// one (research of 2026-09-28): for search results, and for a session card's menu (F12).

/// Single-quotes a value for the shell.
func shellQuoted(_ value: String) -> String {
    "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
}

public extension ClaudeCodeAdapter {
    func resumeCommand(agentSessionID: String?, transcriptPath: String) -> String? {
        let id = agentSessionID ?? URL(filePath: transcriptPath).deletingPathExtension().lastPathComponent
        return "claude --resume \(shellQuoted(id))"
    }

    /// A new session id, starting from a copy of the conversation.
    func forkCommand(agentSessionID: String?, transcriptPath: String) -> String? {
        resumeCommand(agentSessionID: agentSessionID, transcriptPath: transcriptPath).map { $0 + " --fork-session" }
    }
}

public extension CodexAdapter {
    func resumeCommand(agentSessionID: String?, transcriptPath _: String) -> String? {
        agentSessionID.map { "codex resume \(shellQuoted($0))" }
    }

    func forkCommand(agentSessionID: String?, transcriptPath _: String) -> String? {
        agentSessionID.map { "codex fork \(shellQuoted($0))" }
    }
}

public extension PiAdapter {
    /// pi takes a session file or id; the file is unambiguous.
    func resumeCommand(agentSessionID _: String?, transcriptPath: String) -> String? {
        "pi --session \(shellQuoted(transcriptPath))"
    }

    /// `--fork` takes a session file or id, like `--session`.
    func forkCommand(agentSessionID _: String?, transcriptPath: String) -> String? {
        "pi --fork \(shellQuoted(transcriptPath))"
    }
}

import CalmModel
import Foundation

// How each agent resumes a past session (DESIGNS.md → Agents, research of 2026-09-27), for
// search results whose session isn't open in Calm.

/// Single-quotes a value for the shell.
func shellQuoted(_ value: String) -> String {
    "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
}

public extension ClaudeCodeAdapter {
    func resumeCommand(agentSessionID: String?, transcriptPath: String) -> String? {
        let id = agentSessionID ?? URL(filePath: transcriptPath).deletingPathExtension().lastPathComponent
        return "claude --resume \(shellQuoted(id))"
    }
}

public extension CodexAdapter {
    func resumeCommand(agentSessionID: String?, transcriptPath _: String) -> String? {
        agentSessionID.map { "codex resume \(shellQuoted($0))" }
    }
}

public extension PiAdapter {
    /// pi takes a session file or id; the file is unambiguous.
    func resumeCommand(agentSessionID _: String?, transcriptPath: String) -> String? {
        "pi --session \(shellQuoted(transcriptPath))"
    }
}

public extension OmpAdapter {
    func resumeCommand(agentSessionID: String?, transcriptPath _: String) -> String? {
        agentSessionID.map { "omp --resume \(shellQuoted($0))" }
    }
}

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

public extension OpenCodeAdapter {
    /// `--session` continues a session by id (2.0.19's own TUI). An id OpenCode no longer has
    /// would start a new, empty session under it, so this is only for a conversation still there
    /// (search offers no resume for one that's gone).
    func resumeCommand(agentSessionID: String?, transcriptPath _: String) -> String? {
        agentSessionID.map { "opencode --session \(shellQuoted($0))" }
    }

    /// 2.0.19's TUI has no `--fork` flag (only `opencode mini` and `opencode run` do, and those
    /// aren't the interface the user works in), so the fork is made through OpenCode's own API,
    /// `session.fork`, which its `/fork` uses too, and the new session is opened in the TUI.
    /// `opencode api` prints `{"data":{"id":"ses_…",…}}` on one line (checked on 2.0.19 with the
    /// read-only `session.get`); awk takes the first `id` that is a session's, since macOS has
    /// no `jq` by default.
    func forkCommand(agentSessionID: String?, transcriptPath _: String) -> String? {
        agentSessionID.map { id in
            let firstSessionID = #"awk -F'"' '{for (i = 1; i < NF; i++) if ($i == "id" && $(i+2) ~ /^ses_/) {print $(i+2); exit}}'"#
            return "opencode --session \"$(opencode api session.fork --param sessionID=\(shellQuoted(id)) -d '{}' | \(firstSessionID))\""
        }
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

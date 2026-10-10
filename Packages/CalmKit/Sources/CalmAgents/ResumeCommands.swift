import CalmModel
import Foundation

// How each agent resumes a past session (DESIGNS.md → Agents, research of 2026-09-27) and forks
// one (research of 2026-09-28): for search results, and for a session card's menu (F12). Each
// takes the options the agent was started with (`resumeOptions`, in AgentRestart.swift), so a
// conversation started with `--dangerously-skip-permissions` comes back with it.

/// Single-quotes a value for the shell.
func shellQuoted(_ value: String) -> String {
    "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
}

public extension AgentAdapter {
    /// Without options: a conversation found in the agents' history (search, `calm show`), whose
    /// command line Calm never saw.
    func resumeCommand(agentSessionID: String?, transcriptPath: String) -> String? {
        resumeCommand(options: [], agentSessionID: agentSessionID, transcriptPath: transcriptPath)
    }

    func forkCommand(agentSessionID: String?, transcriptPath: String) -> String? {
        forkCommand(options: [], agentSessionID: agentSessionID, transcriptPath: transcriptPath)
    }

    /// Resumes `conversation` with the options its agent was started with.
    func resumeCommand(for conversation: AgentConversation) -> String? {
        resumeCommand(
            options: conversation.options ?? [], agentSessionID: conversation.agentSessionID,
            transcriptPath: conversation.transcriptPath ?? "",
        )
    }

    /// Forks `conversation` with the options its agent was started with, and `prompt` as the
    /// fork's first message when there is one.
    func forkCommand(for conversation: AgentConversation, prompt: String? = nil) -> String? {
        let options = conversation.options ?? []
        let transcript = conversation.transcriptPath ?? ""
        if let prompt {
            return forkCommand(options: options, agentSessionID: conversation.agentSessionID, transcriptPath: transcript, prompt: prompt)
        }
        return forkCommand(options: options, agentSessionID: conversation.agentSessionID, transcriptPath: transcript)
    }

    /// What a restart types once the agent quit: its resume, with the options read from the
    /// running process's argv (`arguments`).
    func restartCommand(arguments: [String], agentSessionID: String?, transcriptPath: String) -> String? {
        resumeOptions(commandLine: arguments)
            .flatMap { resumeCommand(options: $0, agentSessionID: agentSessionID, transcriptPath: transcriptPath) }
    }
}

public extension ClaudeCodeAdapter {
    /// `claude <options> --resume <id>`.
    func resumeCommand(options: [String], agentSessionID: String?, transcriptPath: String) -> String? {
        let id = agentSessionID ?? URL(filePath: transcriptPath).deletingPathExtension().lastPathComponent
        guard !id.isEmpty else { return nil }
        return (["claude"] + options.map(shellWord) + ["--resume", shellQuoted(id)]).joined(separator: " ")
    }

    /// A new session id, starting from a copy of the conversation.
    func forkCommand(options: [String], agentSessionID: String?, transcriptPath: String) -> String? {
        resumeCommand(options: options, agentSessionID: agentSessionID, transcriptPath: transcriptPath).map { $0 + " --fork-session" }
    }

    /// `claude [options] [prompt]` (2.1.285's `--help`): the prompt starts the forked session.
    func forkCommand(options: [String], agentSessionID: String?, transcriptPath: String, prompt: String) -> String? {
        forkCommand(options: options, agentSessionID: agentSessionID, transcriptPath: transcriptPath).map { $0 + " " + shellQuoted(prompt) }
    }

    /// Every record carries the `gitBranch` it was written on (seen in 2.1.x transcripts); the
    /// newest says where the conversation ended up.
    func branch(of transcript: URL) -> String? {
        for record in JSONLTail(transcript) {
            if let branch = record["gitBranch"] as? String, !branch.isEmpty {
                return branch
            }
        }
        return nil
    }
}

public extension CodexAdapter {
    /// `codex resume <options> <id>`: `resume` takes every option `codex` does.
    func resumeCommand(options: [String], agentSessionID: String?, transcriptPath _: String) -> String? {
        Self.command("resume", options, agentSessionID)
    }

    /// `codex fork <options> <id>`: `fork` takes the same options as `resume` (0.158's `--help`,
    /// `--yolo` included).
    func forkCommand(options: [String], agentSessionID: String?, transcriptPath _: String) -> String? {
        Self.command("fork", options, agentSessionID)
    }

    /// `codex fork [SESSION_ID] [PROMPT]` (0.159's `--help`).
    func forkCommand(options: [String], agentSessionID: String?, transcriptPath: String, prompt: String) -> String? {
        forkCommand(options: options, agentSessionID: agentSessionID, transcriptPath: transcriptPath).map { $0 + " " + shellQuoted(prompt) }
    }

    private static func command(_ subcommand: String, _ options: [String], _ id: String?) -> String? {
        guard let id, !id.isEmpty else { return nil }
        return (["codex", subcommand] + options.map(shellWord) + [shellQuoted(id)]).joined(separator: " ")
    }

    /// The rollout's first record, `session_meta`, has `payload.git.branch` (with `commit_hash`
    /// and `repository_url`; seen in 0.159's rollouts) for a session started in a repository.
    func branch(of transcript: URL) -> String? {
        guard let record = TranscriptDiscovery.firstRecord(of: transcript), record["type"] as? String == "session_meta",
              let git = (record["payload"] as? [String: Any])?["git"] as? [String: Any],
              let branch = git["branch"] as? String, !branch.isEmpty
        else { return nil }
        return branch
    }
}

public extension OpenCodeAdapter {
    /// `--session` continues a session by id (2.0.19's own TUI). An id OpenCode no longer has
    /// would start a new, empty session under it, so this is only for a conversation still there
    /// (search offers no resume for one that's gone).
    func resumeCommand(options: [String], agentSessionID: String?, transcriptPath _: String) -> String? {
        guard let id = agentSessionID, !id.isEmpty else { return nil }
        return Self.command(options, session: shellQuoted(id))
    }

    /// 2.0.19's TUI has no `--fork` flag (only `opencode mini` and `opencode run` do, and those
    /// aren't the interface the user works in), so the fork is made through OpenCode's own API,
    /// `session.fork`, which its `/fork` uses too, and the new session is opened in the TUI.
    /// `opencode api` prints `{"data":{"id":"ses_…",…}}` on one line (checked on 2.0.19 with the
    /// read-only `session.get`); awk takes the first `id` that is a session's, since macOS has
    /// no `jq` by default.
    func forkCommand(options: [String], agentSessionID: String?, transcriptPath _: String) -> String? {
        agentSessionID.map { id in
            let firstSessionID = #"awk -F'"' '{for (i = 1; i < NF; i++) if ($i == "id" && $(i+2) ~ /^ses_/) {print $(i+2); exit}}'"#
            let fork = "opencode api session.fork --param sessionID=\(shellQuoted(id)) -d '{}' | \(firstSessionID)"
            return Self.command(options, session: "\"$(\(fork))\"")
        }
    }

    /// `opencode <options> --session <session> [<folder>]`: the folder the options may end with
    /// (`resumeOptions` keeps it) goes last, as OpenCode's one positional argument.
    private static func command(_ options: [String], session: String) -> String {
        let (options, folder) = commandLine.split(options)
        return (["opencode"] + options.map(shellWord) + ["--session", session] + folder.prefix(1).map(shellWord))
            .joined(separator: " ")
    }
}

public extension PiAdapter {
    /// pi takes a session file or id; the file is unambiguous.
    func resumeCommand(options: [String], agentSessionID _: String?, transcriptPath: String) -> String? {
        guard !transcriptPath.isEmpty else { return nil }
        return (["pi"] + options.map(shellWord) + ["--session", shellQuoted(transcriptPath)]).joined(separator: " ")
    }

    /// `--fork` takes a session file or id, like `--session`.
    func forkCommand(options: [String], agentSessionID _: String?, transcriptPath: String) -> String? {
        guard !transcriptPath.isEmpty else { return nil }
        return (["pi"] + options.map(shellWord) + ["--fork", shellQuoted(transcriptPath)]).joined(separator: " ")
    }
}

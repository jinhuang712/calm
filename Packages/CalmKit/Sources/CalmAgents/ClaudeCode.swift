import CalmModel
import Foundation

/// Claude Code. Every install method runs the same native binary, whose file is named after
/// its version (`~/.local/share/claude/versions/2.1.283`), so the kernel's process name is the
/// version; argv[0] is `claude`. npm installs it as `@anthropic-ai/claude-code-darwin-arm64`.
public struct ClaudeCodeAdapter: AgentAdapter {
    public let kind = AgentKind.claudeCode
    public let commandNames: Set<String> = ["claude"]
    public let packagePaths = ["/@anthropic-ai/claude-code", "/share/claude/versions/"]
    public let helperSubcommands: Set<String> = ["daemon", "bg-pty-host", "bg-spare"]

    public init() {}
}

// MARK: Hooks

/// Claude Code's hooks (DESIGNS.md → Agents). Calm ships them as a plugin that Claude loads
/// from `CLAUDE_CODE_PLUGIN_DIRS`, set only in the shells Calm starts, so nothing is written to
/// the user's Claude settings.
extension ClaudeCodeAdapter: HookReporting {
    public var hookName: String {
        "claude-code"
    }

    /// The events Calm listens to, each running `calm hook claude-code` with the payload on stdin.
    public static let hookEvents = [
        "UserPromptSubmit", "PreToolUse", "PostToolUse", "PermissionRequest", "Notification", "Stop", "StopFailure",
        "PreCompact", "PostCompact",
    ]

    /// Payload fields (stdin JSON): `hook_event_name`, `session_id`, `transcript_path`, and per
    /// event `tool_name`/`tool_input`, `notification_type`/`message`, `last_assistant_message`
    /// and `background_tasks`, `error`/`error_details`, and for compaction `trigger` ("manual" for
    /// `/compact`, "auto"; captured from 2.1.291 on 2026-10-06).
    private struct Payload: Decodable {
        var hookEventName: String?
        var sessionId: String?
        var transcriptPath: String?
        var toolName: String?
        var toolInput: ToolInput?
        var notificationType: String?
        var message: String?
        var lastAssistantMessage: String?
        /// Stop only: work still in flight (shells, subagents, monitors…) that wakes Claude
        /// when it finishes. Missing on versions without it, which reads as none.
        var backgroundTasks: [BackgroundTask]?
        var error: String?
        var errorDetails: String?
        var trigger: String?

        struct ToolInput: Decodable {
            var command: String?
            var filePath: String?
            var description: String?
        }

        /// `id`, `description` and `command` are not read. Seen in captured payloads:
        /// `type` "shell" (a Monitor arrives as one too) and "subagent".
        struct BackgroundTask: Decodable {
            var type: String?
            var status: String?

            /// Ended tasks can stay in the list; a missing status reads as in flight, since
            /// the list is for work that will wake Claude.
            var isInFlight: Bool {
                guard let status = status?.lowercased() else { return true }
                return status == "running" || status == "pending"
            }

            /// Claude's own work, which ends and wakes it. Any other kind, including one Calm
            /// hasn't seen, counts as a shell: if that's wrong, the card says done, never
            /// a blue card that never clears.
            var isAgent: Bool {
                type?.lowercased() == "subagent"
            }
        }
    }

    /// How much of a reply a hook reads for its recap. The recap is the first 280 columns of what
    /// is left once code, tables and headings are dropped, and making it from a whole reply of a
    /// megabyte held the Stop hook, and so Claude, for most of a second (5 MB: 3 s). Only a reply
    /// that opens with this much code or table could lose words, and the transcript tail's recap
    /// reads it whole.
    static let recapSource = 32000

    public func hookReport(from payload: Data) -> HookReport? {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        guard let hook = try? decoder.decode(Payload.self, from: payload), let event = hook.hookEventName else { return nil }
        // `prose`: what Claude said (Markdown, made plain). The rest is Calm's own text or text
        // that quotes a command someone is asked to allow, and stays as it is.
        func report(
            _ state: SessionState, _ message: String? = nil, prose: Bool = false, shells: Int = 0, compaction: CompactionReport? = nil,
        ) -> HookReport {
            HookReport(
                state: state,
                message: prose ? MessageText.recap(message.map { String($0.prefix(Self.recapSource)) }) : HookReport.recap(message),
                agentSessionID: hook.sessionId,
                transcriptPath: hook.transcriptPath,
                backgroundShells: shells,
                compaction: compaction,
            )
        }
        // A trigger Calm doesn't know reads as Claude's own: that never ends the turn as done.
        let trigger = Compaction.Trigger(rawValue: hook.trigger ?? "") ?? .auto
        switch event {
        case "UserPromptSubmit", "PreToolUse", "PostToolUse":
            // After an approval the tool runs, so these also clear a *needs you*.
            return report(.working)
        case "PermissionRequest":
            let detail = hook.toolInput?.command ?? hook.toolInput?.filePath ?? hook.toolInput?.description
            let tool = hook.toolName ?? "a tool"
            return report(.needsYou, detail.map { "Allow \(tool): \($0)" } ?? "Allow \(tool)?")
        case "Notification":
            // Only questions and permission prompts; "waiting for your input" follows a finished turn.
            guard ["permission_prompt", "elicitation_dialog"].contains(hook.notificationType ?? "") else { return nil }
            return report(.needsYou, hook.message)
        case "Stop":
            // A turn that leaves one of Claude's own agents running isn't over: Claude picks up
            // again without you when it finishes, and its next Stop reports done. Shells are
            // different: a dev server or a monitor never ends, so the turn is over (the next
            // move is yours) and the card only says how many are still running.
            let running = (hook.backgroundTasks ?? []).filter(\.isInFlight)
            if running.contains(where: \.isAgent) {
                return report(.working, hook.lastAssistantMessage, prose: true)
            }
            return report(.done, hook.lastAssistantMessage, prose: true, shells: running.count)
        case "StopFailure":
            return report(.failed, hook.errorDetails ?? hook.error)
        case "PreCompact":
            // Claude summarizes the conversation to make room: busy for a minute or two (99 s at the
            // median in the author's history), with none of the turn's work. `/compact` sends no
            // UserPromptSubmit, so this is all that says the session is busy.
            return report(.working, compaction: .started(trigger))
        case "PostCompact":
            // A `/compact` you typed is over and waits for your next prompt (no Stop follows it);
            // one Claude began on its own goes back to the turn, whose Stop comes later. Esc
            // cancels a compaction with neither (the transcript tells, `Workspace`).
            if trigger == .manual {
                return report(.done, "Conversation compacted.", compaction: .ended(.manual))
            }
            return report(.working, compaction: .ended(trigger))
        default:
            return nil
        }
    }

    /// Where Calm writes the plugin, at each launch: its shells load it through
    /// `CLAUDE_CODE_PLUGIN_DIRS`, and `calm doctor` checks it's there.
    public static var pluginDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: "Calm/agents/claude-code")
    }

    /// The plugin's files: `.claude-plugin/plugin.json` and `hooks/hooks.json`. Hooks run
    /// synchronously so reports arrive in order; `calm hook` returns within a second at most.
    public static func pluginFiles() -> [String: String] {
        let command = #"[ -n "$CALM_CLI" ] && "$CALM_CLI" hook claude-code || true"#
        var hooks: [String: Any] = [:]
        for event in hookEvents {
            hooks[event] = [["hooks": [["type": "command", "command": command, "timeout": 5]]]]
        }
        let manifest: [String: Any] = [
            "name": "calm",
            "version": "1.0.0",
            "description": "Reports this session's state to Calm Terminal (only inside Calm).",
            "author": ["name": "Calm Terminal"],
        ]
        let hooksFile: [String: Any] = [
            "description": "Calm Terminal: session state for the sidebar and notifications.",
            "hooks": hooks,
        ]
        return [
            ".claude-plugin/plugin.json": json(manifest),
            "hooks/hooks.json": json(hooksFile),
        ]
    }

    private static func json(_ object: Any) -> String {
        let data = (try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])) ?? Data()
        return String(bytes: data, encoding: .utf8) ?? "{}"
    }
}

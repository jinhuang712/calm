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
    ]

    /// Payload fields (stdin JSON): `hook_event_name`, `session_id`, `transcript_path`, and per
    /// event `tool_name`/`tool_input`, `notification_type`/`message`, `last_assistant_message`
    /// and `background_tasks`, `error`/`error_details`.
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

        struct ToolInput: Decodable {
            var command: String?
            var filePath: String?
            var description: String?
        }

        /// Only its presence matters; `id`, `type`, `status`, `command`… are not read.
        struct BackgroundTask: Decodable {}
    }

    public func hookReport(from payload: Data) -> HookReport? {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        guard let hook = try? decoder.decode(Payload.self, from: payload), let event = hook.hookEventName else { return nil }
        // `prose`: what Claude said (Markdown, made plain). The rest is Calm's own text or text
        // that quotes a command someone is asked to allow, and stays as it is.
        func report(_ state: SessionState, _ message: String? = nil, prose: Bool = false) -> HookReport {
            HookReport(
                state: state,
                message: prose ? MessageText.recap(message) : HookReport.recap(message),
                agentSessionID: hook.sessionId,
                transcriptPath: hook.transcriptPath,
            )
        }
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
            // A turn that leaves background work running isn't over: Claude picks up again
            // without you when it finishes, and its next Stop reports done.
            let waiting = !(hook.backgroundTasks ?? []).isEmpty
            return report(waiting ? .working : .done, hook.lastAssistantMessage, prose: true)
        case "StopFailure":
            return report(.failed, hook.errorDetails ?? hook.error)
        default:
            return nil
        }
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

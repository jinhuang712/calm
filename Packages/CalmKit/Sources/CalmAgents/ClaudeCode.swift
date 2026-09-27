import CalmModel

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

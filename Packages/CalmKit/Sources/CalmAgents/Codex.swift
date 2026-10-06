import CalmModel

/// Codex CLI: a native binary, started directly or by the npm package's node launcher,
/// which runs a per-platform build such as `codex-aarch64-apple-darwin`.
///
/// No `sendKeys`: Codex's keymap knows only ctrl, alt and shift (0.159.0 and 0.160.1), and a ⌘ key
/// in its `config.toml` stops it from starting, so it keeps Return to send.
public struct CodexAdapter: AgentAdapter {
    public let kind = AgentKind.codex
    public let commandNames: Set<String> = ["codex"]
    public let commandPrefixes = ["codex-"]
    public let packagePaths = ["/@openai/codex/"]
    /// Background servers (used by the desktop apps), not sessions.
    public let helperSubcommands: Set<String> = ["app-server", "mcp-server"]

    public init() {}
}

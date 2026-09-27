import CalmModel

/// Codex CLI: a native binary, started directly or by the npm package's node launcher,
/// which runs a per-platform build such as `codex-aarch64-apple-darwin`.
public struct CodexAdapter: AgentAdapter {
    public let kind = AgentKind.codex
    public let commandNames: Set<String> = ["codex"]
    public let commandPrefixes = ["codex-"]
    public let packagePaths = ["/@openai/codex/"]
    /// Background servers (used by the desktop apps), not sessions.
    public let helperSubcommands: Set<String> = ["app-server", "mcp-server"]

    public init() {}
}

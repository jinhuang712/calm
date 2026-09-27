import CalmModel

/// Claude Code: the native `claude` binary, or the npm package run by node.
public struct ClaudeCodeAdapter: AgentAdapter {
    public let kind = AgentKind.claudeCode
    public let commandNames: Set<String> = ["claude"]
    public let packagePaths = ["/@anthropic-ai/claude-code/"]

    public init() {}
}

import CalmModel

/// OpenCode: a compiled binary, or the npm package's launcher.
public struct OpenCodeAdapter: AgentAdapter {
    public let kind = AgentKind.openCode
    public let commandNames: Set<String> = ["opencode", ".opencode"]
    public let packagePaths = ["/opencode-ai/", "/opencode/bin/"]

    public init() {}
}

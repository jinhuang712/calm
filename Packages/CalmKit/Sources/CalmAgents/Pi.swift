import CalmModel

/// pi (`@earendil-works/pi-coding-agent`): node running the package's CLI, which renames
/// itself `pi` (`process.title`), or a Bun-compiled `pi`.
public struct PiAdapter: AgentAdapter {
    public let kind = AgentKind.pi
    public let commandNames: Set<String> = ["pi"]
    public let packagePaths = ["/pi-coding-agent/"]

    public init() {}
}

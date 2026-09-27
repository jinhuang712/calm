import CalmModel

/// pi (pi-coding-agent): usually node running the package's `pi` script.
public struct PiAdapter: AgentAdapter {
    public let kind = AgentKind.pi
    public let commandNames: Set<String> = ["pi"]
    public let packagePaths = ["/pi-coding-agent/"]

    public init() {}
}

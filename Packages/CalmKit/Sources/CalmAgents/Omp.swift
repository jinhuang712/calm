import CalmModel

/// omp (oh-my-pi), a pi fork.
public struct OmpAdapter: AgentAdapter {
    public let kind = AgentKind.omp
    public let commandNames: Set<String> = ["omp"]
    public let packagePaths = ["/oh-my-pi/"]

    public init() {}
}

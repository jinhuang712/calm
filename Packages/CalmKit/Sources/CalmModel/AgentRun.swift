import Foundation

/// The coding agents Calm recognizes. Only an identifier: everything agent-specific lives in
/// that agent's adapter (CalmAgents).
public enum AgentKind: String, Codable, Sendable, CaseIterable {
    case claudeCode
    case codex
    case openCode
    case pi
    case omp

    public var displayName: String {
        switch self {
        case .claudeCode: "Claude Code"
        case .codex: "Codex"
        case .openCode: "OpenCode"
        case .pi: "pi"
        case .omp: "omp"
        }
    }
}

/// An agent running in the foreground of a session.
public struct AgentRun: Codable, Hashable, Sendable {
    public var kind: AgentKind
    /// The agent's process, while Calm is watching it (not meaningful after a relaunch).
    public var processID: Int32
    public var startedAt: Date

    public init(kind: AgentKind, processID: Int32, startedAt: Date = Date()) {
        self.kind = kind
        self.processID = processID
        self.startedAt = startedAt
    }
}

public extension Workspace {
    /// An agent took over the session's foreground (or a different one replaced it).
    mutating func startAgentRun(_ id: Session.ID, _ run: AgentRun) {
        guard let index = sessions.firstIndex(where: { $0.id == id }) else { return }
        if sessions[index].agent?.kind != run.kind || sessions[index].agent?.processID != run.processID {
            if sessions[index].agent != nil {
                endAgentRun(id)
            }
            sessions[index].agent = run
        }
    }
}

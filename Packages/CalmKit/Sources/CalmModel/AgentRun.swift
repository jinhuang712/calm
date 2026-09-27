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
    /// The agent's process, while Calm is watching it; 0 when only its hooks have spoken so far.
    public var processID: Int32
    public var startedAt: Date
    /// The agent's own session id and transcript file, from its hooks.
    public var agentSessionID: String?
    public var transcriptPath: String?

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
        // A run first heard of through its hooks gets its process once the probe sees it.
        if let existing = sessions[index].agent, existing.kind == run.kind, existing.processID == 0 || run.processID == 0 {
            sessions[index].agent?.processID = max(existing.processID, run.processID)
            return
        }
        if sessions[index].agent?.kind != run.kind || sessions[index].agent?.processID != run.processID {
            if sessions[index].agent != nil {
                endAgentRun(id)
            }
            sessions[index].agent = run
        }
    }

    /// Hooks tell which of the agent's sessions and transcripts this is.
    mutating func noteAgentSession(_ id: Session.ID, kind: AgentKind, agentSessionID: String?, transcriptPath: String?) {
        guard let index = sessions.firstIndex(where: { $0.id == id }) else { return }
        if sessions[index].agent?.kind != kind {
            startAgentRun(id, AgentRun(kind: kind, processID: 0))
        }
        if let agentSessionID {
            sessions[index].agent?.agentSessionID = agentSessionID
        }
        if let transcriptPath {
            sessions[index].agent?.transcriptPath = transcriptPath
        }
    }
}

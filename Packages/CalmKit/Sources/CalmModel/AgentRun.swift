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

/// "3 of 5 todos".
public struct TodoProgress: Codable, Hashable, Sendable {
    public var done: Int
    public var total: Int

    public init(done: Int, total: Int) {
        self.done = done
        self.total = total
    }
}

/// What the agent's transcript says right now (FEATURES.md → F2 session cards).
public struct TranscriptTail: Codable, Hashable, Sendable {
    /// The agent's own session title (e.g. set by `/rename`, or generated).
    public var title: String?
    /// The latest thing the agent said, cut for a recap.
    public var lastMessage: String?
    /// What it's doing now: the task in progress.
    public var step: String?
    public var progress: TodoProgress?
    /// The user interrupted the turn (no hook reports that).
    public var interrupted: Bool

    public init(
        title: String? = nil,
        lastMessage: String? = nil,
        step: String? = nil,
        progress: TodoProgress? = nil,
        interrupted: Bool = false,
    ) {
        self.title = title
        self.lastMessage = lastMessage
        self.step = step
        self.progress = progress
        self.interrupted = interrupted
    }
}

/// An agent running in the foreground of a session.
public struct AgentRun: Codable, Hashable, Sendable {
    public var kind: AgentKind
    /// The agent's process, while Calm is watching it; 0 when only its hooks have spoken so far.
    public var processID: Int32
    public var startedAt: Date
    /// The agent's own session id and transcript file, from its hooks or found from its process.
    public var agentSessionID: String?
    public var transcriptPath: String?
    /// The latest reading of its transcript.
    public var tail: TranscriptTail?

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

    /// A new reading of the agent's transcript. An interruption ends a *working* turn: agents'
    /// hooks don't report it.
    mutating func updateTranscriptTail(_ id: Session.ID, _ tail: TranscriptTail, readAt date: Date = Date()) {
        guard let index = sessions.firstIndex(where: { $0.id == id }), sessions[index].agent != nil else { return }
        sessions[index].agent?.tail = tail
        if tail.interrupted, sessions[index].state == .working {
            sessions[index].state = .idle
            sessions[index].lastReport = StatusReport(state: .idle, message: "Interrupted", source: .hook, date: date)
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

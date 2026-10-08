import Foundation

/// The coding agents Calm recognizes. Only an identifier: everything agent-specific lives in
/// that agent's adapter (CalmAgents).
public enum AgentKind: String, Codable, Sendable, CaseIterable {
    case claudeCode
    case codex
    case openCode
    case pi

    public var displayName: String {
        switch self {
        case .claudeCode: "Claude Code"
        case .codex: "Codex"
        case .openCode: "OpenCode"
        case .pi: "pi"
        }
    }

    /// The agent's name in config.toml keys (`agents.claude-code.hooks`) and `calm config` values.
    public var configName: String {
        switch self {
        case .claudeCode: "claude-code"
        case .codex: "codex"
        case .openCode: "opencode"
        case .pi: "pi"
        }
    }

    public init?(configName: String) {
        guard let kind = Self.allCases.first(where: { $0.configName == configName.lowercased() }) else { return nil }
        self = kind
    }
}

public extension AgentKind {
    /// Whether a report naming this agent speaks for a session whose terminal foreground is held
    /// by `foreground` right now.
    ///
    /// Whatever an agent starts inherits the session's `CALM_SESSION_ID`, so Claude Code running
    /// `pi -p` in its Bash tool makes pi's extension report as if the session were pi's. The
    /// agent in the foreground is the session's; another agent's report isn't about the session
    /// at all, its state included. Only a *different* agent, positively recognised, disproves a
    /// report. With nothing recognised (a wrapper script, a shell not probed yet) the report
    /// stands, as it always did.
    func speaksForSession(whileForeground foreground: AgentKind?) -> Bool {
        foreground == nil || foreground == self
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
/// Where an agent's newest turn stands, as its transcript says.
public enum TurnPhase: String, Codable, Sendable {
    /// Started and not ended.
    case inProgress
    case finished
    case failed
}

public struct TranscriptTail: Codable, Hashable, Sendable {
    /// The agent's own session title (e.g. set by `/rename`, or generated).
    public var title: String?
    /// The latest thing the agent said, cut for a recap.
    public var lastMessage: String?
    /// The agent's own summary of where the conversation stands and what's next (Claude Code's
    /// recap), only while nothing has been said since it was written. It's for a session you've
    /// read: what you need then is where you were, not the tail end of the last answer.
    public var summary: String?
    /// A turn began after `lastMessage` (a prompt, a slash command, a background task waking the
    /// agent), so that message belongs to an earlier one. Optional only so that a tail saved
    /// before it was added still decodes.
    public var newTurnSinceMessage: Bool?
    /// What it's doing now: the task in progress.
    public var step: String?
    public var progress: TodoProgress?
    /// The user interrupted the turn (no hook reports that).
    public var interrupted: Bool
    /// The folder the agent works in now, by its own account. It can move into a git worktree
    /// and out again while the shell that started it stays where it was.
    public var directory: String?
    /// Where the newest turn stands, for agents whose transcript says (nil: it doesn't, or the
    /// turn was interrupted). An agent with no hook or extension has no other way to tell Calm
    /// it is working.
    public var turn: TurnPhase?
    /// The conversation's size as the agent's latest reply saw it, in tokens (for agents whose
    /// transcript counts them): what a compaction starts from.
    public var contextTokens: Int?
    /// The newest compaction the transcript records, with the sizes it gives.
    public var lastCompaction: CompactedContext?
    /// When the newest message was written (the person's or the agent's, not bookkeeping): a
    /// message after a compaction began, with no record of it ending, means it was cancelled.
    public var newestMessageAt: Date?

    public init(
        title: String? = nil,
        lastMessage: String? = nil,
        summary: String? = nil,
        newTurnSinceMessage: Bool? = nil,
        step: String? = nil,
        progress: TodoProgress? = nil,
        interrupted: Bool = false,
        directory: String? = nil,
        turn: TurnPhase? = nil,
        contextTokens: Int? = nil,
        lastCompaction: CompactedContext? = nil,
        newestMessageAt: Date? = nil,
    ) {
        self.title = title
        self.lastMessage = lastMessage
        self.summary = summary
        self.newTurnSinceMessage = newTurnSinceMessage
        self.step = step
        self.progress = progress
        self.interrupted = interrupted
        self.directory = directory
        self.turn = turn
        self.contextTokens = contextTokens
        self.lastCompaction = lastCompaction
        self.newestMessageAt = newestMessageAt
    }

    /// The state a session should move to given what this reading says of the newest turn, or nil
    /// for no change. Only for agents that can't say it themselves, so:
    ///
    /// - An agent's own hook report outranks it, as it does a terminal signal.
    /// - A reading written before the latest report is stale: a desktop notification for the
    ///   finished turn may have come first (the same rule as for an interruption).
    /// - A turn in progress starts *working* from idle, done or failed, but never overrides a
    ///   pending *needs you*: an ask is made mid-turn and waits for the person.
    /// - A turn that ended (finished or failed) ends the work or the wait.
    public func stateChange(from state: SessionState, after report: StatusReport?, transcriptWritten: Date) -> SessionState? {
        guard let turn, report?.source != .hook else { return nil }
        if let reported = report?.date, transcriptWritten <= reported {
            return nil
        }
        switch (turn, state) {
        case (.inProgress, .idle), (.inProgress, .done), (.inProgress, .failed): return .working
        case (.finished, .working), (.finished, .needsYou): return .done
        case (.failed, .working), (.failed, .needsYou): return .failed
        default: return nil
        }
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

/// A past or running agent conversation, enough to resume or fork it with the agent's own
/// command (FEATURES.md → F12).
public struct AgentConversation: Codable, Hashable, Sendable {
    public var kind: AgentKind
    public var agentSessionID: String?
    public var transcriptPath: String?
    /// The agent's title for it, for menus.
    public var title: String?

    public init(kind: AgentKind, agentSessionID: String?, transcriptPath: String?, title: String? = nil) {
        self.kind = kind
        self.agentSessionID = agentSessionID
        self.transcriptPath = transcriptPath
        self.title = title
    }
}

public extension Session {
    /// Whether the agent running here is that conversation (a search result's transcript, or the
    /// agent's own id for it): opening the result goes to this session instead of resuming it anew.
    /// A conversation whose agent has exited isn't running, even while its session stays open.
    func runs(transcriptPath: String, agentSessionID: String?) -> Bool {
        guard let agent else { return false }
        return agent.transcriptPath == transcriptPath
            || agentSessionID != nil && agent.agentSessionID == agentSessionID
    }

    /// The recap a card and the arrival card show: what the agent asked while it waits for you;
    /// once you've read it (idle), the agent's own summary of where things stand, if it wrote one
    /// after its last message; otherwise the latest thing it said. A turn that hasn't said
    /// anything yet is no different from idle: its latest message is the last turn's, and under
    /// *working* it would read as this one's (an "API Error" from five hours before, seen
    /// 2026-10-09). A `/compact` that ended as *done* says so: the last thing the agent said
    /// came before it.
    var recap: String? {
        let tail = agent?.tail
        if state == .done, compaction?.trigger == .manual, compaction?.endedAt != nil, let message = lastReport?.message {
            return message
        }
        switch state {
        case .needsYou: return lastReport?.message ?? tail?.lastMessage
        case .working where tail?.newTurnSinceMessage == true, .idle:
            return tail?.summary ?? tail?.lastMessage ?? lastReport?.message
        case .working, .done, .failed: return tail?.lastMessage ?? lastReport?.message
        }
    }
}

public extension AgentRun {
    /// This run's conversation, once its id or transcript is known.
    var conversation: AgentConversation? {
        guard agentSessionID != nil || transcriptPath != nil else { return nil }
        return AgentConversation(kind: kind, agentSessionID: agentSessionID, transcriptPath: transcriptPath, title: tail?.title)
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
        noteCompactionInTranscript(index, tail, readAt: date)
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

public extension Workspace {
    /// Names a session (FEATURES.md → F12); an empty name gives it back its own title.
    mutating func rename(_ id: Session.ID, to name: String?) {
        guard let index = sessions.firstIndex(where: { $0.id == id }) else { return }
        let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        sessions[index].customName = trimmed.isEmpty ? nil : trimmed
    }
}

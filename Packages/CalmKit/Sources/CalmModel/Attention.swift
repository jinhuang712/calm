import Foundation

/// The latest word about a session: its state, what the agent last said, and who said so
/// (see DESIGNS.md → Attention).
public struct StatusReport: Codable, Hashable, Sendable {
    /// Hooks are the agent speaking for itself; terminal signals (bell, progress, titles) are
    /// Calm's guess. While an agent reports through hooks, guesses don't override it.
    public enum Source: String, Codable, Sendable {
        case hook
        case terminal
    }

    public var state: SessionState
    public var message: String?
    public var source: Source
    public var date: Date

    public init(state: SessionState, message: String? = nil, source: Source, date: Date = Date()) {
        self.state = state
        let trimmed = message?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.message = trimmed?.isEmpty == false ? trimmed : nil
        self.source = source
        self.date = date
    }
}

/// What the app should do after a report: nothing, notify the user, or take back a
/// notification that no longer applies.
public enum AttentionEffect: Equatable, Sendable {
    case none
    case notify
    case withdraw
}

public extension SessionState {
    /// Reads the state names agents' hooks pass to `calm status`. A few synonyms are accepted
    /// so hook scripts can use their agent's own words.
    init?(reportName: String) {
        switch reportName.lowercased().replacingOccurrences(of: "_", with: "-") {
        case "idle": self = .idle
        case "working", "busy", "running", "thinking": self = .working
        case "needs-you", "needsyou", "waiting", "input", "permission", "attention": self = .needsYou
        case "done", "finished", "complete", "completed", "stop", "stopped": self = .done
        case "failed", "error", "failure": self = .failed
        default: return nil
        }
    }

    /// The name `calm status` and the control protocol use.
    var reportName: String {
        switch self {
        case .idle: "idle"
        case .working: "working"
        case .needsYou: "needs-you"
        case .done: "done"
        case .failed: "failed"
        }
    }
}

public extension Workspace {
    /// Applies a report to a session. `focusedSessionID` is the session the user is looking at
    /// right now (nil when Calm isn't the active app).
    ///
    /// - The latest report wins, except that terminal guesses never override a hook report
    ///   from the same agent run.
    /// - Repeating the current state and message changes nothing.
    /// - *Needs you* in a session the user isn't looking at asks for a notification; leaving
    ///   *needs you* takes it back.
    /// - A session the user is looking at doesn't collect *done* or *failed*: they've seen it.
    @discardableResult
    mutating func report(_ id: Session.ID, _ report: StatusReport, focusedSessionID: Session.ID?) -> AttentionEffect {
        guard let index = sessions.firstIndex(where: { $0.id == id }) else { return .none }
        let previous = sessions[index]
        if report.source == .terminal, previous.lastReport?.source == .hook {
            return .none
        }
        let isFocused = id == focusedSessionID
        let newState = isFocused ? report.state.afterVisit() : report.state
        if previous.state == newState, previous.lastReport?.message == report.message,
           previous.lastReport?.source == report.source {
            return .none
        }
        sessions[index].state = newState
        sessions[index].lastReport = report

        if newState == .needsYou {
            return isFocused || previous.state == .needsYou ? .none : .notify
        }
        return previous.state == .needsYou ? .withdraw : .none
    }

    /// The agent in a session has exited. Hooks no longer speak for the session, so terminal
    /// signals count again; a run that ends mid-work leaves nothing to wait for.
    mutating func endAgentRun(_ id: Session.ID) {
        guard let index = sessions.firstIndex(where: { $0.id == id }) else { return }
        sessions[index].agent = nil
        sessions[index].lastReport?.source = .terminal
        if sessions[index].state == .working {
            sessions[index].state = .idle
        }
    }

    /// Sessions waiting for the user, oldest request first (for ⌘⇧A).
    var sessionsNeedingYou: [Session] {
        sessions
            .filter { $0.state == .needsYou }
            .sorted { ($0.lastReport?.date ?? .distantPast) < ($1.lastReport?.date ?? .distantPast) }
    }
}

import Foundation

/// Where a session's restart stands (specs/FEATURES.md → F12).
public enum RestartPhase: Sendable, Equatable {
    /// Waiting for the agent's turn to end: a restart now would cut the turn off, or drop the
    /// question it is waiting on you for.
    case afterTurn
    /// Asked to quit; the command that starts it again follows once it has.
    case restarting
}

/// Every session's restart phase, and the one place a phase changes. Each change is an event with
/// a name and one reason, so a reader sees why a restart began or ended without searching the
/// callers:
///
///     (none) ── ask, mid-turn ─────▶ afterTurn ── quitting ──▶ restarting ── agentBack ──▶ (none)
///     (none) ── ask, idle ─ quitting ─────────────────────────▶ restarting
///     afterTurn ── takeBack, agentExited, end ──▶ (none)
///     restarting ── end ──▶ (none)
///
/// It only keeps phases. Quitting the agent, typing the command and reading the process are
/// `SessionManager`'s (`SessionManager+Restart`).
public struct RestartTracker: Sendable, Equatable {
    private var phases: [Session.ID: RestartPhase]

    public init() {
        phases = [:]
    }

    /// True with no restart waiting or under way anywhere.
    public var isEmpty: Bool {
        phases.isEmpty
    }

    /// The session's phase, nil with no restart.
    public subscript(_ id: Session.ID) -> RestartPhase? {
        phases[id]
    }

    /// The sessions whose restart waits for a turn to end.
    public var waiting: [Session.ID] {
        phases.filter { $0.value == .afterTurn }.map(\.key)
    }

    /// What asking for a restart leads to.
    public enum Ask: Sendable, Equatable {
        /// One is waiting or under way already.
        case underWay
        /// The agent is mid-turn: the restart waits, and `waiting` lists the session.
        case waitsForTurn
        /// The agent is between turns: the caller starts the restart (`quitting` follows once it can).
        case startNow
    }

    /// A restart is asked for. `midTurn`: the agent works, or waits on a question it asked.
    public mutating func ask(_ id: Session.ID, midTurn: Bool) -> Ask {
        guard phases[id] == nil else { return .underWay }
        guard midTurn else { return .startNow }
        phases[id] = .afterTurn
        return .waitsForTurn
    }

    /// A waiting restart is taken back. False when none was waiting: one under way can't be.
    @discardableResult
    public mutating func takeBack(_ id: Session.ID) -> Bool {
        guard phases[id] == .afterTurn else { return false }
        phases[id] = nil
        return true
    }

    /// The agent was asked to quit, and the command that starts it again follows.
    public mutating func quitting(_ id: Session.ID) {
        phases[id] = .restarting
    }

    /// The agent is back: a restart under way is over. A waiting one is left as it is.
    public mutating func agentBack(_ id: Session.ID) {
        guard phases[id] == .restarting else { return }
        phases[id] = nil
    }

    /// The agent exited by itself, so a restart that waited has nothing to restart. One under
    /// way is left as it is: its agent exits on purpose, and its command follows.
    public mutating func agentExited(_ id: Session.ID) {
        guard phases[id] == .afterTurn else { return }
        phases[id] = nil
    }

    /// A restart that goes no further: it could not start, the agent did not quit or did not come
    /// back, or the session closed.
    public mutating func end(_ id: Session.ID) {
        phases[id] = nil
    }
}

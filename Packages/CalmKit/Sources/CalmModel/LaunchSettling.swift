import Foundation

/// What an agent says about itself right now, from a file the agent keeps for its own process
/// (Claude Code: `~/.claude/sessions/<pid>.json`). Undocumented and the agent's to change:
/// anything unexpected reads as "no status", never as an error.
public struct AgentLiveStatus: Sendable, Equatable {
    public enum Phase: Sendable, Equatable {
        case busy
        case idle
        /// The agent says it waits for something (a permission, a dialog). What that means for a
        /// session's row is left to hooks until each agent's wording has been seen.
        case waiting
    }

    public var phase: Phase
    /// When the agent last changed phase.
    public var since: Date

    public init(phase: Phase, since: Date) {
        self.phase = phase
        self.since = since
    }
}

/// What the launch pass found in a session whose saved state says an agent was running there
/// (DESIGNS.md → Launch).
public enum AgentAtLaunch: Sendable, Equatable {
    /// No agent has the shell's foreground any more: its process ended, the shell is gone, or
    /// another program is running.
    case gone
    /// The agent is still running as `processID`, and `status` is what it says about itself,
    /// if it can.
    case running(kind: AgentKind, processID: Int32, status: AgentLiveStatus?)
}

public extension Workspace {
    /// A state saved this recently was saved by a Restart, or close to one: little can have
    /// happened since. Older than this, a saved *working* is a guess.
    static let freshSavedState: TimeInterval = 30

    /// A report and the agent's own status may differ by this much and still agree about which
    /// came first: the agent writes its file and runs its hooks a moment apart.
    static let statusOrderTolerance: TimeInterval = 1

    /// Settles a session's saved agent run against what the launch pass found, so the sidebar
    /// opens as it was left and shows only what is still true.
    ///
    /// - The run is kept only while the same agent still runs as the same process (or its
    ///   process was not yet known). Otherwise it is over: the row loses its mark and *working*
    ///   becomes idle, as when any agent exits.
    /// - The agent's own status corrects the saved state, but only where it speaks after the
    ///   last report (hooks are otherwise the newer word): *working* while it says idle, idle,
    ///   done or failed while it says busy. *Needs you* is left to hooks.
    /// - With no status to ask, a saved *working* stands only if the state was saved moments
    ///   ago (`freshSavedState`); older, it is idle, as a launch always used to make it.
    mutating func settleSavedRun(_ id: Session.ID, found: AgentAtLaunch, savedAt: Date?, now: Date = Date()) {
        guard let index = sessions.firstIndex(where: { $0.id == id }), let saved = sessions[index].agent else { return }
        guard case let .running(kind, processID, status) = found,
              saved.kind == kind, saved.processID == 0 || saved.processID == processID
        else {
            endAgentRun(id)
            return
        }
        sessions[index].agent?.processID = processID
        let state = sessions[index].state
        guard let status else {
            if state == .working, !Self.isFresh(savedAt, now: now) {
                sessions[index].state = .idle
            }
            return
        }
        let reportedAt = sessions[index].lastReport?.date ?? .distantPast
        guard status.since >= reportedAt.addingTimeInterval(-Self.statusOrderTolerance) else { return }
        let corrected: SessionState? = switch (state, status.phase) {
        case (.working, .idle): .idle
        case (.idle, .busy), (.done, .busy), (.failed, .busy): .working
        default: nil
        }
        guard let corrected else { return }
        sessions[index].state = corrected
        sessions[index].stateSince = status.since
        sessions[index].lastReport = StatusReport(state: corrected, source: .hook, date: status.since)
    }

    private static func isFresh(_ savedAt: Date?, now: Date) -> Bool {
        guard let savedAt else { return false }
        return now.timeIntervalSince(savedAt) < freshSavedState
    }
}

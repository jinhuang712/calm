import AppKit
import CalmAgents
import CalmModel
import SwiftUI

/// What agents' hooks and programs' terminal signals tell the manager. Hooks mostly repeat
/// themselves, so each handler writes the workspace only when something changed
/// (`changeWorkspace`).
extension SessionManager {
    /// Applies a status report (from a hook or a terminal signal) and passes on what it means
    /// for notifications. The session's working line follows: the report's state change, then
    /// `activity` (from a hook), so a turn's first step lands on the line that turn started. The
    /// line lives outside the workspace (`LiveLineBox`): a tool call redraws its card, not the
    /// sidebar, and schedules no save.
    func report(_ id: Session.ID, _ report: StatusReport, activity: ActivityChange? = nil) {
        let previous = workspace.session(id)?.state
        var effect = AttentionEffect.none
        let changed = changeWorkspace(animation: .easeInOut(duration: 0.25)) {
            effect = $0.report(id, report, focusedSessionID: lookingAtSessionID, newTurn: activity == .thinking)
        }
        if let state = workspace.session(id)?.state, state != previous || activity != nil {
            let box = liveLine(for: id)
            box.set(LiveLine.after(box.line, from: previous, to: state, change: activity, at: report.date))
        }
        Trace.reported(id, report, before: previous, after: workspace.session(id)?.state)
        AttentionCenter.shared.apply(effect, for: id)
        // Opted in (Agents panel): a turn finishing or failing where you aren't looking notifies too.
        if settings.notifyStates == .all, let state = workspace.session(id)?.state, state != previous,
           state == .done || state == .failed, id != lookingAtSessionID {
            AttentionCenter.shared.notify(report.message, state: state, for: id)
        }
        // A restart that waited for this turn to end can go now.
        if !restarts.isEmpty {
            runDueRestarts()
        }
        if changed {
            scheduleSave()
        }
    }

    /// A hook that only moves the working line along, saying nothing of the state (a failed tool
    /// call): it counts only while the session works.
    func noteActivity(_ id: Session.ID, _ change: ActivityChange) {
        guard workspace.session(id)?.state == .working else { return }
        let box = liveLine(for: id)
        box.set(LiveLine.after(box.line, from: .working, to: .working, change: change, at: Date()))
    }

    /// A session's working line, for its card; made the first time it's asked for.
    func liveLine(for id: Session.ID) -> LiveLineBox {
        if let box = liveLines[id] {
            return box
        }
        let box = LiveLineBox()
        liveLines[id] = box
        return box
    }

    /// A program in the session signalled something (DESIGNS.md → Attention → fallback signals).
    /// Reports go in with source `terminal`, so an agent's hooks still outrank them.
    func terminalSignal(_ id: Session.ID, _ signal: TerminalSignal) {
        guard let session = workspace.session(id) else { return }
        switch signal.outcome(currentState: session.state, hasAgent: session.agent != nil) {
        case let .report(state, message):
            report(id, StatusReport(state: state, message: message, source: .terminal))
        case let .notify(message):
            if id != lookingAtSessionID {
                AttentionCenter.shared.notify(message, for: id)
            }
        case .ignore:
            break
        }
    }

    func noteAgentSession(_ id: Session.ID, kind: AgentKind, agentSessionID: String?, transcriptPath: String?) {
        let before = workspace.session(id)?.agent
        let changed = changeWorkspace {
            $0.noteAgentSession(id, kind: kind, agentSessionID: agentSessionID, transcriptPath: transcriptPath)
        }
        Trace.agentNamed(id, kind, before: before, after: workspace.session(id)?.agent)
        if changed {
            scheduleSave()
        }
    }
}

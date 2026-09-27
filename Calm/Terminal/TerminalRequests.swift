import CalmModel
import Foundation
import GhosttyKit

// libghostty's layout actions, translated into Calm's own terms here so that nothing outside
// Terminal needs GhosttyKit (AGENTS.md → module boundaries).

/// Where a pane asks focus to move.
enum PaneFocusTarget: Equatable {
    case previous
    case next
    case toward(SplitTree<UUID>.Direction)

    init?(_ value: ghostty_action_goto_split_e) {
        switch value {
        case GHOSTTY_GOTO_SPLIT_PREVIOUS: self = .previous
        case GHOSTTY_GOTO_SPLIT_NEXT: self = .next
        case GHOSTTY_GOTO_SPLIT_LEFT: self = .toward(.left)
        case GHOSTTY_GOTO_SPLIT_RIGHT: self = .toward(.right)
        case GHOSTTY_GOTO_SPLIT_UP: self = .toward(.up)
        case GHOSTTY_GOTO_SPLIT_DOWN: self = .toward(.down)
        default: return nil
        }
    }
}

/// Which session a pane asks for (Ghostty's tabs are Calm's sessions).
enum SessionTarget: Equatable {
    case previous
    case next
    case last
    /// Zero-based position in the sidebar.
    case position(Int)

    /// Ghostty numbers tabs from 1 (`goto_tab:1` is the first), with negative values for
    /// previous, next and last.
    init?(_ value: ghostty_action_goto_tab_e) {
        switch value {
        case GHOSTTY_GOTO_TAB_PREVIOUS: self = .previous
        case GHOSTTY_GOTO_TAB_NEXT: self = .next
        case GHOSTTY_GOTO_TAB_LAST: self = .last
        default:
            guard value.rawValue >= 1 else { return nil }
            self = .position(Int(value.rawValue) - 1)
        }
    }

    /// The index to select among `count` sessions, from `current`. Positions past the end
    /// go to the last session, as in Ghostty.
    func index(from current: Int, count: Int) -> Int? {
        guard count > 0 else { return nil }
        return switch self {
        case .previous: (current - 1 + count) % count
        case .next: (current + 1) % count
        case .last: count - 1
        case let .position(position): min(position, count - 1)
        }
    }
}

extension SplitTree<UUID>.Direction {
    init(_ value: ghostty_action_split_direction_e) {
        self = switch value {
        case GHOSTTY_SPLIT_DIRECTION_LEFT: .left
        case GHOSTTY_SPLIT_DIRECTION_UP: .up
        case GHOSTTY_SPLIT_DIRECTION_DOWN: .down
        default: .right
        }
    }

    init(_ value: ghostty_action_resize_split_direction_e) {
        self = switch value {
        case GHOSTTY_RESIZE_SPLIT_LEFT: .left
        case GHOSTTY_RESIZE_SPLIT_UP: .up
        case GHOSTTY_RESIZE_SPLIT_DOWN: .down
        default: .right
        }
    }
}

extension TerminalSignal.Progress {
    init?(_ state: ghostty_action_progress_report_state_e) {
        switch state {
        case GHOSTTY_PROGRESS_STATE_SET, GHOSTTY_PROGRESS_STATE_INDETERMINATE: self = .active
        case GHOSTTY_PROGRESS_STATE_PAUSE: self = .paused
        case GHOSTTY_PROGRESS_STATE_ERROR: self = .error
        case GHOSTTY_PROGRESS_STATE_REMOVE: self = .cleared
        default: return nil
        }
    }
}

extension TerminalSignal {
    /// The attention-relevant libghostty actions (bell, desktop notification, progress,
    /// command finished), or nil for any other action.
    init?(_ action: ghostty_action_s) {
        switch action.tag {
        case GHOSTTY_ACTION_RING_BELL:
            self = .bell
        case GHOSTTY_ACTION_DESKTOP_NOTIFICATION:
            let notification = action.action.desktop_notification
            self = .notification(
                title: notification.title.map { String(cString: $0) } ?? "",
                body: notification.body.map { String(cString: $0) } ?? "",
            )
        case GHOSTTY_ACTION_PROGRESS_REPORT:
            guard let progress = Progress(action.action.progress_report.state) else { return nil }
            self = .progress(progress)
        case GHOSTTY_ACTION_COMMAND_FINISHED:
            let finished = action.action.command_finished
            self = .commandFinished(
                exitCode: finished.exit_code < 0 ? nil : Int(finished.exit_code),
                duration: TimeInterval(finished.duration) / 1_000_000_000,
            )
        default:
            return nil
        }
    }
}

import Foundation

/// Whether the user has left Calm, read from which app comes to the front (FEATURES.md → F5).
/// Leaving settles the finished session on screen, as going to another session does. Only an
/// app with a Dock icon counts: a menu-bar tool that takes the front for a moment (a screenshot
/// tool, a clipboard manager, Spotlight) is used over Calm, not instead of it. Snipaste froze
/// the screen and took the front for a second, and the done card being read went idle under it
/// (2026-09-30). A stop at such a tool on the way to another app still counts as leaving.
public struct LeavingCalm: Sendable, Equatable {
    /// What Calm showed: the focused session and its state.
    public struct OnScreen: Sendable, Equatable {
        public var sessionID: Session.ID
        public var state: SessionState

        public init(sessionID: Session.ID, state: SessionState) {
            self.sessionID = sessionID
            self.state = state
        }
    }

    private enum Place: Sendable, Equatable {
        case calm
        /// A menu-bar tool is in front, with what Calm showed when it came.
        case aside(OnScreen?)
        case elsewhere
    }

    private var place: Place

    public init(calmIsActive: Bool) {
        place = calmIsActive ? .calm : .elsewhere
    }

    public mutating func calmCameForward() {
        place = .calm
    }

    /// Another app came to the front: `regular` when it has a Dock icon. `onScreen` is what Calm
    /// shows now. Returns what the user saw and has now left, to settle, or nil.
    public mutating func appCameForward(regular: Bool, onScreen: OnScreen?) -> OnScreen? {
        switch place {
        case .calm:
            guard regular else {
                place = .aside(onScreen)
                return nil
            }
            place = .elsewhere
            return onScreen
        case let .aside(before):
            guard regular else { return nil }
            place = .elsewhere
            // A session that finished while the tool was in front hasn't been seen.
            return before == onScreen ? before : nil
        case .elsewhere:
            return nil
        }
    }
}

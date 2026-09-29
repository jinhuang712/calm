import Foundation

/// What the main area shows while sessions are open but none is chosen, as after closing the one
/// on screen (UIUX.md → No session chosen).
public enum NoSessionContent: Equatable, Sendable {
    /// The sessions that wait for a look, so the one to pick up is in the middle of the screen.
    case waiting(Waiting)
    /// Nothing waits: search over past sessions and projects, as on the welcome page.
    case lists

    public struct Waiting: Equatable, Sendable {
        /// The sessions shown, first to last: questions before finished turns, the newest first.
        public var sessionIDs: [UUID]
        /// Waiting sessions left out past `shownLimit`; the sidebar has them.
        public var moreWaiting: Int
        public var stillWorking: Int

        public init(sessionIDs: [UUID], moreWaiting: Int, stillWorking: Int) {
            self.sessionIDs = sessionIDs
            self.moreWaiting = moreWaiting
            self.stillWorking = stillWorking
        }

        /// The card ↵ opens after the list changed: the one the keys were on while it's there,
        /// else the first.
        public func keeping(_ selected: UUID?) -> UUID? {
            selected.flatMap { sessionIDs.contains($0) ? $0 : nil } ?? sessionIDs.first
        }

        /// ↑ or ↓ from `selected`, stopping at either end.
        public func step(from selected: UUID?, by delta: Int) -> UUID? {
            guard let index = selected.flatMap({ sessionIDs.firstIndex(of: $0) }) else { return sessionIDs.first }
            return sessionIDs[max(0, min(sessionIDs.count - 1, index + delta))]
        }

        /// "2 more waiting · 5 still working", or nil when there's neither.
        public var footnote: String? {
            let parts = [
                moreWaiting > 0 ? "\(moreWaiting) more waiting" : nil,
                stillWorking > 0 ? "\(stillWorking) still working" : nil,
            ]
            let line = parts.compactMap(\.self).joined(separator: " · ")
            return line.isEmpty ? nil : line
        }
    }

    /// Enough cards to see what's waiting without the page becoming a second sidebar.
    public static let shownLimit = 3

    /// `current` is what the page shows now, and `searched` whether the user has typed in its
    /// search. Once they have, the lists stay until the page goes away: a session finishing
    /// meanwhile shows in the sidebar instead of swapping the page from under their keys.
    public static func choose(sessions: [Session], current: NoSessionContent?, searched: Bool) -> NoSessionContent {
        if current == .lists, searched {
            return .lists
        }
        let waiting = sessions
            .filter { SessionCardLayout.waitsForALook($0.state) }
            .sorted(by: comesFirst)
        guard !waiting.isEmpty else { return .lists }
        return .waiting(Waiting(
            sessionIDs: waiting.prefix(shownLimit).map(\.id),
            moreWaiting: max(0, waiting.count - shownLimit),
            stillWorking: sessions.count { $0.state == .working },
        ))
    }

    /// A question comes before a finished turn: it holds the agent up. Within each, the newest.
    private static func comesFirst(_ lhs: Session, _ rhs: Session) -> Bool {
        let (left, right) = (lhs.state == .needsYou, rhs.state == .needsYou)
        if left != right {
            return left
        }
        return since(lhs) > since(rhs)
    }

    private static func since(_ session: Session) -> Date {
        session.lastReport?.date ?? session.stateSince ?? session.createdAt
    }
}

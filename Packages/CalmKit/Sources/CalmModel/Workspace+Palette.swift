import Foundation

/// What the ⌘P palette does to the workspace (FEATURES.md → Command palette).
public extension Workspace {
    /// Folds or unfolds every group in the sidebar.
    mutating func setAllCollapsed(_ collapsed: Bool) {
        for index in projects.indices {
            projects[index].isCollapsed = collapsed
        }
    }

    /// Chooses no session, as closing the one in front does: the main area shows what waits for a
    /// look, or search. The session left settles, as when moving to another one.
    mutating func deselect() {
        guard let left = selectedLayout?.focusedSessionID else { return }
        settle(left)
        selectedLayoutID = nil
    }

    /// The sessions whose finished turn has been waiting for a look (*done*, not *failed*: a
    /// failure shouldn't go quiet without being seen), except `current`, which the user is in
    /// and which settles on its own when they leave.
    func sessionsDoneUnseen(except current: Session.ID?) -> [Session] {
        sessions.filter { $0.state == .done && $0.id != current }
    }

    /// Settles every finished session the user hasn't opened (`sessionsDoneUnseen`).
    @discardableResult
    mutating func markDoneSeen(except current: Session.ID?) -> [Session.ID] {
        let done = sessionsDoneUnseen(except: current).map(\.id)
        done.forEach { settle($0) }
        return done
    }

    /// Gives every pane of a split layout a layout of its own, in the order they had, so each is a
    /// session in the sidebar again. Nothing closes: each keeps its shell and its place in its
    /// group. When the layout was on screen, the session in focus stays on screen. Returns the
    /// new layouts (empty, and nothing changes, when the layout holds one session or isn't there).
    @discardableResult
    mutating func unsplit(_ layoutID: PaneLayout.ID) -> [PaneLayout] {
        guard let index = layouts.firstIndex(where: { $0.id == layoutID }) else { return [] }
        let original = layouts[index]
        let members = original.tree.leaves
        guard members.count > 1 else { return [] }
        // The focused session keeps the layout's identity, so whatever showed it keeps showing it.
        let apart = members.map { member in
            PaneLayout(
                id: member == original.focusedSessionID ? original.id : UUID(),
                tree: .leaf(member), focusedSessionID: member,
            )
        }
        layouts.replaceSubrange(index ... index, with: apart)
        return apart
    }
}

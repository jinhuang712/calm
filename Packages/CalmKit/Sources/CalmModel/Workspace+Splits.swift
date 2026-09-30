import Foundation

/// Sessions and the splits they're shown in (UIUX.md → Split panes). A split is only where
/// sessions are displayed together: bringing one in, or taking one out, ends nothing.
public extension Workspace {
    /// Puts an existing session on `direction`'s side of `target`, in `target`'s layout, and shows
    /// that layout with the joined session in focus. The session leaves the layout it was in; if
    /// that was its only pane the layout goes, and a split it leaves keeps the rest (the pane that
    /// takes its room has the focus). Returns false, changing nothing, for a session that isn't
    /// there or that is `target` itself.
    @discardableResult
    mutating func join(_ id: Session.ID, beside target: Session.ID, direction: SplitTree<Session.ID>.Direction) -> Bool {
        guard id != target, session(id) != nil, session(target) != nil,
              let targetLayout = layout(containing: target)?.id
        else { return false }
        if let focused = layouts.first(where: { $0.id == targetLayout })?.focusedSessionID, focused != id {
            settle(focused)
        }
        if let source = layout(containing: id)?.id, let sourceIndex = layouts.firstIndex(where: { $0.id == source }) {
            let neighbor = layouts[sourceIndex].tree.neighborAfterRemoving(id)
            if let remaining = layouts[sourceIndex].tree.removing(id) {
                layouts[sourceIndex].tree = remaining
                if layouts[sourceIndex].focusedSessionID == id, let neighbor {
                    layouts[sourceIndex].focusedSessionID = neighbor
                }
            } else {
                layouts.remove(at: sourceIndex)
            }
        }
        guard let index = layouts.firstIndex(where: { $0.id == targetLayout }) else { return false }
        layouts[index].tree = layouts[index].tree.splitting(target, direction: direction, with: id)
        layouts[index].focusedSessionID = id
        selectedLayoutID = targetLayout
        reveal(id)
        return true
    }

    /// Takes a pane out of its split: the session gets a layout of its own, the others close up
    /// around the gap and stay on screen, and the focus, if it was on the pane, goes to the pane
    /// that took its room. Returns false for a pane that is alone.
    @discardableResult
    mutating func takeOut(_ id: Session.ID) -> Bool {
        guard let index = layouts.firstIndex(where: { $0.tree.contains(id) }), layouts[index].tree.leaves.count > 1,
              let remaining = layouts[index].tree.removing(id)
        else { return false }
        let neighbor = layouts[index].tree.neighborAfterRemoving(id)
        layouts[index].tree = remaining
        if layouts[index].focusedSessionID == id, let neighbor {
            layouts[index].focusedSessionID = neighbor
        }
        layouts.append(PaneLayout(tree: .leaf(id), focusedSessionID: id))
        return true
    }

    /// Undoes a split entirely: the pane in focus stays on the layout, every other gets one of its
    /// own. Returns the sessions let go, in reading order; none for a layout of one.
    @discardableResult
    mutating func unsplit(_ layoutID: PaneLayout.ID) -> [Session.ID] {
        guard let index = layouts.firstIndex(where: { $0.id == layoutID }), layouts[index].tree.leaves.count > 1 else { return [] }
        let kept = layouts[index].focusedSessionID
        let freed = layouts[index].tree.leaves.filter { $0 != kept }
        layouts[index].tree = .leaf(kept)
        layouts.append(contentsOf: freed.map { PaneLayout(tree: .leaf($0), focusedSessionID: $0) })
        return freed
    }

    /// The sessions on screen together: every pane of the layout shown, while it has more than
    /// one. The sidebar lifts their rows; a lone session has nothing to say beyond its ring.
    var sessionsInView: Set<Session.ID> {
        guard let leaves = selectedLayout?.tree.leaves, leaves.count > 1 else { return [] }
        return Set(leaves)
    }
}

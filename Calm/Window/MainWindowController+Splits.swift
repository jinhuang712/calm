import AppKit
import CalmModel

/// Getting into a split and out of one (UIUX.md → Split panes). A split is only where sessions are
/// shown together, so bringing one in or taking one out ends nothing: the pane's view moves to
/// another workspace, or to one of its own, and its shell runs on.
extension MainWindowController {
    /// How many panes the layout on screen has; two or more is a split.
    var splitPaneCount: Int {
        manager.workspace.selectedLayout?.tree.leaves.count ?? 0
    }

    var isInSplit: Bool {
        splitPaneCount > 1
    }

    // MARK: Moves

    /// Puts session `id` on `direction`'s side of `target`, in `target`'s layout, and shows it in
    /// focus. The session may come from another layout (which goes if it was the only pane there)
    /// or from this split, where it moves.
    func joinSession(_ id: Session.ID, beside target: Session.ID, direction: SplitTree<Session.ID>.Direction) {
        let model = manager.workspace
        guard id != target, model.session(id) != nil, let destination = model.layout(containing: target) else { return }
        closePrompt.dismiss()
        let shown = model.selectedLayoutID
        let source = model.layout(containing: id)
        // The pane leaves the workspace it was in first, which closes the gap there.
        if let source, let pane = manager.panes[id] {
            workspaces[source.id]?.detach(pane)
        }
        guard manager.joinSession(id, beside: target, direction: direction) else { return }
        if let source, !manager.workspace.layouts.contains(where: { $0.id == source.id }) {
            workspaces[source.id]?.removeFromSuperview()
            workspaces[source.id] = nil
        }
        if let workspace = workspaces[destination.id], let targetPane = manager.panes[target],
           let pane = manager.pane(for: id, host: self) {
            workspace.split(targetPane, direction: direction, with: pane)
        } else if let layout = manager.workspace.layouts.first(where: { $0.id == destination.id }) {
            // Not built yet (nothing has shown it): it is made with the joined session in it.
            workspaces[destination.id]?.removeFromSuperview()
            workspaces[destination.id] = nil
            makeWorkspace(for: layout)
        }
        showSelectedLayout(animated: manager.workspace.selectedLayoutID != shown)
    }

    /// Takes a pane out of its split: its session is on its own in the sidebar, the others close up
    /// around the gap and stay on screen, and nothing ends.
    func takeOutPane(_ id: Session.ID) {
        guard let layout = manager.workspace.layout(containing: id), layout.tree.leaves.count > 1 else { return }
        closePrompt.dismiss()
        if let pane = manager.panes[id] {
            workspaces[layout.id]?.detach(pane)
        }
        guard manager.takeOutSession(id), let own = manager.workspace.layout(containing: id) else { return }
        // Built at once, hidden, like any layout not on screen: a pane with no view would stop
        // knowing whether it can be seen.
        makeWorkspace(for: own)
        showSelectedLayout(animated: false)
    }

    func takeOutFocusedPane() {
        if let id = manager.workspace.selectedLayout?.focusedSessionID {
            takeOutPane(id)
        }
    }

    // MARK: The workspace's end of it

    /// Hooks a workspace's icons and its drops up to this window.
    func wireSplitInteractions(_ view: TerminalWorkspaceView) {
        view.onSessionDrop = { [weak self] drag, target, direction in
            guard let self, manager.workspace.session(drag.sessionID) != nil else { return false }
            joinSession(drag.sessionID, beside: target, direction: direction)
            return true
        }
        view.onHandleClick = { [weak self] id, handle in self?.showSplitMenu(for: id, at: handle) }
        view.onHandleDrag = { [weak self] id in self?.splitDragItem(for: id) }
        view.onHandleDragMoved = { [weak self] id, point in self?.paneDragMoved(id, to: point) }
        view.onHandleDragEnded = { [weak self] id in
            guard let layout = self?.manager.workspace.layout(containing: id) else { return }
            self?.workspaces[layout.id]?.setLeaving(nil)
        }
    }

    /// What the pane's icon carries when it is dragged: the session, on a card of its own.
    private func splitDragItem(for id: Session.ID) -> NSDraggingItem? {
        guard let session = manager.workspace.session(id), isInSplit else { return nil }
        let drag = SessionDrag(origin: .pane, sessionID: id)
        ActiveSessionDrag.current = drag
        let pasteboardItem = NSPasteboardItem()
        pasteboardItem.setString(drag.text, forType: TerminalWorkspaceView.sessionDragType)
        let item = NSDraggingItem(pasteboardWriter: pasteboardItem)
        if let image = SessionDragCard.image(of: session, style: sidebarStyle, scale: window?.backingScaleFactor ?? 2) {
            // The pointer is over the card's left end, where its mark is.
            item.setDraggingFrame(NSRect(x: -18, y: -12, width: image.size.width, height: image.size.height), contents: image)
        }
        return item
    }

    /// While the icon is over the sidebar, letting go takes the pane out: it all but goes.
    private func paneDragMoved(_ id: Session.ID, to screenPoint: NSPoint) {
        guard let layout = manager.workspace.layout(containing: id), let workspace = workspaces[layout.id],
              let sidebar = sidebarHost, let window, (sidebarWidth?.constant ?? 0) > 0
        else { return }
        let frame = window.convertToScreen(sidebar.convert(sidebar.bounds, to: nil))
        workspace.setLeaving(frame.contains(screenPoint) ? id : nil)
    }

    // MARK: The icon's menu

    /// The menu under a pane's icon (`SplitMenu`). Clicking the icon first puts the focus on its
    /// pane, so Zoom and Equalize, which act on the focused pane, act on the one it belongs to.
    func splitMenu(for id: Session.ID) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        let zoomed = selectedWorkspace?.zoomedPane != nil
        for row in SplitMenu.rows(paneCount: splitPaneCount, zoomed: zoomed) {
            switch row {
            case .takeOut:
                menu.addItem(item("Take Out of Split", #selector(takeOutFromMenu(_:)), id))
            case .unsplitAll:
                menu.addItem(item("Unsplit All", #selector(unsplitFromMenu(_:)), id))
            case .separator:
                menu.addItem(.separator())
            case let .zoom(zoomed):
                menu.addItem(terminalItem(
                    zoomed ? "Show All Panes" : "Zoom Pane",
                    "toggle_split_zoom",
                    key: "\r",
                    mods: [.command, .shift],
                ))
            case .equalize:
                menu.addItem(terminalItem("Equalize Splits", "equalize_splits", key: "=", mods: [.command, .control]))
            }
        }
        return menu
    }

    private func item(_ title: String, _ action: Selector, _ id: Session.ID) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        item.representedObject = id
        return item
    }

    private func terminalItem(_ title: String, _ action: String, key: String, mods: NSEvent.ModifierFlags) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: #selector(TerminalMenuTarget.performTerminalAction(_:)), keyEquivalent: key)
        item.keyEquivalentModifierMask = mods
        item.representedObject = action
        item.target = TerminalMenuTarget.shared
        return item
    }

    private func showSplitMenu(for id: Session.ID, at handle: NSView) {
        if let pane = manager.panes[id], window?.firstResponder !== pane {
            window?.makeFirstResponder(pane)
        }
        splitMenu(for: id).popUp(positioning: nil, at: NSPoint(x: 0, y: handle.bounds.maxY + 4), in: handle)
    }

    @objc private func takeOutFromMenu(_ sender: NSMenuItem) {
        if let id = sender.representedObject as? Session.ID {
            takeOutPane(id)
        }
    }

    @objc private func unsplitFromMenu(_: NSMenuItem) {
        unsplit()
    }
}

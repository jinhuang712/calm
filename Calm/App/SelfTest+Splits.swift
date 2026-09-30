#if DEBUG
    import AppKit
    import CalmModel

    /// Self-test drivers for getting into and out of a split (UIUX.md → Split panes). A headless
    /// run can't drag or hover, so each of these does what the pointer would, through the same code:
    /// `select:<session>` (a click in the sidebar), `take_out:<n>`, `unsplit`, `join:<session>:<n>:<side>` (a session by creation order,
    /// beside
    /// the n-th pane of the split on screen), `hover:<n>` (the pointer on that pane), `landing:<n>:<side>`
    /// and `landing_off` (the dotted outline a drag shows), `leaving:<n>` and `leaving_off` (the
    /// pane being dragged out, over the sidebar), `split_menu` (what the icon's menu holds) and
    /// `split_state` (the layouts, the focus, what the sidebar lights). Panes count in reading order.
    extension MainWindowController {
        func performSplitActionForTesting(_ action: String) -> Bool {
            let parts = action.split(separator: ":").map(String.init)
            switch parts.first {
            case "select" where parts.count == 2:
                // select:<session>: a click on that session in the sidebar (creation order)
                if let index = Int(parts[1]), manager.workspace.sessions.indices.contains(index) {
                    select(manager.workspace.sessions[index].id)
                }
            case "take_out" where parts.count == 2:
                if let id = paneID(parts[1]) {
                    takeOutPane(id)
                }
            case "unsplit":
                unsplitAll()
            case "join" where parts.count == 4:
                if let index = Int(parts[1]), manager.workspace.sessions.indices.contains(index), let target = paneID(parts[2]),
                   let side = direction(parts[3]) {
                    joinSession(manager.workspace.sessions[index].id, beside: target, direction: side)
                }
            case "hover" where parts.count == 2:
                selectedWorkspace?.setHovered(paneID(parts[1]))
            case "landing" where parts.count == 3:
                if let target = paneID(parts[1]), let side = direction(parts[2]) {
                    selectedWorkspace?.showLanding(.init(target: target, direction: side))
                }
            case "landing_off":
                selectedWorkspace?.hideLanding()
            case "leaving" where parts.count == 2:
                selectedWorkspace?.setLeaving(paneID(parts[1]))
            case "leaving_off":
                selectedWorkspace?.setLeaving(nil)
            case "split_menu":
                logSplitMenuForTesting()
            case "split_state":
                logSplitStateForTesting()
            default:
                return performFocusActionForTesting(action)
            }
            return true
        }

        /// The n-th pane of the split on screen, in reading order.
        private func paneID(_ index: String) -> Session.ID? {
            guard let leaves = manager.workspace.selectedLayout?.tree.leaves, let index = Int(index), leaves.indices.contains(index) else {
                return nil
            }
            return leaves[index]
        }

        private func direction(_ name: String) -> SplitTree<Session.ID>.Direction? {
            ["left": .left, "right": .right, "up": .up, "down": .down][name]
        }

        /// The titles of the menu under the focused pane's icon, in order ("-" for a line).
        private func logSplitMenuForTesting() {
            guard let id = manager.workspace.selectedLayout?.focusedSessionID else { return }
            let titles = splitMenu(for: id).items.map { $0.isSeparatorItem ? "-" : $0.title }
            FileHandle.standardError.write(Data("calm-selftest: split menu \(titles.joined(separator: " | "))\n".utf8))
        }

        /// Every layout as the creation-order numbers of its sessions in reading order, which one is
        /// on screen, which session has the focus, what the sidebar lights, and how many panes each
        /// workspace view holds (the views must agree with the model).
        private func logSplitStateForTesting() {
            let sessions = manager.workspace.sessions
            func number(_ id: Session.ID) -> String {
                sessions.firstIndex { $0.id == id }.map(String.init) ?? "?"
            }
            let layouts = manager.workspace.layouts.map { layout in
                let panes = workspaces[layout.id]?.orderedPanes.count.description ?? "no view"
                let marker = layout.id == manager.workspace.selectedLayoutID ? "*" : ""
                let order = layout.tree.leaves.map(number).joined(separator: ",")
                return "\(marker)[\(order)] focus \(number(layout.focusedSessionID)) views \(panes)"
            }
            let lit = manager.workspace.sessionsInView.map(number).sorted().joined(separator: ",")
            let strays = workspaces.keys.filter { id in !manager.workspace.layouts.contains { $0.id == id } }.count
            let line = "layouts \(layouts.joined(separator: " ; ")) | in view [\(lit)] | workspace views without a layout \(strays)"
            FileHandle.standardError.write(Data("calm-selftest: split state \(line)\n".utf8))
        }
    }
#endif

#if DEBUG
    import AppKit
    import CalmModel

    /// Self-test drivers for getting into and out of a split (UIUX.md → Split panes). A headless
    /// run can't drag or hover, so each of these does what the pointer would, through the same code:
    /// - `select:<session>`: a click in the sidebar. Sessions count in creation order.
    /// - `take_out:<n>`, `unsplit`, `join:<session>:<n>:<side>`: the moves. Panes count in reading order.
    /// - `drag_over:<session>:<x>:<y>` and `drop:<session>:<x>:<y>`: a card of that session held over, or
    ///   let go at, that point of the split (fractions of its area), through the workspace view's own
    ///   drag-destination code with a stand-in for what AppKit hands it.
    /// - `pointer:<x>:<y>`: the pointer at that point of the split (fractions of its area), through the
    ///   workspace view's own mouse-moved code. `hover:<n>`: the pointer on that pane, without the geometry. `landing:<n>:<side>` and
    /// `landing_off`: the dotted outline.
    ///   `leaving:<n>` and `leaving_off`: the pane dragged out, over the sidebar.
    /// - `split_menu`: what the icon's menu holds. `split_state`: the layouts, the focus, what the sidebar lights.
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
                unsplit()
            case "join" where parts.count == 4:
                if let index = Int(parts[1]), manager.workspace.sessions.indices.contains(index), let target = paneID(parts[2]),
                   let side = direction(parts[3]) {
                    joinSession(manager.workspace.sessions[index].id, beside: target, direction: side)
                }
            case "drag_over" where parts.count == 4, "drop" where parts.count == 4:
                dragForTesting(parts)
            case "pointer" where parts.count == 3:
                pointerForTesting(x: parts[1], y: parts[2])
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

        /// `drag_over` or `drop` (`parts` is [action, session, x, y]): the workspace view's drag
        /// destination gets what AppKit would hand it (a private pasteboard with the session's drag
        /// on it, the point in window coordinates) and its answer is logged.
        private func dragForTesting(_ parts: [String]) {
            let sessions = manager.workspace.sessions
            guard let workspace = selectedWorkspace, let index = Int(parts[1]), sessions.indices.contains(index),
                  let x = Double(parts[2]), let y = Double(parts[3]) else { return }
            let drag = SessionDrag(origin: .card, sessionID: sessions[index].id)
            let board = NSPasteboard(name: NSPasteboard.Name("com.jinhuang.calm.selftest.drag"))
            board.clearContents()
            board.setString(drag.text, forType: TerminalWorkspaceView.sessionDragType)
            let local = NSPoint(x: x * workspace.bounds.width, y: y * workspace.bounds.height)
            let info = StandInDragInfo(pasteboard: board, location: workspace.convert(local, to: nil), window: window)
            if parts[0] == "drag_over" {
                let operation = workspace.draggingUpdated(info)
                FileHandle.standardError.write(Data("calm-selftest: drag over → operation \(operation.rawValue)\n".utf8))
            } else {
                let accepted = workspace.performDragOperation(info)
                FileHandle.standardError.write(Data("calm-selftest: drop → accepted \(accepted)\n".utf8))
            }
        }

        private func pointerForTesting(x: String, y: String) {
            guard let workspace = selectedWorkspace, let window, let x = Double(x), let y = Double(y) else { return }
            let local = NSPoint(x: x * workspace.bounds.width, y: y * workspace.bounds.height)
            if let event = NSEvent.mouseEvent(
                with: .mouseMoved, location: workspace.convert(local, to: nil), modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber, context: nil,
                eventNumber: 0, clickCount: 0, pressure: 0,
            ) {
                workspace.mouseMoved(with: event)
            }
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
            let hovered = selectedWorkspace?.hoveredID.map(number) ?? "none"
            let line = "layouts \(layouts.joined(separator: " ; ")) | in view [\(lit)] | pointer on \(hovered) | "
                + "workspace views without a layout \(strays)"
            FileHandle.standardError.write(Data("calm-selftest: split state \(line)\n".utf8))
        }
    }
#endif

#if DEBUG
    /// What AppKit hands a drag destination, made by hand: a pasteboard, a point and a window, and
    /// nothing else (a self-test has no pointer to drag with).
    @MainActor
    private final class StandInDragInfo: NSObject, @MainActor NSDraggingInfo {
        let draggingPasteboard: NSPasteboard
        let draggingLocation: NSPoint
        private let window: NSWindow?

        init(pasteboard: NSPasteboard, location: NSPoint, window: NSWindow?) {
            draggingPasteboard = pasteboard
            draggingLocation = location
            self.window = window
        }

        var draggingDestinationWindow: NSWindow? {
            window
        }

        var draggingSourceOperationMask: NSDragOperation {
            .every
        }

        var draggedImageLocation: NSPoint {
            draggingLocation
        }

        var draggedImage: NSImage? {
            nil
        }

        var draggingSource: Any? {
            nil
        }

        var draggingSequenceNumber: Int {
            1
        }

        var draggingFormation: NSDraggingFormation = .default
        var animatesToDestination = false
        var numberOfValidItemsForDrop = 1

        var springLoadingHighlight: NSSpringLoadingHighlight {
            .none
        }

        func slideDraggedImage(to _: NSPoint) {}

        func enumerateDraggingItems(
            options _: NSDraggingItemEnumerationOptions, for _: NSView?, classes _: [AnyClass],
            searchOptions _: [NSPasteboard.ReadingOptionKey: Any],
            using _: @escaping (NSDraggingItem, Int, UnsafeMutablePointer<ObjCBool>) -> Void,
        ) {}

        func resetSpringLoading() {}
    }
#endif

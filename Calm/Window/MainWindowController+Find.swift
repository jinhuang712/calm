import AppKit

/// Find in a session (FEATURES.md → F16, DESIGNS.md → Find): libghostty's reports about a pane's
/// search reach the window's FindModel, whose field sits in the title strip.
extension MainWindowController {
    func surface(_ view: TerminalSurfaceView, didFind event: FindEvent) {
        // The viewer and Settings cover the strip; find in a viewed file comes later (M8.7).
        if case .start = event, fileViewer.isShowing || settingsPage.isShowing {
            return
        }
        if case .fullScreen(true) = event, find.isSearching(view) {
            // For the note: an agent keeps its conversation, which ⌘K searches.
            find.agentName = manager.workspace.session(view.id)?.agent?.kind.displayName
        }
        find.handle(event, from: view)
    }

    /// The note's Search all of it ⌘K: the words go to ⌘K, which searches the agent's whole
    /// conversation, and find closes.
    func searchAllOfFind() {
        let words = find.query
        find.close()
        if searchHost != nil {
            hideSearch()
        }
        toggleSearch(query: words)
    }

    /// A key without ⌘ went to `view`: back to work, so find closes (the key still reaches the program).
    func surfaceDidType(_ view: TerminalSurfaceView) {
        find.didType(in: view)
    }

    #if DEBUG
        /// `find_open`, `find_type:<words>`, `find_older`, `find_newer`, `find_close` drive find as the
        /// keys would; `find_state` logs what the field shows.
        func findForTesting(_ action: String) {
            switch action {
            case "find_open":
                focusedPane?.perform("start_search")
            case let words where words.hasPrefix("find_type:"):
                find.query = String(words.dropFirst(10))
            case "find_older":
                find.step(.older)
            case "find_newer":
                find.step(.newer)
            case "find_close":
                find.close()
            case "find_note":
                FileHandle.standardError.write(Data("calm-selftest: find \(findNote.descriptionForTesting)\n".utf8))
            case "find_search_all":
                searchAllOfFind()
            case let agent where agent.hasPrefix("find_agent:"):
                // As if an agent ran in the pane: a test can't start a real one.
                find.agentName = String(agent.dropFirst(11))
            case "find_band":
                let marks = focusedPane.flatMap { pane in (pane.superview as? TerminalWorkspaceView)?.findMarksForTesting(pane.id) }
                FileHandle.standardError.write(Data("calm-selftest: find \(marks ?? "no workspace")\n".utf8))
            case "find_map":
                let map = (focusedPane?.superview as? TerminalWorkspaceView)?.findMapForTesting ?? "no workspace"
                FileHandle.standardError.write(Data("calm-selftest: find \(map)\n".utf8))
            case let hover where hover.hasPrefix("find_map_hover:"):
                (focusedPane?.superview as? TerminalWorkspaceView)?.hoverFindMapForTesting(line: Int(hover.dropFirst(15)))
            case let click where click.hasPrefix("find_map_click:"):
                if let line = Int(click.dropFirst(15)) {
                    focusedPane?.goToFindLine(line)
                }
            default:
                let target = find.target.map { Trace.id($0.id) } ?? "none"
                let state = "open \(find.isOpen), words \"\(find.query)\", total \(find.total.map(String.init) ?? "nil"), "
                    + "selected \(find.selected.map(String.init) ?? "nil"), shows \"\(find.countText)\", "
                    + "older \(find.olderDisabled ? "off" : "on"), newer \(find.newerDisabled ? "off" : "on"), pane \(target)"
                    + (focusedPane.map { pane in
                        let marks = pane.find
                        let rows = marks.matches.map { runs in
                            runs.map { "\($0.row):\($0.columns.lowerBound)-\($0.columns.upperBound)" }.joined(separator: "+")
                        }
                        let geometry = marks.geometry.map { "origin \($0.origin) baseline \($0.baseline) cell \(pane.cellSize)" } ?? "none"
                        return ", marks [\(rows.joined(separator: " "))], current \(marks.current.map(String.init) ?? "nil"), \(geometry)"
                    } ?? "")
                FileHandle.standardError.write(Data("calm-selftest: find \(state)\n".utf8))
            }
        }
    #endif
}

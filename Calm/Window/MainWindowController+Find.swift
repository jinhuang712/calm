import AppKit
import CalmModel

/// Find in a session (FEATURES.md → F16, DESIGNS.md → Find): libghostty's reports about a pane's
/// search reach the window's FindModel, whose field sits in the title strip.
extension MainWindowController {
    func surface(_ view: TerminalSurfaceView, didFind event: FindEvent) {
        // A viewed file covers the strip: ⌘F through the menu finds in it instead. Settings has no find.
        if case .start = event, fileViewer.isShowing || settingsPage.isShowing {
            if fileViewer.isShowing, !settingsPage.isShowing {
                fileViewer.find.toggle()
            }
            return
        }
        if case .fullScreen(true) = event, find.isSearching(view) {
            // For the note: an agent keeps its conversation, which ⌘K searches.
            find.agentName = manager.workspace.session(view.id)?.agent?.kind.displayName
        }
        find.handle(event, from: view)
        switch event {
        case .start, .fullScreen:
            updateFindSession(view)
        default:
            break
        }
    }

    /// Whether find's field offers Screen | Session for `pane`, and, in a full-screen program, how
    /// many more lines the session showed, for the note (one read of the scrollback).
    private func updateFindSession(_ pane: TerminalSurfaceView) {
        guard find.isSearching(pane) else { return }
        find.hasSession = pane.showsMoreThanScreen
        find.moreLines = find.hasSession && find.isFullScreen ? pane.sessionPage().moreCount : nil
    }

    /// Session, in the field or the note: what the session showed, as a page over the terminal
    /// with find's words (FEATURES.md → F16, the whole session). The program goes on underneath.
    func showSessionPage() {
        guard let pane = (find.target as? TerminalSurfaceView) ?? focusedPane, !settingsPage.isShowing else { return }
        let words = find.query
        let pattern = find.isPattern
        let page = pane.sessionPage()
        find.close()
        let background = pane.effectiveBackgroundColor
            ?? TerminalEngine.shared.config?.backgroundColor
            ?? NSColor(white: 0.15, alpha: 1)
        fileViewer.findColors = viewerFindColors
        let config = pane.shownConfig ?? TerminalEngine.shared.config
        let agent = manager.workspace.session(pane.id)?.agent?.kind.displayName
        let opening = FileViewer.SessionOpening(
            page: page,
            detail: Self.sessionPageDetail(page, agent: agent),
            session: pane.id,
            fontFamily: config?.string("font-family").flatMap { $0.isEmpty ? nil : $0 },
            fontSize: Double(pane.fontSize ?? 13),
        )
        fileViewer.showSession(opening, over: mainArea, background: background, style: sidebarStyle) { [weak self, weak pane] in
            if let pane {
                self?.window?.makeFirstResponder(pane)
            }
        }
        fileViewer.find.onScreen = { [weak self, weak pane] in self?.leaveSessionPage(to: pane) }
        fileViewer.find.open(words: words, isPattern: pattern)
    }

    /// Screen or esc on the session page: back to the live program, find in Screen with the page's
    /// words.
    private func leaveSessionPage(to pane: TerminalSurfaceView?) {
        let words = fileViewer.find.query
        let pattern = fileViewer.find.isPattern
        fileViewer.close()
        guard let pane else { return }
        find.open(pane, query: words, isPattern: pattern)
        updateFindSession(pane)
    }

    /// The session page's header: "Claude Code · since 14:02 · 1,240 lines".
    static func sessionPageDetail(_ page: SessionPage, agent: String?) -> String {
        let count = page.lines.count
        let lines = "\(count.formatted(.number.grouping(.automatic))) line\(count == 1 ? "" : "s")"
        return [agent, page.since.map { "since \(FileViewer.clock($0))" }, lines].compactMap(\.self).joined(separator: " · ")
    }

    /// ⌥⌘R: switches find's words between plain and a pattern; with find closed, opens it with
    /// a pattern.
    func toggleFindPattern() {
        if fileViewer.isShowing, !settingsPage.isShowing {
            let viewer = fileViewer.find
            if !viewer.isOpen {
                viewer.toggle()
                if !viewer.isPattern {
                    viewer.togglePattern()
                }
            } else {
                viewer.togglePattern()
            }
            return
        }
        guard let pane = focusedPane, !settingsPage.isShowing else { return }
        if find.isSearching(pane) {
            find.togglePattern()
        } else {
            find.handle(.start(needle: ""), from: pane)
            if !find.isPattern {
                find.togglePattern()
            }
        }
    }

    /// The Edit menu's find items while a file is shown: they find in it. False otherwise, so the
    /// pane gets them.
    func performViewerFind(_ action: String) -> Bool {
        guard fileViewer.isShowing, !settingsPage.isShowing else { return false }
        switch action {
        case "start_search": fileViewer.find.toggle()
        case "navigate_search:next": fileViewer.find.step(up: false)
        case "navigate_search:previous": fileViewer.find.step(up: true)
        case "search_selection": fileViewer.findSelection()
        default: return false
        }
        return true
    }

    /// Find's colors for a viewed file: the viewer's own background and text, with the accent the
    /// terminal's marks take (FindMarksView: the theme's, or palette color 4 for the user's own colors).
    var viewerFindColors: FindColors {
        let config = focusedPane?.shownConfig ?? TerminalEngine.shared.config
        let terminal = focusedPane?.effectiveBackgroundColor ?? config?.backgroundColor ?? .black
        let palette = config?.palette ?? []
        let accent = TerminalTheme.chromeColors(matching: terminal)?.findAccent
            ?? (palette.count == 16 ? palette[4].hexString : NSColor(sidebarStyle.accent).hexString)
        return FindColors(
            background: terminal.withAlphaComponent(1).hexString, foreground: NSColor(sidebarStyle.primary).hexString, accent: accent,
        )
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
            if findSessionForTesting(action) {
                return
            }
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
            case "find_pattern":
                toggleFindPattern()
            case let words where words.hasPrefix("find_viewer:"):
                fileViewer.find.toggle(words: String(words.dropFirst(12)))
            case let words where words.hasPrefix("find_viewer_type:"):
                fileViewer.find.query = String(words.dropFirst(17))
            case "find_viewer_toggle":
                fileViewer.find.toggle()
            case let step where step.hasPrefix("find_viewer_step:"):
                fileViewer.find.step(up: step.hasSuffix("up"))
            case "find_viewer_state":
                let model = fileViewer.find
                let underlines = fileViewer.pdfMarks.joined().count { $0.page.annotations.contains($0.underline) }
                let state = "viewer \(fileViewer.isShowing), open \(model.isOpen), searcher \(model.searcher), "
                    + "words \"\(model.query)\", shows \"\(model.countText)\", "
                    + "up \(model.upDisabled ? "off" : "on"), down \(model.downDisabled ? "off" : "on"), "
                    + "picture note \(model.showsPictureNote), pdf underlines \(underlines)"
                FileHandle.standardError.write(Data("calm-selftest: viewer find \(state)\n".utf8))
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
                let state = "open \(find.isOpen), pattern \(find.isPattern), words \"\(find.query)\", "
                    + "total \(find.total.map(String.init) ?? "nil"), selected \(find.selected.map(String.init) ?? "nil"), "
                    + "shows \"\(find.countText)\", "
                    + "older \(find.olderDisabled ? "off" : "on"), newer \(find.newerDisabled ? "off" : "on"), pane \(target), "
                    + "scope \(find.showsScope), more \(find.moreLines.map(String.init) ?? "nil")"
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

        /// The whole session: `find_session` and `find_screen` choose a side of the switch,
        /// `find_page` logs the session page, `find_kept` every pane's kept lines. False for
        /// any other action.
        private func findSessionForTesting(_ action: String) -> Bool {
            switch action {
            case "find_session":
                find.setScope(session: true)
            case "find_screen":
                fileViewer.find.setScope(session: false)
            case "find_page":
                Task { @MainActor in
                    let script = "[document.querySelectorAll('.session .l').length, document.querySelectorAll('.session .t').length, "
                        + "(document.querySelector('.session .l') || {}).textContent, "
                        + "Array.from(document.querySelectorAll('.session .l')).slice(-5).map(l => l.textContent).join(' / '), "
                        + "Math.round(window.scrollY + window.innerHeight) >= document.documentElement.scrollHeight - 2, "
                        + "Array.from(document.querySelectorAll('.session .t')).map(t => t.dataset.time).join(' ')].join(' | ')"
                    let page = await (try? fileViewer.webView?.evaluateJavaScript(script) as? String) ?? "no page"
                    let state = "session \(fileViewer.isSessionPage), scope \(fileViewer.find.showsScope), "
                        + "session chosen \(fileViewer.find.isSession), lines | marks | first | last five | at bottom | times: \(page)"
                    FileHandle.standardError.write(Data("calm-selftest: find page \(state)\n".utf8))
                }
            case "find_kept":
                // Every pane's kept lines, and the last line of the shell's screen behind (patch 0020).
                for pane in manager.panes.values {
                    let lines = pane.kept.lines
                    let shell = pane.primaryScreenText()?.split(separator: "\n").last { !$0.allSatisfy(\.isWhitespace) }
                    let state = "pane \(pane.id.uuidString.prefix(4)) shown \(pane.drawsFrames), kept \(lines.count), "
                        + "parts \(lines.count(where: \.startsPart)), first \"\(lines.first?.text ?? "")\", "
                        + "last \"\(lines.last?.text ?? "")\", shell \"\(shell ?? "none")\""
                    FileHandle.standardError.write(Data("calm-selftest: kept \(state)\n".utf8))
                }
            default:
                return false
            }
            return true
        }
    #endif
}

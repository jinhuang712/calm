#if DEBUG
    import AppKit
    import CalmAgents
    import CalmModel

    extension MainWindowController {
        func peekForTesting() {
            peek?.showForTesting()
        }

        /// Frames of the window's parts, for self-test logs.
        var layoutForTesting: String {
            let overlays = container.subviews
                .filter { $0 !== sidebarHost && $0 !== mainArea && $0 !== titleHost }
                .map { "\(type(of: $0)) \($0.frame)" }
            let background = focusedPane?.effectiveBackgroundColor ?? window?.backgroundColor ?? .clear
            let themed = TerminalTheme.chromeColors(matching: background) != nil
            let chrome = "terminal \(background.hexString), sidebar \(NSColor(sidebarStyle.background).hexString), "
                + "accent \(NSColor(sidebarStyle.accent).hexString), theme chrome \(themed)"
            let frames = "sidebar \(sidebarHost?.frame ?? .zero), main \(mainArea.frame), title \(titleHost?.frame ?? .zero), "
                + "overlays \(overlays)"
            return "\(frames); \(chrome); welcome \(welcomePage.isShowing); window title \(window?.title ?? ""); \(titleMenuForTesting)"
        }

        /// Where the title's ⋯ button is, and whether a click lands on it (and not beside it).
        private var titleMenuForTesting: String {
            guard let host = titleHost, host.menuFrame != .zero else { return "title menu none" }
            func hit(_ x: CGFloat, _ y: CGFloat) -> Bool {
                let point = NSPoint(x: x, y: host.isFlipped ? y : host.bounds.height - y)
                return host.hitTest(host.convert(point, to: host.superview)) != nil
            }
            let frame = host.menuFrame
            return "title menu \(frame), hit on button \(hit(frame.midX, frame.midY)), beside \(hit(frame.minX - 40, frame.midY))"
        }

        /// Calm's own actions for self-tests. Keys go through the app's event queue, so the
        /// session switcher sees them exactly as it sees the keyboard.
        func performForTesting(_ action: String) -> Bool {
            switch action {
            case "new_session":
                newSession()
            case let text where text.hasPrefix("type:"):
                // type:<command>: run a command in the focused session, so one run can set up several
                focusedPane?.typeForTesting(String(text.dropFirst(5)))
            case "toggle_sidebar":
                toggleSidebar()
            case "toggle_files":
                toggleFiles()
            case "viewer_text":
                Task { @MainActor in
                    let text = await fileViewer.renderedTextForTesting() ?? "no page"
                    let head = text.prefix(80).replacingOccurrences(of: "\n", with: " ⏎ ")
                    FileHandle.standardError.write(Data("calm-selftest: viewer text \(text.count) characters: \(head)\n".utf8))
                }
            case let appearance where appearance.hasPrefix("appearance:"):
                // appearance:light|dark, as if the system's appearance changed
                NSApp.appearance = NSAppearance(named: appearance.hasSuffix("light") ? .aqua : .darkAqua)
            case let files where files.hasPrefix("files_"):
                // What a click on a row of the files column does (a headless window is never key,
                // so AppKit won't deliver the click): files_open:<file>, files_expand:<folder>.
                filesColumnForTesting(files)
            case let name where name.hasPrefix("shuffle_mark:"):
                // What a click on a project's mark does (headless clicks never reach SwiftUI).
                return SessionManager.shared.shuffleMarkForTesting(named: String(name.dropFirst(13)))
            case "peek":
                peekForTesting()
            case let file where file.hasPrefix("view:"):
                // view:<path>[:line]
                if case let .file(path, line, _) = Link.parse(String(file.dropFirst(5)), relativeTo: nil, home: NSHomeDirectory()) {
                    showFile(path, line: line)
                }
            case "escape":
                postKey(.keyDown, keyCode: 53, characters: "\u{1b}", flags: [])
            case let link where link.hasPrefix("open_link:"):
                if let pane = focusedPane {
                    surface(pane, requestsOpenLink: String(link.dropFirst(10)))
                }
            case let copy where copy.hasPrefix("copy_cell:"):
                let text = String(copy.dropFirst(10))
                let copied = focusedPane?.copyCellForTesting(text)
                FileHandle.standardError.write(Data("calm-selftest: copy cell at \(text) → \(copied.debugDescription)\n".utf8))
            case let search where search.hasPrefix("search:"):
                toggleSearch(query: String(search.dropFirst(7)))
            case let search where search.hasPrefix("search_open:"):
                searchAndOpenForTesting(String(search.dropFirst(12)))
            case let keys where keys.hasPrefix("keys:"):
                // keys:<text>: type into whatever has focus (a text field, say), one key event per
                // character; `--type` only reaches the terminal. Sent to the window directly,
                // because a headless window is never key.
                for character in keys.dropFirst(5) {
                    let text = String(character)
                    for type in [NSEvent.EventType.keyDown, .keyUp] {
                        if let window, let event = NSEvent.keyEvent(
                            with: type, location: .zero, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                            windowNumber: window.windowNumber, context: nil, characters: text,
                            charactersIgnoringModifiers: text, isARepeat: false, keyCode: 0,
                        ) {
                            window.sendEvent(event)
                        }
                    }
                }
            case "cmd_k":
                pressKeyEquivalentForTesting(keyCode: 40, characters: "k")
            case let click where click.hasPrefix("double_click:"):
                // double_click:<x>x<y> in window points from the top left, through the window's
                // own event handling
                let point = click.dropFirst(13).split(separator: "x").compactMap { Double($0) }
                if point.count == 2 {
                    doubleClickForTesting(at: NSPoint(x: point[0], y: point[1]))
                }
            case "cmd_comma":
                pressKeyEquivalentForTesting(keyCode: 43, characters: ",")
            case "cmd_backslash":
                pressKeyEquivalentForTesting(keyCode: 42, characters: "\\")
            case "arrival":
                showArrivalCard()
            case "jump_waiting":
                TerminalMenuTarget.shared.jumpToWaitingSession(nil)
            case "ctrl_tab":
                postKey(.keyDown, keyCode: 48, characters: "\t", flags: .control)
            case "ctrl_escape":
                postKey(.keyDown, keyCode: 53, characters: "\u{1b}", flags: .control)
            case "ctrl_release":
                postKey(.flagsChanged, keyCode: 59, characters: "", flags: [])
            default:
                return performSessionActionForTesting(action)
            }
            return true
        }

        /// Session actions (F12), grouping (F2) and restart (F3) for self-tests.
        private func performSessionActionForTesting(_ action: String) -> Bool {
            switch action {
            case "restart":
                // Calm → Restart Calm. The Calm that comes back has no test drivers, so it never
                // snapshots or quits: whoever runs this stops it (not with selftest.sh, whose
                // watchdog only knows the first process).
                TerminalMenuTarget.shared.restart(nil)
            case "scratch":
                newScratchSession()
            case "close":
                focusedPane.map { requestCloseSession($0.id) }
            case "cmd_shift_t":
                pressKeyEquivalentForTesting(keyCode: 17, characters: "t", modifiers: [.command, .shift])
            case let add where add.hasPrefix("add_project:"):
                // add_project:<path>: what + New Project does once a folder is picked
                addProjects([URL(filePath: String(add.dropFirst(12)), directoryHint: .isDirectory)])
            case "make_project":
                focusedPane.flatMap { manager.workspace.session($0.id) }.map { manager.makeProject($0.projectID) }
            case let keep where keep.hasPrefix("keep_scratch:"):
                // keep_scratch:<path>: what "Keep as Project…" does once a folder is picked
                if let session = focusedPane.flatMap({ manager.workspace.session($0.id) }), let folder = session.scratchFolder {
                    moveScratchFolder(of: session.id, from: folder, to: URL(filePath: String(keep.dropFirst(13))))
                }
            case let conversation where conversation.hasPrefix("conversation:"):
                // conversation:<agent>:<id>: a stand-in for an agent conversation that ended in
                // the focused session (no agent is started)
                let parts = conversation.split(separator: ":").map(String.init)
                if parts.count == 3, let kind = AgentKind(rawValue: parts[1]), let id = focusedPane?.id {
                    manager.setLastConversationForTesting(id, AgentConversation(
                        kind: kind, agentSessionID: parts[2], transcriptPath: "/tmp/\(parts[2]).jsonl", title: "A past conversation",
                    ))
                }
            case let run where run.hasPrefix("agent_run:"):
                // agent_run:<agent>:<id>: a stand-in for an agent running in the focused session, with
                // its conversation known (no agent is started)
                let parts = run.split(separator: ":").map(String.init)
                if parts.count == 3, let kind = AgentKind(rawValue: parts[1]), let id = focusedPane?.id {
                    manager.noteAgentSession(id, kind: kind, agentSessionID: parts[2], transcriptPath: "/tmp/\(parts[2]).jsonl")
                }
            case "confirm_sheet":
                // What Return does on a confirmation (a headless window is never key)
                window?.attachedSheet?.defaultButtonCell?.performClick(nil)
            case let name where name.hasPrefix("rename:"):
                focusedPane.map { rename($0.id, to: String(name.dropFirst(7))) }
            case "rename_begin":
                sidebarEditing.renamingSessionID = focusedPane?.id
            case "resume":
                focusedPane.map { resumeConversation(in: $0.id) }
            case "fork_split":
                focusedPane.map { forkConversation(of: $0.id, into: .split) }
            case "fork_tab":
                focusedPane.map { forkConversation(of: $0.id, into: .tab) }
            default:
                return performSettingsActionForTesting(action)
            }
            return true
        }

        /// Settings (F14) and session states for self-tests.
        private func performSettingsActionForTesting(_ action: String) -> Bool {
            switch action {
            case "settings":
                TerminalMenuTarget.shared.showSettings(nil)
            case let section where section.hasPrefix("settings:"):
                // settings:appearance|agents|general|shortcuts
                showSettings(SettingsPage.Section(rawValue: String(section.dropFirst(9))))
            case let option where option.hasPrefix("set:"):
                // set:<key>=<value>, as a click in Settings (Appearance: background, layout, motion;
                // General: editor, open-paths, auto-grouping)
                let parts = option.dropFirst(4).split(separator: "=").map(String.init)
                if parts.count == 2 {
                    settingsPage.windowOptions.set(parts[0], parts[1])
                    settingsPage.general.set(parts[0], parts[1])
                }
            case let theme where theme.hasPrefix("pick_theme:"):
                // What a click on a theme in Settings does
                if settingsPage.themes.choices.isEmpty {
                    settingsPage.themes.refresh()
                }
                settingsPage.themes.pick(String(theme.dropFirst(11)).lowercased())
            case "agents":
                showSettings(.agents)
            case let state where state.hasPrefix("report:"):
                // report:<state>: the focused session reports a state, as an agent's hook would
                // (e.g. report:needsYou), without starting an agent.
                if let state = SessionState(rawValue: String(state.dropFirst(7))), let id = focusedPane?.id {
                    manager.report(id, StatusReport(state: state, message: "Allow edit?", source: .hook))
                }
            case let state where state.hasPrefix("agent:"):
                // agent:<state>: the focused session becomes a Claude Code card with a recap and a
                // todo list, in that state, so cards can be snapshotted without running an agent.
                if let state = SessionState(rawValue: String(state.dropFirst(6))), let id = focusedPane?.id {
                    manager.noteAgentSession(
                        id,
                        kind: .claudeCode,
                        agentSessionID: "5e1f0c2a-4b7d-4c1e-9a52-0d3f8e6b7a19",
                        transcriptPath: nil,
                    )
                    let tail = TranscriptTail(
                        lastMessage: "Moved the token refresh behind the retry loop and added a test for the expired case.",
                        progress: TodoProgress(done: 2, total: 5),
                    )
                    manager.transcriptChanged(id, tail, modified: .now)
                    if state != .idle {
                        manager.report(id, StatusReport(state: state, message: nil, source: .hook))
                    }
                }
            case let text where text.hasPrefix("copy:"):
                // copy:<sessionID|resumeCommand|folderPath>: what the title's ⋯ menu copies, read back from
                // the self-test pasteboard.
                let names: [String: SessionCopy] = ["sessionID": .sessionID, "resumeCommand": .resumeCommand, "folderPath": .folderPath]
                guard let kind = names[String(text.dropFirst(5))], let id = focusedPane?.id else { return false }
                copy(kind, of: id)
                let copied = NSPasteboard(name: .init("calm-selftest")).string(forType: .string)
                FileHandle.standardError.write(Data("calm-selftest: copied \(copied ?? "nothing")\n".utf8))
            case "rename":
                // What the title's ⋯ → Rename… does.
                if let id = focusedPane?.id {
                    beginRename(id)
                }
            default:
                return performLinkActionForTesting(action)
            }
            return true
        }

        /// Smart links (F8): the marks at rest, and the tag under ⌘.
        private func performLinkActionForTesting(_ action: String) -> Bool {
            switch action {
            case let link where link.hasPrefix("link_hover:"):
                // link_hover:<text on screen>: the pointer rests on it with ⌘ held
                let found = focusedPane?.hoverLinkForTesting(String(link.dropFirst(11))) ?? false
                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(0.3))
                    FileHandle.standardError.write(Data("calm-selftest: hover found \(found): \(linkTag.descriptionForTesting)\n".utf8))
                }
            case "link_marks":
                let marks = focusedPane?.linkMarksForTesting ?? []
                FileHandle.standardError.write(Data("calm-selftest: \(marks.count) link marks: \(marks.joined(separator: " | "))\n".utf8))
                FileHandle.standardError.write(Data("calm-selftest: grid \(focusedPane?.gridGeometryForTesting ?? "none")\n".utf8))
            default:
                return false
            }
            return true
        }

        /// What AppKit does with a key equivalent when the window is key (a headless window never
        /// is): the focused terminal first, then the menu item with that equivalent. The item's
        /// action is performed directly: a headless (accessory) app has no live menu bar, so
        /// `NSMenu.performKeyEquivalent` matches the item but doesn't dispatch it.
        private func pressKeyEquivalentForTesting(keyCode: UInt16, characters: String, modifiers: NSEvent.ModifierFlags = .command) {
            guard let window, let event = NSEvent.keyEvent(
                with: .keyDown, location: .zero, modifierFlags: modifiers, timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: window.windowNumber, context: nil, characters: characters,
                charactersIgnoringModifiers: characters, isARepeat: false, keyCode: keyCode,
            ) else { return }
            let terminalTookIt = focusedPane?.performKeyEquivalent(with: event) ?? false
            var menuItem: String?
            if !terminalTookIt, let menu = NSApp.mainMenu, let (owner, index) = Self.item(in: menu, key: characters, modifiers: modifiers) {
                // AppKit validates the items (greyed out or not) before it performs a key equivalent.
                owner.update()
                menuItem = owner.items[index].title + (owner.items[index].isEnabled ? "" : " (disabled)")
                owner.performActionForItem(at: index)
            }
            FileHandle.standardError
                .write(Data("calm-selftest: ⌘\(characters): terminal \(terminalTookIt), menu item \(menuItem ?? "none")\n".utf8))
        }

        private func doubleClickForTesting(at topLeft: NSPoint) {
            guard let window else { return }
            let before = window.frame
            let location = NSPoint(x: topLeft.x, y: window.frame.height - topLeft.y)
            for clicks in [1, 2] {
                for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
                    guard let event = NSEvent.mouseEvent(
                        with: type, location: location, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                        windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: clicks, pressure: 1,
                    ) else { continue }
                    window.sendEvent(event)
                }
            }
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(0.6)) // the zoom animates
                FileHandle.standardError.write(Data("calm-selftest: double-click at \(topLeft): frame \(before) → \(window.frame)\n".utf8))
            }
        }

        private static func item(in menu: NSMenu, key: String, modifiers: NSEvent.ModifierFlags) -> (NSMenu, Int)? {
            for (index, item) in menu.items.enumerated() {
                if item.keyEquivalent == key, item.keyEquivalentModifierMask.intersection(.deviceIndependentFlagsMask) == modifiers {
                    return (menu, index)
                }
                if let submenu = item.submenu, let found = self.item(in: submenu, key: key, modifiers: modifiers) {
                    return found
                }
            }
            return nil
        }

        /// Searches, waits for results, and opens the first, as Enter would.
        private func searchAndOpenForTesting(_ query: String) {
            let model = SearchPanelModel(query: query, currentProject: nil)
            Task {
                for _ in 0 ..< 30 where model.items.isEmpty {
                    try? await Task.sleep(for: .milliseconds(100))
                }
                guard let first = model.items.first else {
                    FileHandle.standardError.write(Data("calm-selftest: no search results for \(query)\n".utf8))
                    return
                }
                FileHandle.standardError
                    .write(Data("calm-selftest: opening \(first.result.title) (open session: \(first.openSession != nil))\n".utf8))
                openSearchResult(first)
            }
        }

        private func postKey(_ type: NSEvent.EventType, keyCode: UInt16, characters: String, flags: NSEvent.ModifierFlags) {
            guard let window else { return }
            let event = type == .flagsChanged
                ? NSEvent.keyEvent(
                    with: .flagsChanged, location: .zero, modifierFlags: flags, timestamp: ProcessInfo.processInfo.systemUptime,
                    windowNumber: window.windowNumber, context: nil, characters: "", charactersIgnoringModifiers: "",
                    isARepeat: false, keyCode: keyCode,
                )
                : NSEvent.keyEvent(
                    with: type, location: .zero, modifierFlags: flags, timestamp: ProcessInfo.processInfo.systemUptime,
                    windowNumber: window.windowNumber, context: nil, characters: characters,
                    charactersIgnoringModifiers: characters, isARepeat: false, keyCode: keyCode,
                )
            if let event {
                NSApp.postEvent(event, atStart: false)
            }
        }
    }
#endif

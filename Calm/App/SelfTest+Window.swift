#if DEBUG
    import AppKit
    import CalmModel

    extension MainWindowController {
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
            case "settings":
                TerminalMenuTarget.shared.showSettings(nil)
            case let section where section.hasPrefix("settings:"):
                SettingsWindowController.shared.show(SettingsWindowController.Section(rawValue: String(section.dropFirst(9))))
            case let option where option.hasPrefix("set:"):
                // set:<key>=<value>, as a click in Settings (Window: background, layout, motion;
                // General: editor, open-paths, auto-grouping)
                let parts = option.dropFirst(4).split(separator: "=").map(String.init)
                if parts.count == 2 {
                    SettingsWindowController.shared.windowOptions.set(parts[0], parts[1])
                    SettingsWindowController.shared.general.set(parts[0], parts[1])
                }
            case let theme where theme.hasPrefix("pick_theme:"):
                // What a click on a theme in Settings does
                SettingsWindowController.shared.themes.pick(String(theme.dropFirst(11)).lowercased())
            case "viewer_text":
                Task { @MainActor in
                    let text = await fileViewer.renderedTextForTesting() ?? "no page"
                    let head = text.prefix(80).replacingOccurrences(of: "\n", with: " ⏎ ")
                    FileHandle.standardError.write(Data("calm-selftest: viewer text \(text.count) characters: \(head)\n".utf8))
                }
            case let appearance where appearance.hasPrefix("appearance:"):
                // appearance:light|dark, as if the system's appearance changed
                NSApp.appearance = NSAppearance(named: appearance.hasSuffix("light") ? .aqua : .darkAqua)
            case let file where file.hasPrefix("files_open:"):
                // What a click on a file row does (a headless window is never key, so AppKit won't
                // deliver the click to the list).
                openFromFilesForTesting(String(file.dropFirst(11)))
            case "peek":
                peekForTesting()
            case "agents":
                showAgentsPanel()
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
            case "cmd_shift_e":
                pressKeyEquivalentForTesting(keyCode: 14, characters: "e", modifiers: [.command, .shift])
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

        /// Session actions (F12) and grouping (F2) for self-tests.
        private func performSessionActionForTesting(_ action: String) -> Bool {
            switch action {
            case "scratch":
                newScratchSession()
            case "close":
                focusedPane.map { requestCloseSession($0.id) }
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
                menuItem = owner.items[index].title
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

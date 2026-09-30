#if DEBUG
    import AppKit
    import CalmAgents
    import CalmControl
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
            return "\(frames); \(chrome); welcome \(welcomePage.isShowing); no-session page \(noSessionPage.isShowing); "
                + "window title \(window?.title ?? ""); \(titleMenuForTesting)"
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
            case let copy where ["copy_cell:", "cell_drag:", "cell_select:", "cell_hold:"].contains { copy.hasPrefix($0) }:
                copyCellForTesting(copy)
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

        /// Session actions (F12), grouping (F2), restart (F3) and the window's state (F1) for self-tests.
        private func performSessionActionForTesting(_ action: String) -> Bool {
            switch action {
            case "window_state":
                // Where the window is and whether it's in full screen, at this moment.
                if let window {
                    let state = "frame \(window.frame), full screen \(window.styleMask.contains(.fullScreen))"
                    FileHandle.standardError.write(Data("calm-selftest: window \(state)\n".utf8))
                }
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
            case "cmd_z":
                // ⌘Z: bound to Ctrl-_ in CalmDefaults, the line editor's undo
                pressKeyEquivalentForTesting(keyCode: 6, characters: "z", modifiers: [.command])
            case "cmd_delete":
                // ⌘⌫: Ghostty's default sends Ctrl-U, which deletes the line
                pressKeyEquivalentForTesting(keyCode: 51, characters: "\u{7F}", modifiers: [.command])
            case let arrow where arrow.hasPrefix("cmd_opt_"):
                // cmd_opt_left (or right, up, down): ⌘⌥ and that arrow key, which splits that way
                pressSplitArrowForTesting(String(arrow.dropFirst(8)))
            case let add where add.hasPrefix("add_project:"):
                // add_project:<path>: what + New Project does once a folder is picked
                addProjects([URL(filePath: String(add.dropFirst(12)), directoryHint: .isDirectory)])
            case let footer where footer.hasPrefix("footer:"):
                // footer:hide|show: what a click on the sidebar footer's handle does
                setSidebarFooter(footer == "footer:show")
            case "make_project":
                focusedPane.flatMap { manager.workspace.session($0.id) }.map { manager.makeProject($0.projectID) }
            case "fold_group":
                // What a click on the focused session's group header does: fold it, or unfold it.
                focusedPane.flatMap { manager.workspace.session($0.id) }.map { manager.toggleCollapsed($0.projectID) }
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
            case "confirm_prompt":
                // What Return does on the question a split's pane asks
                closePrompt.answerForTesting(close: true)
            case "keep_prompt":
                // What Esc does on it
                closePrompt.answerForTesting(close: false)
            case "focus_next":
                // ⌘]: the next split gets the focus, as a click on it would give it
                focusedPane.map { _ = surface($0, requestsFocus: .next) }
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

        /// Settings (F14), session states and the Dock icon for self-tests.
        private func performSettingsActionForTesting(_ action: String) -> Bool {
            switch action {
            case let folder where folder.hasPrefix("dock_icon:"):
                // dock_icon:<folder>: the Dock icon's states as PNGs (headless runs have no Dock)
                return DockIcon.shared.renderForTesting(to: URL(filePath: String(folder.dropFirst(10))))
            case "settings":
                TerminalMenuTarget.shared.showSettings(nil)
            case let section where section.hasPrefix("settings:"):
                // settings:appearance|agents|general|shortcuts
                showSettings(SettingsPage.Section(rawValue: String(section.dropFirst(9))))
            case let option where option.hasPrefix("set:"):
                // set:<key>=<value>, as a click in Settings (Appearance: background, layout, motion;
                // General: editor, editor-app, open-paths, auto-grouping)
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
            case let report where report.hasPrefix("report_away:"):
                // report_away:<state>[:<message>]: a session other than the focused one reports, as
                // when you're looking elsewhere, so a notification is due (run calm.new_session first;
                // "\n" in the message is a line break). The log says what it would have shown.
                let parts = report.dropFirst(12).split(separator: ":", maxSplits: 1).map(String.init)
                if let state = parts.first.flatMap(SessionState.init(rawValue:)),
                   let id = manager.workspace.sessions.first(where: { $0.id != focusedPane?.id })?.id {
                    let message = parts.dropFirst().first?.replacingOccurrences(of: "\\n", with: "\n")
                    manager.report(id, StatusReport(state: state, message: message, source: .hook))
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
            case let stop where stop.hasPrefix("hook_stop:"):
                // hook_stop:<shells>[:<agents>]: a Claude Code Stop reaches the focused session the way a
                // real one does, with that many background shells and agents still running.
                let counts = stop.dropFirst(10).split(separator: ":").compactMap { Int($0) }
                return sendStopForTesting(shells: counts.first ?? 0, agents: counts.dropFirst().first ?? 0)
            case let folder where folder.hasPrefix("agent_folder:"):
                // agent_folder:<path>: the agent in the focused session says it works in this folder
                // (run agent:<state> first), as Claude Code does after entering a git worktree while
                // its shell stays where it was.
                if let id = focusedPane?.id, var tail = manager.workspace.session(id)?.agent?.tail {
                    tail.directory = String(folder.dropFirst(13))
                    manager.transcriptChanged(id, tail, modified: .now)
                }
            case let title where title.hasPrefix("agent_title:"):
                // agent_title:<text>: the agent in the focused session has this title (run agent:<state>
                // first), as its transcript gives: the name the title strip shows above the folder.
                if let id = focusedPane?.id, var tail = manager.workspace.session(id)?.agent?.tail {
                    tail.title = String(title.dropFirst(12))
                    manager.transcriptChanged(id, tail, modified: .now)
                }
            case let summary where summary.hasPrefix("agent_summary:"):
                // agent_summary:<text>: the agent in the focused session wrote its own recap after its
                // last message (run agent:<state> first), as Claude Code does a few minutes after a turn.
                if let id = focusedPane?.id, var tail = manager.workspace.session(id)?.agent?.tail {
                    tail.summary = String(summary.dropFirst(14))
                    manager.transcriptChanged(id, tail, modified: .now)
                }
            case let text where text.hasPrefix("copy:"):
                // copy:<sessionID|resumeCommand|folderPath>: what the title's ⋯ menu copies, read back from
                // the self-test pasteboard.
                let names: [String: SessionCopy] = ["sessionID": .sessionID, "resumeCommand": .resumeCommand, "folderPath": .folderPath]
                guard let kind = names[String(text.dropFirst(5))], let id = focusedPane?.id else { return false }
                copy(kind, of: id)
                let copied = NSPasteboard.calm.string(forType: .string)
                FileHandle.standardError.write(Data("calm-selftest: copied \(copied ?? "nothing")\n".utf8))
            case "rename":
                // What the title's ⋯ → Rename… does.
                if let id = focusedPane?.id {
                    beginRename(id)
                }
            default:
                return performWelcomeActionForTesting(action)
            }
            return true
        }

        /// The welcome page, or the main area's lists with no session chosen. A headless window is
        /// never key, so neither clicks nor keys reach it: these drive its model the way they would.
        /// `welcome_type:<text>` types into the search; `welcome_key:down|up|left|right|enter|escape`
        /// presses that key; `welcome_project:<name>` and `welcome_session:<n>` click that row;
        /// `welcome_state` logs what the page holds. False while neither is up.
        private func performWelcomeActionForTesting(_ action: String) -> Bool {
            guard action.hasPrefix("welcome_") else { return performNoSessionActionForTesting(action) }
            guard let model = welcomePage.model ?? noSessionPage.model?.welcome else { return false }
            let argument = String(action.drop { $0 != ":" }.dropFirst())
            switch String(action.prefix { $0 != ":" }) {
            case "welcome_type":
                model.query = argument
            case "welcome_key":
                switch argument {
                case "down": model.step(1)
                case "up": model.step(-1)
                case "left": model.switchColumn(to: .sessions)
                case "right": model.switchColumn(to: .projects)
                case "enter": model.activate(welcomeActions)
                case "escape": model.query = ""
                default: return false
                }
            case "welcome_project":
                guard let project = model.projects.first(where: { $0.name == argument }) else { return false }
                welcomeActions.newSessionIn(project)
            case "welcome_session":
                guard let index = Int(argument), model.sessions.indices.contains(index) else { return false }
                welcomeActions.open(model.sessions[index])
            case "welcome_state":
                let rows = model.walk.map { target -> String in
                    switch target {
                    case let .session(id): "session \((id as NSString).lastPathComponent)"
                    case let .project(id): "project \(model.projects.first { $0.id == id }?.name ?? "?")"
                    }
                }
                let selected = model.selected.flatMap { model.walk.firstIndex(of: $0) }.map(String.init) ?? "none"
                let line = "welcome: content \(model.content), query \"\(model.query)\", selected \(selected), rows \(rows)"
                FileHandle.standardError.write(Data("calm-selftest: \(line)\n".utf8))
            default:
                return false
            }
            return true
        }

        /// A Claude Code Stop through the real path: payload, adapter, control handler (`calm hook` does
        /// the same over the socket). False when there's no session or no adapter.
        private func sendStopForTesting(shells: Int, agents: Int) -> Bool {
            guard let id = focusedPane?.id, let reporter = Agents.hookReporter(named: "claude-code") else { return false }
            func tasks(_ type: String, _ count: Int) -> [String] {
                (0 ..< count).map { #"{"id":"\#(type)\#($0)","type":"\#(type)","status":"running"}"# }
            }
            let list = (tasks("shell", shells) + tasks("subagent", agents)).joined(separator: ",")
            let message = "Fixes 1 and 2 are built. Want me to build the third?"
            let payload = Data(
                #"{"hook_event_name":"Stop","last_assistant_message":"\#(message)","background_tasks":[\#(list)]}"#.utf8,
            )
            guard let hook = reporter.hookReport(from: payload) else { return false }
            let response = ControlServer.shared.handle(ControlRequest(
                cmd: .status, session: id.uuidString, state: hook.state.reportName, message: hook.message,
                agent: reporter.kind.rawValue, agentSession: hook.agentSessionID, transcript: hook.transcriptPath,
                shells: hook.backgroundShells > 0 ? hook.backgroundShells : nil,
            ))
            let result = "\(hook.state.reportName), \(hook.backgroundShells) shells, ok \(response.ok)"
            FileHandle.standardError.write(Data("calm-selftest: hook_stop → \(result)\n".utf8))
            return response.ok
        }

        /// The main area with no session chosen, driven like the welcome page: `nosession_key:down|up|enter`
        /// presses that key on the waiting cards; `nosession_state` logs what the page shows.
        /// False while the page isn't up.
        private func performNoSessionActionForTesting(_ action: String) -> Bool {
            guard action.hasPrefix("nosession_") else { return performLinkActionForTesting(action) }
            guard let model = noSessionPage.model else { return false }
            switch action {
            case "nosession_key:down":
                model.step(1)
            case "nosession_key:up":
                model.step(-1)
            case "nosession_key:enter":
                guard let id = model.selected else { return false }
                select(id)
            case "nosession_state":
                let titles = model.waitingIDs.map { id in
                    manager.workspace.session(id).map { $0.title(agentTitle: $0.agent?.tail?.title) } ?? "?"
                }
                let selected = model.selected.flatMap { model.waitingIDs.firstIndex(of: $0) }.map(String.init) ?? "none"
                let shows = model.content == .lists ? "lists (\(model.welcome.content))" : "waiting \(titles)"
                let line = "no-session page: \(shows), selected \(selected), searched \(model.searched), "
                    + "first responder \(window?.firstResponder.map { String(describing: type(of: $0)) } ?? "none")"
                FileHandle.standardError.write(Data("calm-selftest: \(line)\n".utf8))
            default:
                return false
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
            case let link where link.hasPrefix("link_click:"):
                // link_click:<text on screen>: ⌘-move onto it and ⌘-click, through the pane's mouse handlers
                let found = focusedPane?.commandClickForTesting(String(link.dropFirst(11))) ?? false
                FileHandle.standardError.write(Data("calm-selftest: command-click found \(found)\n".utf8))
            case let link where link.hasPrefix("link_press:"):
                // link_press:<text on screen>: the pointer rests on it, then ⌘ goes down
                let found = focusedPane?.commandPressOverForTesting(String(link.dropFirst(11))) ?? false
                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(0.3))
                    FileHandle.standardError.write(Data("calm-selftest: press found \(found): \(linkTag.descriptionForTesting)\n".utf8))
                }
            case "link_tag":
                // what the link tag shows right now
                FileHandle.standardError.write(Data("calm-selftest: \(linkTag.descriptionForTesting)\n".utf8))
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

        private func pressSplitArrowForTesting(_ direction: String) {
            let keys: [String: (code: UInt16, function: Int)] = [
                "left": (123, NSLeftArrowFunctionKey), "right": (124, NSRightArrowFunctionKey),
                "up": (126, NSUpArrowFunctionKey), "down": (125, NSDownArrowFunctionKey),
            ]
            guard let key = keys[direction] else { return }
            pressKeyEquivalentForTesting(
                keyCode: key.code,
                characters: String(utf16CodeUnits: [unichar(key.function)], count: 1),
                modifiers: [.command, .option],
            )
        }

        /// copy_cell:<text>: hold ⌥ over the text and click it; cell_drag:<text>: ⌥-drag from it six
        /// cells to the right; cell_select:<from>|<to>: ⌥-drag from the first to the last character
        /// of <to>; cell_hold: the same, not let go, for a snapshot. Logs the outline, the
        /// selection, what was copied and whether the terminal selected too.
        private func copyCellForTesting(_ action: String) {
            let name = action.prefix { $0 != ":" }
            let parts = action.dropFirst(name.count + 1).split(separator: "|", maxSplits: 1).map(String.init)
            let result = focusedPane?.optionClickForTesting(
                parts[0], to: parts.count > 1 ? parts[1] : nil, dragCells: name == "cell_drag" ? 6 : 0,
                release: name != "cell_hold",
            )
            let line = "calm-selftest: \(name) at \(parts.joined(separator: " → ")): \(result ?? "not found")\n"
            FileHandle.standardError.write(Data(line.utf8))
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

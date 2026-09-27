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
            case "toggle_sidebar":
                toggleSidebar()
            case "toggle_files":
                toggleFiles()
            case "settings":
                TerminalMenuTarget.shared.showSettings(nil)
            case let option where option.hasPrefix("set:"):
                // set:<background|layout|motion>=<value>, as a click in Settings → Window
                let parts = option.dropFirst(4).split(separator: "=").map(String.init)
                if parts.count == 2 {
                    SettingsWindowController.shared.windowOptions.set(parts[0], parts[1])
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

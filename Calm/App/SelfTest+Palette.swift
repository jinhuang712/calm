#if DEBUG
    import AppKit
    import CalmModel

    extension MainWindowController {
        /// ⌘P for self-tests: `cmd_p` opens the palette and logs its rows (`keys:<text>` then types
        /// into its field); `palette_run:<title>` does what choosing that row does, since a headless
        /// window is never key and ↵ and clicks don't arrive. False for any other action.
        func performPaletteActionForTesting(_ action: String) -> Bool {
            switch action {
            case "cmd_p":
                pressKeyEquivalentForTesting(keyCode: 35, characters: "p")
            case "finish_elsewhere":
                // The first session not in front finishes a turn, as when an agent ends while you
                // work in another session. (Leaving a done session settles it, so a test can't
                // make one done and then leave it.)
                if let other = manager.workspace.sessions.first(where: { $0.id != focusedPane?.id }) {
                    manager.report(other.id, StatusReport(state: .done, message: nil, source: .hook))
                }
            case let row where row.hasPrefix("palette_run:"):
                let title = String(row.dropFirst(12))
                if let command = paletteCommands().first(where: { $0.title == title }) {
                    runPaletteCommand(command)
                } else {
                    FileHandle.standardError.write(Data("calm-selftest: palette_run: no row titled \(title)\n".utf8))
                }
            default:
                return performSessionMenuActionForTesting(action)
            }
            return true
        }

        /// The session menu for self-tests (a headless window gets no clicks or keys):
        /// `session_menu` opens it from the title strip's ⋯ for the session in front,
        /// `session_menu_at:<x>:<y>` at that point in the window as a right-click would (the action
        /// list is comma-separated, so the point isn't), and
        /// `menu_key:<up|down|left|right|enter|esc>` presses a key in it. Each logs the menu.
        private func performSessionMenuActionForTesting(_ action: String) -> Bool {
            switch action {
            case "session_menu":
                guard let id = focusedPane?.id else { return false }
                showSessionMenuFromTitle(id)
            case let at where at.hasPrefix("session_menu_at:"):
                let numbers = at.dropFirst(16).split(separator: ":").compactMap { Double($0) }
                guard numbers.count == 2, let id = focusedPane?.id else { return false }
                showSessionMenu(id, atWindowPoint: CGPoint(x: numbers[0], y: numbers[1]))
            case let key where key.hasPrefix("menu_key:"):
                guard sessionMenu.isShowing,
                      let key = SessionMenuController.TestKey(rawValue: String(key.dropFirst(9))) else { return false }
                sessionMenu.pressForTesting(key)
            default:
                return false
            }
            return true
        }
    }
#endif

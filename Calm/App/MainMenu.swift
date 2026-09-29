import AppKit

/// The app's menu bar. Terminal commands are sent to the focused pane as libghostty
/// binding actions, so menus and the user's Ghostty keybindings always agree.
@MainActor
enum MainMenu {
    static func make() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(submenu(appMenu()))
        menu.addItem(submenu(fileMenu()))
        menu.addItem(submenu(editMenu()))
        menu.addItem(submenu(viewMenu()))
        let window = windowMenu()
        menu.addItem(submenu(window))
        NSApp.windowsMenu = window
        return menu
    }

    private static func submenu(_ menu: NSMenu) -> NSMenuItem {
        let item = NSMenuItem(title: menu.title, action: nil, keyEquivalent: "")
        item.submenu = menu
        return item
    }

    private static func appMenu() -> NSMenu {
        let menu = NSMenu(title: "Calm")
        menu.addItem(withTitle: "About Calm", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        menu.addItem(.separator())
        let settings = NSMenuItem(title: "Settings…", action: #selector(TerminalMenuTarget.showSettings(_:)), keyEquivalent: ",")
        settings.target = TerminalMenuTarget.shared
        menu.addItem(settings)
        let agents = NSMenuItem(title: "Agents…", action: #selector(TerminalMenuTarget.showAgentsPanel(_:)), keyEquivalent: "")
        agents.target = TerminalMenuTarget.shared
        menu.addItem(agents)
        menu.addItem(.separator())
        menu.addItem(terminalItem("Reload Configuration", "reload_config", key: ",", mods: [.command, .shift]))
        menu.addItem(.separator())
        menu.addItem(withTitle: "Hide Calm", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        let hideOthers = menu.addItem(
            withTitle: "Hide Others",
            action: #selector(NSApplication.hideOtherApplications(_:)),
            keyEquivalent: "h",
        )
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        menu.addItem(.separator())
        // No shortcut: a restart is rare, and one key away from ⌘Q it would be easy to hit by mistake.
        let restart = NSMenuItem(title: "Restart Calm", action: #selector(TerminalMenuTarget.restart(_:)), keyEquivalent: "")
        restart.target = TerminalMenuTarget.shared
        // AppKit gives Hide and Quit their symbols; this one sits with Quit, so it gets one too.
        restart.image = NSImage(systemSymbolName: "arrow.clockwise", accessibilityDescription: nil)
        menu.addItem(restart)
        menu.addItem(withTitle: "Quit Calm", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        return menu
    }

    private static func fileMenu() -> NSMenu {
        let menu = NSMenu(title: "Shell")
        menu.addItem(actionItem("New Session", #selector(TerminalMenuTarget.newSession(_:)), key: "t"))
        menu.addItem(actionItem(
            "New Scratch Session",
            #selector(TerminalMenuTarget.newScratchSession(_:)),
            key: "n",
            mods: [.command, .shift],
        ))
        menu.addItem(actionItem("New Project…", #selector(TerminalMenuTarget.newProject(_:)), key: "o"))
        menu.addItem(actionItem(
            "Reopen Closed Session",
            #selector(TerminalMenuTarget.reopenClosedSession(_:)),
            key: "t",
            mods: [.command, .shift],
        ))
        menu.addItem(.separator())
        // ⌘D and ⌘⇧D (Ghostty's) still split right and down, unlisted: a menu item shows one key.
        for (title, direction, arrow) in [
            ("Split Left", "left", NSLeftArrowFunctionKey),
            ("Split Right", "right", NSRightArrowFunctionKey),
            ("Split Up", "up", NSUpArrowFunctionKey),
            ("Split Down", "down", NSDownArrowFunctionKey),
        ] {
            let key = String(utf16CodeUnits: [unichar(arrow)], count: 1)
            menu.addItem(terminalItem(title, "new_split:\(direction)", key: key, mods: [.command, .option]))
        }
        menu.addItem(.separator())
        menu.addItem(terminalItem("Close Session", "close_surface", key: "w"))
        return menu
    }

    private static func editMenu() -> NSMenu {
        let menu = NSMenu(title: "Edit")
        menu.addItem(withTitle: "Copy", action: #selector(TerminalSurfaceView.copy(_:)), keyEquivalent: "c")
        menu.addItem(withTitle: "Paste", action: #selector(TerminalSurfaceView.paste(_:)), keyEquivalent: "v")
        menu.addItem(withTitle: "Select All", action: #selector(NSResponder.selectAll(_:)), keyEquivalent: "a")
        menu.addItem(.separator())
        menu.addItem(terminalItem("Clear Screen", "clear_screen", key: "k", mods: [.command, .shift])) // ⌘K is Search Sessions
        return menu
    }

    private static func viewMenu() -> NSMenu {
        let menu = NSMenu(title: "View")
        menu.addItem(actionItem("Command Palette", #selector(TerminalMenuTarget.toggleCommandPalette(_:)), key: "p"))
        menu.addItem(actionItem("Toggle Sidebar", #selector(TerminalMenuTarget.toggleSidebar(_:)), key: "s", mods: [.command, .control]))
        menu.addItem(actionItem("Toggle Files", #selector(TerminalMenuTarget.toggleFiles(_:)), key: "\\"))
        menu.addItem(.separator())
        menu.addItem(terminalItem("Bigger", "increase_font_size:1", key: "+"))
        menu.addItem(terminalItem("Smaller", "decrease_font_size:1", key: "-"))
        menu.addItem(terminalItem("Actual Size", "reset_font_size", key: "0"))
        menu.addItem(.separator())
        menu.addItem(terminalItem("Zoom Split", "toggle_split_zoom", key: "\r", mods: [.command, .shift]))
        menu.addItem(terminalItem("Equalize Splits", "equalize_splits", key: "=", mods: [.command, .control]))
        menu.addItem(.separator())
        let fullScreen = menu.addItem(
            withTitle: "Enter Full Screen",
            action: #selector(NSWindow.toggleFullScreen(_:)),
            keyEquivalent: "f",
        )
        fullScreen.keyEquivalentModifierMask = [.command, .control]
        return menu
    }

    private static func windowMenu() -> NSMenu {
        let menu = NSMenu(title: "Window")
        menu.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        menu.addItem(.separator())
        menu.addItem(terminalItem("Previous Split", "goto_split:previous", key: "["))
        menu.addItem(terminalItem("Next Split", "goto_split:next", key: "]"))
        menu.addItem(.separator())
        menu.addItem(terminalItem("Previous Session", "previous_tab", key: "[", mods: [.command, .shift]))
        menu.addItem(terminalItem("Next Session", "next_tab", key: "]", mods: [.command, .shift]))
        menu.addItem(actionItem(
            "Jump to Waiting Session",
            #selector(TerminalMenuTarget.jumpToWaitingSession(_:)),
            key: "a",
            mods: [.command, .shift],
        ))
        menu.addItem(actionItem("Show Arrival Card", #selector(TerminalMenuTarget.showArrivalCard(_:)), key: "i", mods: [.command, .shift]))
        menu.addItem(.separator())
        menu.addItem(actionItem("Search Sessions", #selector(TerminalMenuTarget.searchSessions(_:)), key: "k"))
        return menu
    }

    /// A menu item that runs a libghostty binding action on the focused pane.
    private static func terminalItem(_ title: String, _ action: String, key: String, mods: NSEvent.ModifierFlags = .command) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: #selector(TerminalMenuTarget.performTerminalAction(_:)), keyEquivalent: key)
        item.keyEquivalentModifierMask = mods
        item.representedObject = action
        item.target = TerminalMenuTarget.shared
        return item
    }

    private static func actionItem(
        _ title: String,
        _ selector: Selector,
        key: String,
        mods: NSEvent.ModifierFlags = .command,
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: selector, keyEquivalent: key)
        item.keyEquivalentModifierMask = mods
        let targeted = [
            "newSession", "newScratchSession", "newProject", "reopenClosedSession", "toggleCommandPalette", "toggleSidebar", "toggleFiles",
            "jumpToWaitingSession",
            "showArrivalCard",
            "searchSessions",
        ]
        if targeted.contains(where: { selector.description.hasPrefix($0) }) {
            item.target = TerminalMenuTarget.shared
        }
        return item
    }
}

/// Target for menu commands that aren't tied to one view.
@MainActor
final class TerminalMenuTarget: NSObject {
    static let shared = TerminalMenuTarget()

    @objc func newSession(_: Any?) {
        TerminalWindowManager.shared.openMainWindow().newSession()
    }

    @objc func newScratchSession(_: Any?) {
        TerminalWindowManager.shared.openMainWindow().newScratchSession()
    }

    @objc func newProject(_: Any?) {
        TerminalWindowManager.shared.openMainWindow().chooseNewProject()
    }

    @objc func reopenClosedSession(_: Any?) {
        TerminalWindowManager.shared.openMainWindow().reopenClosedSession()
    }

    @objc func toggleFiles(_: Any?) {
        TerminalWindowManager.shared.focusedController?.toggleFiles()
    }

    @objc func toggleSidebar(_: Any?) {
        TerminalWindowManager.shared.focusedController?.toggleSidebar()
    }

    @objc func performTerminalAction(_ sender: NSMenuItem) {
        guard let action = sender.representedObject as? String else { return }
        if action == "reload_config" {
            TerminalEngine.shared.reloadConfig(soft: false)
            return
        }
        TerminalWindowManager.shared.focusedController?.focusedPane?.perform(action)
    }

    /// ⌘⇧A: the session that has waited longest for you (UIUX.md → Keyboard).
    @objc func jumpToWaitingSession(_: Any?) {
        let manager = SessionManager.shared
        let current = manager.workspace.selectedLayout?.focusedSessionID
        guard let waiting = manager.workspace.sessionsNeedingYou.first(where: { $0.id != current }) else { return }
        TerminalWindowManager.shared.openMainWindow().select(waiting.id)
    }

    /// ⌘K: search every session.
    @objc func searchSessions(_: Any?) {
        TerminalWindowManager.shared.openMainWindow().toggleSearch()
    }

    /// ⌘,: Settings takes the window; ⌘, again goes back.
    @objc func showSettings(_: Any?) {
        TerminalWindowManager.shared.openMainWindow().toggleSettings()
    }

    @objc func showAgentsPanel(_: Any?) {
        TerminalWindowManager.shared.openMainWindow().showSettings(.agents)
    }

    /// Quit and open again; shells stay alive in between (see Restart).
    @objc func restart(_: Any?) {
        Restart.request()
    }

    /// ⌘⇧I: what the focused agent session is and last said.
    @objc func showArrivalCard(_: Any?) {
        TerminalWindowManager.shared.focusedController?.showArrivalCard()
    }

    @objc func toggleCommandPalette(_: Any?) {
        TerminalWindowManager.shared.focusedController?.toggleCommandPalette()
    }
}

extension TerminalMenuTarget: NSMenuItemValidation {
    /// Reopen Closed Session waits until a session has been closed.
    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        item.action == #selector(reopenClosedSession(_:)) ? SessionManager.shared.canReopenClosedSession : true
    }
}

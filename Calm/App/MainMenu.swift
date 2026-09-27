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
        menu.addItem(withTitle: "Quit Calm", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        return menu
    }

    private static func fileMenu() -> NSMenu {
        let menu = NSMenu(title: "Shell")
        menu.addItem(actionItem("New Window", #selector(TerminalMenuTarget.newWindow(_:)), key: "n"))
        menu.addItem(terminalItem("New Tab", "new_tab", key: "t"))
        menu.addItem(.separator())
        menu.addItem(terminalItem("Split Right", "new_split:right", key: "d"))
        menu.addItem(terminalItem("Split Down", "new_split:down", key: "d", mods: [.command, .shift]))
        menu.addItem(.separator())
        menu.addItem(terminalItem("Close", "close_surface", key: "w"))
        menu.addItem(actionItem("Close Window", #selector(NSWindow.performClose(_:)), key: "w", mods: [.command, .shift]))
        return menu
    }

    private static func editMenu() -> NSMenu {
        let menu = NSMenu(title: "Edit")
        menu.addItem(withTitle: "Copy", action: #selector(TerminalSurfaceView.copy(_:)), keyEquivalent: "c")
        menu.addItem(withTitle: "Paste", action: #selector(TerminalSurfaceView.paste(_:)), keyEquivalent: "v")
        menu.addItem(withTitle: "Select All", action: #selector(NSResponder.selectAll(_:)), keyEquivalent: "a")
        menu.addItem(.separator())
        menu.addItem(terminalItem("Clear Screen", "clear_screen", key: "k"))
        return menu
    }

    private static func viewMenu() -> NSMenu {
        let menu = NSMenu(title: "View")
        menu.addItem(actionItem("Command Palette", #selector(TerminalMenuTarget.toggleCommandPalette(_:)), key: "p"))
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
        menu.addItem(withTitle: "Show Previous Tab", action: #selector(NSWindow.selectPreviousTab(_:)), keyEquivalent: "{")
        menu.addItem(withTitle: "Show Next Tab", action: #selector(NSWindow.selectNextTab(_:)), keyEquivalent: "}")
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
        if selector.description.hasPrefix("newWindow") || selector.description.hasPrefix("toggleCommandPalette") {
            item.target = TerminalMenuTarget.shared
        }
        return item
    }
}

/// Target for menu commands that aren't tied to one view.
@MainActor
final class TerminalMenuTarget: NSObject {
    static let shared = TerminalMenuTarget()

    @objc func newWindow(_: Any?) {
        TerminalWindowManager.shared.openWindow(inheriting: TerminalWindowManager.shared.focusedController?.focusedPane)
    }

    @objc func performTerminalAction(_ sender: NSMenuItem) {
        guard let action = sender.representedObject as? String else { return }
        if action == "reload_config" {
            TerminalEngine.shared.reloadConfig(soft: false)
            return
        }
        TerminalWindowManager.shared.focusedController?.focusedPane?.perform(action)
    }

    @objc func toggleCommandPalette(_: Any?) {
        TerminalWindowManager.shared.focusedController?.toggleCommandPalette()
    }
}

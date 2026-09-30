import Foundation
import GhosttyKit

/// A libghostty binding action the palette can run, with the labels Ghostty gives it.
struct TerminalCommand: Identifiable, Hashable {
    var id: String {
        action
    }

    let title: String
    let detail: String
    let action: String
}

extension TerminalConfig {
    /// The few of libghostty's palette entries that belong beside Calm's own: no key reaches them
    /// and they are about the terminal. Without a key, Ghostty's list is still dozens of rows, mostly
    /// its own windows, tabs and screen dumps, so this is an allowlist, not a blocklist that a
    /// new Ghostty release would quietly outgrow.
    static let paletteActions = ["reset", "toggle_mouse_reporting"]

    /// libghostty's palette entries (`command-palette-entry`) for `paletteActions`.
    var commands: [TerminalCommand] {
        var list = ghostty_config_command_list_s()
        let key = "command-palette-entry"
        let found = key.withCString { ghostty_config_get(raw, &list, $0, UInt(key.utf8.count)) }
        guard found, let pointer = list.commands else { return [] }

        var seen = Set<String>()
        var result: [TerminalCommand] = []
        for index in 0 ..< list.len {
            let entry = pointer[index]
            guard let actionPointer = entry.action, let titlePointer = entry.title else { continue }
            let action = String(cString: actionPointer)
            guard Self.paletteActions.contains(action), !seen.contains(action) else { continue }
            seen.insert(action)
            result.append(TerminalCommand(
                title: String(cString: titlePointer),
                detail: entry.description.map { String(cString: $0) } ?? "",
                action: action,
            ))
        }
        return result
    }
}

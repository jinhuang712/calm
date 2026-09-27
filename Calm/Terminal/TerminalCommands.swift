import AppKit
import GhosttyKit

/// A command that can run from the palette: a libghostty binding action plus labels.
struct TerminalCommand: Identifiable, Hashable {
    var id: String {
        action
    }

    let title: String
    let detail: String
    let action: String
    let shortcut: String
}

extension TerminalConfig {
    /// libghostty's palette entries (`command-palette-entry`), with the key bound to each.
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
            guard !seen.contains(action), Self.isSupported(action) else { continue }
            seen.insert(action)
            result.append(TerminalCommand(
                title: String(cString: titlePointer),
                detail: entry.description.map { String(cString: $0) } ?? "",
                action: action,
                shortcut: shortcutLabel(for: action),
            ))
        }
        return result
    }

    /// Actions Calm doesn't implement (yet); hidden from the palette rather than doing nothing.
    private static let unsupportedPrefixes = [
        "check_for_updates", "prompt_", "inspector", "toggle_quick_terminal", "toggle_tab_overview",
        "toggle_window_decorations", "show_gtk_inspector", "toggle_visibility", "float_window",
        "toggle_background_opacity", "undo", "redo", "show_on_screen_keyboard", "toggle_secure_input",
        "open_config", "toggle_readonly", "present_terminal", "move_tab", "toggle_maximize",
    ]

    static func isSupported(_ action: String) -> Bool {
        !unsupportedPrefixes.contains { action.hasPrefix($0) }
    }

    /// A readable label (⌘⇧D) for the key bound to `action`, or "" if none or unknown.
    func shortcutLabel(for action: String) -> String {
        let trigger = action.withCString { ghostty_config_trigger(raw, $0, UInt(action.utf8.count)) }
        let key: String
        switch trigger.tag {
        case GHOSTTY_TRIGGER_UNICODE:
            guard let scalar = Unicode.Scalar(trigger.key.unicode) else { return "" }
            key = String(Character(scalar)).uppercased()
        case GHOSTTY_TRIGGER_PHYSICAL:
            key = Self.physicalKeyLabel(trigger.key.physical)
        default:
            return ""
        }
        guard !key.isEmpty else { return "" }
        let mods = trigger.mods.rawValue
        var label = ""
        if mods & GHOSTTY_MODS_CTRL.rawValue != 0 {
            label += "⌃"
        }
        if mods & GHOSTTY_MODS_ALT.rawValue != 0 {
            label += "⌥"
        }
        if mods & GHOSTTY_MODS_SHIFT.rawValue != 0 {
            label += "⇧"
        }
        if mods & GHOSTTY_MODS_SUPER.rawValue != 0 {
            label += "⌘"
        }
        return label + key
    }

    private static func physicalKeyLabel(_ key: ghostty_input_key_e) -> String {
        switch key {
        case GHOSTTY_KEY_ENTER: "↩"
        case GHOSTTY_KEY_TAB: "⇥"
        case GHOSTTY_KEY_ESCAPE: "⎋"
        case GHOSTTY_KEY_SPACE: "Space"
        case GHOSTTY_KEY_BACKSPACE: "⌫"
        case GHOSTTY_KEY_ARROW_UP: "↑"
        case GHOSTTY_KEY_ARROW_DOWN: "↓"
        case GHOSTTY_KEY_ARROW_LEFT: "←"
        case GHOSTTY_KEY_ARROW_RIGHT: "→"
        case GHOSTTY_KEY_PAGE_UP: "⇞"
        case GHOSTTY_KEY_PAGE_DOWN: "⇟"
        case GHOSTTY_KEY_HOME: "↖"
        case GHOSTTY_KEY_END: "↘"
        case GHOSTTY_KEY_BRACKET_LEFT: "["
        case GHOSTTY_KEY_BRACKET_RIGHT: "]"
        case GHOSTTY_KEY_COMMA: ","
        case GHOSTTY_KEY_PERIOD: "."
        case GHOSTTY_KEY_SLASH: "/"
        case GHOSTTY_KEY_EQUAL: "="
        case GHOSTTY_KEY_MINUS: "-"
        default: physicalLetterOrDigit(key)
        }
    }

    private static func physicalLetterOrDigit(_ key: ghostty_input_key_e) -> String {
        let letters = GHOSTTY_KEY_A.rawValue ... GHOSTTY_KEY_Z.rawValue
        if letters.contains(key.rawValue), let scalar = Unicode.Scalar(UInt32(65) + key.rawValue - GHOSTTY_KEY_A.rawValue) {
            return String(Character(scalar))
        }
        let digits = GHOSTTY_KEY_DIGIT_0.rawValue ... GHOSTTY_KEY_DIGIT_9.rawValue
        if digits.contains(key.rawValue) {
            return String(key.rawValue - GHOSTTY_KEY_DIGIT_0.rawValue)
        }
        return ""
    }
}

/// Ranks commands for a query: every query character must appear in order in the title
/// (or the description); earlier and denser matches rank higher.
enum CommandMatcher {
    static func filter(_ commands: [TerminalCommand], query: String) -> [TerminalCommand] {
        let needle = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !needle.isEmpty else { return commands }
        return commands
            .compactMap { command -> (TerminalCommand, Int)? in
                if let score = score(needle, in: command.title.lowercased()) {
                    return (command, score)
                }
                if let score = score(needle, in: command.detail.lowercased()) {
                    return (command, score + 1000)
                }
                return nil
            }
            .sorted { $0.1 < $1.1 }
            .map(\.0)
    }

    /// Lower is better; nil when `needle` isn't a subsequence of `haystack`.
    static func score(_ needle: String, in haystack: String) -> Int? {
        if let range = haystack.range(of: needle) {
            return haystack.distance(from: haystack.startIndex, to: range.lowerBound)
        }
        var score = 100
        var index = haystack.startIndex
        var last: String.Index?
        for character in needle {
            guard let found = haystack[index...].firstIndex(of: character) else { return nil }
            if let last {
                score += haystack.distance(from: last, to: found)
            }
            last = found
            index = haystack.index(after: found)
        }
        return score
    }
}

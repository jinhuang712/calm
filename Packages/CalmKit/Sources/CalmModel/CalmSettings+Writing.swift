import Foundation

public extension CalmSettings {
    /// Which states notify (FEATURES.md → F5): *needs you* only, or also *done* and *failed*.
    enum NotifyStates: String, Sendable {
        case needsYou = "needs-you"
        case all
    }

    var notifyStates: NotifyStates {
        values["agents.notify"].flatMap { NotifyStates(rawValue: $0.lowercased()) } ?? .needsYou
    }

    /// Notification sound (default off: UIUX.md → Notifications).
    var notificationSound: Bool {
        bool("agents.sound", default: false)
    }

    /// Send with ⌘ Return (FEATURES.md → F5): ⌘ Return sends an agent's prompt and Return starts a
    /// new line in it, in the agents that can bind ⌘ (`SendKeys`). Off: Return sends, as everywhere.
    var sendWithCommandReturn: Bool {
        bool("agents.send-with-cmd-return", default: false)
    }

    /// The window's background (UIUX.md → Themes): solid, or the system's glass behind a
    /// translucent terminal and sidebar.
    enum WindowBackground: String, Sendable, CaseIterable {
        case solid, glass
    }

    var windowBackground: WindowBackground {
        values["window.background"].flatMap { WindowBackground(rawValue: $0.lowercased()) } ?? .solid
    }

    /// The terminal area runs edge to edge, or floats as a rounded card.
    enum WindowLayout: String, Sendable, CaseIterable {
        case edge, card
    }

    var windowLayout: WindowLayout {
        values["window.layout"].flatMap { WindowLayout(rawValue: $0.lowercased()) } ?? .edge
    }

    /// How large Calm's own interface is drawn (UIUX.md → Accessibility): the sidebar, cards,
    /// Settings and panels, not the terminal, whose text is the Ghostty font's.
    enum InterfaceSize: String, Sendable, CaseIterable {
        case standard, large, larger, largest

        /// Every size and length in the chrome is multiplied by this.
        public var scale: Double {
            switch self {
            case .standard: 1
            case .large: 1.15
            case .larger: 1.3
            case .largest: 1.5
            }
        }
    }

    var interfaceSize: InterfaceSize {
        values["ui-size"].flatMap { InterfaceSize(rawValue: $0.lowercased()) } ?? .standard
    }

    /// How much an agent's card in the sidebar shows (UIUX.md → Session cards): every line, the
    /// state and the recap on one line, or the title alone.
    enum SessionCardSize: String, Sendable, CaseIterable {
        case full, compact, minimal
    }

    var sessionCardSize: SessionCardSize {
        values["sidebar.cards"].flatMap { SessionCardSize(rawValue: $0.lowercased()) } ?? .full
    }

    /// Whether the sidebar's footer (New Session, New Scratch Session, New Project… and their
    /// shortcuts) shows. The footer's own hover handle writes it (UIUX.md → Layout); the
    /// shortcuts and menu items work either way.
    var sidebarFooter: Bool {
        bool("sidebar.footer", default: true)
    }

    /// The cards shrink below the chosen size when the sessions don't fit the sidebar, and grow
    /// back when they do (`SessionCardFit`). Off unless asked for.
    var sessionCardsFit: Bool {
        bool("sidebar.cards-fit", default: false)
    }

    /// The `[section]` a key lives in and its name there: everything before the last dot, so
    /// `agents.claude-code.worktree` is `worktree` in `[agents.claude-code]`.
    private static func sectionAndName(_ key: String) -> (section: String, name: String) {
        guard let dot = key.lastIndex(of: ".") else { return ("", key) }
        return (String(key[..<dot]), String(key[key.index(after: dot)...]))
    }

    /// Sets one key in config.toml text, keeping every other line and comment as it is. `key` is
    /// `section.name` or a top-level `name`; strings are quoted, booleans and numbers aren't.
    static func setting(_ key: String, to value: String, in text: String) -> String {
        let (section, name) = sectionAndName(key)
        let escaped = value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        let rendered = ["true", "false"].contains(value) || Double(value) != nil ? value : "\"\(escaped)\""
        let entry = "\(name) = \(rendered)"
        var lines = text.isEmpty ? [] : text.components(separatedBy: "\n")
        var current = ""
        var sectionEnd: Int?
        for (index, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("["), trimmed.hasSuffix("]") {
                if current == section, sectionEnd == nil, !section.isEmpty {
                    sectionEnd = index
                }
                current = String(trimmed.dropFirst().dropLast()).trimmingCharacters(in: .whitespaces)
                continue
            }
            guard current == section, let equals = trimmed.firstIndex(of: "="),
                  trimmed[..<equals].trimmingCharacters(in: .whitespaces) == name
            else { continue }
            lines[index] = entry
            return lines.joined(separator: "\n")
        }
        if section.isEmpty {
            // Top-level keys go before the first section, after the last top-level line (not after
            // the blank lines that end the file or lead into the section).
            var index = lines.firstIndex { $0.trimmingCharacters(in: .whitespaces).hasPrefix("[") } ?? lines.count
            while index > 0, lines[index - 1].trimmingCharacters(in: .whitespaces).isEmpty {
                index -= 1
            }
            lines.insert(entry, at: index)
        } else if current == section || sectionEnd != nil {
            var index = sectionEnd ?? lines.count
            while index > 0, lines[index - 1].trimmingCharacters(in: .whitespaces).isEmpty {
                index -= 1
            }
            lines.insert(entry, at: index)
        } else {
            if let last = lines.last, !last.isEmpty {
                lines.append("")
            }
            lines.append("[\(section)]")
            lines.append(entry)
        }
        var result = lines.joined(separator: "\n")
        if !result.hasSuffix("\n") {
            result += "\n"
        }
        return result
    }

    /// Removes one key from config.toml text, keeping every other line (the default applies again).
    static func removing(_ key: String, in text: String) -> String {
        let (section, name) = sectionAndName(key)
        var current = ""
        var removed = false
        var lines = text.components(separatedBy: "\n")
        lines.removeAll { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if let header = sectionHeader(trimmed) {
                current = header
                return false
            }
            guard current == section, let equals = trimmed.firstIndex(of: "="),
                  trimmed[..<equals].trimmingCharacters(in: .whitespaces) == name
            else { return false }
            removed = true
            return true
        }
        if removed, !section.isEmpty {
            lines = droppingEmpty(section, from: lines)
        }
        return lines.joined(separator: "\n")
    }

    /// The name inside a `[section]` line, nil for any other line.
    private static func sectionHeader(_ trimmed: String) -> String? {
        guard trimmed.hasPrefix("["), trimmed.hasSuffix("]") else { return nil }
        return String(trimmed.dropFirst().dropLast()).trimmingCharacters(in: .whitespaces)
    }

    /// A section whose last key went goes too, with the blank lines around it, so going back to a
    /// default leaves no bare `[window]` behind. One with anything else left in it, a comment
    /// included, stays.
    private static func droppingEmpty(_ section: String, from lines: [String]) -> [String] {
        let isBlank = { (line: String) in line.trimmingCharacters(in: .whitespaces).isEmpty }
        guard let header = lines.firstIndex(where: { sectionHeader($0.trimmingCharacters(in: .whitespaces)) == section })
        else { return lines }
        var end = header + 1
        while end < lines.count, sectionHeader(lines[end].trimmingCharacters(in: .whitespaces)) == nil {
            guard isBlank(lines[end]) else { return lines }
            end += 1
        }
        var start = header
        while start > 0, isBlank(lines[start - 1]) {
            start -= 1
        }
        var result = lines
        result.removeSubrange(start ..< end)
        if start > 0, end < lines.count {
            result.insert("", at: start) // one blank line between the sections on either side
        } else if end == lines.count, lines.last == "", result.last != "" {
            result.append("") // the file still ends with a newline
        }
        return result
    }

    /// Writes one setting to config.toml (creating it if needed), or removes it for `nil`, and
    /// returns the settings as saved.
    @discardableResult
    static func save(_ key: String, _ value: String?, to url: URL = standardURL) throws -> CalmSettings {
        let text = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        let updated = value.map { setting(key, to: $0, in: text) } ?? removing(key, in: text)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try updated.write(to: url, atomically: true, encoding: .utf8)
        return CalmSettings(text: updated)
    }
}

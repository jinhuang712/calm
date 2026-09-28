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

    /// Sets one key in config.toml text, keeping every other line and comment as it is. `key` is
    /// `section.name` or a top-level `name`; strings are quoted, booleans and numbers aren't.
    static func setting(_ key: String, to value: String, in text: String) -> String {
        let parts = key.split(separator: ".", maxSplits: 1).map(String.init)
        let (section, name) = parts.count == 2 ? (parts[0], parts[1]) : ("", parts[0])
        let rendered = ["true", "false"].contains(value) || Double(value) != nil ? value : "\"\(value)\""
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
        let parts = key.split(separator: ".", maxSplits: 1).map(String.init)
        let (section, name) = parts.count == 2 ? (parts[0], parts[1]) : ("", parts[0])
        var current = ""
        var lines = text.components(separatedBy: "\n")
        lines.removeAll { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("["), trimmed.hasSuffix("]") {
                current = String(trimmed.dropFirst().dropLast()).trimmingCharacters(in: .whitespaces)
                return false
            }
            guard current == section, let equals = trimmed.firstIndex(of: "=") else { return false }
            return trimmed[..<equals].trimmingCharacters(in: .whitespaces) == name
        }
        return lines.joined(separator: "\n")
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

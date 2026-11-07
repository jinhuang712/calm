import Foundation

/// Calm's own settings from `~/.config/calm/config.toml`.
///
/// Only flat `key = value` lines are needed (strings, booleans, numbers), so this reads that
/// subset of TOML: comments with `#`, `[sections]` flatten to `section.key`. Unknown keys are
/// kept, so a future settings screen can write the file back without losing anything.
public struct CalmSettings: Equatable, Sendable {
    public private(set) var values: [String: String] = [:]
    public private(set) var problems: [String] = []

    public init() {}

    public init(text: String) {
        var section = ""
        for (number, rawLine) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
            let line = Self.stripComment(String(rawLine)).trimmingCharacters(in: .whitespaces)
            if line.isEmpty {
                continue
            }
            if line.hasPrefix("["), line.hasSuffix("]") {
                section = String(line.dropFirst().dropLast()).trimmingCharacters(in: .whitespaces)
                continue
            }
            guard let equals = line.firstIndex(of: "=") else {
                problems.append("line \(number + 1): expected key = value")
                continue
            }
            let key = line[..<equals].trimmingCharacters(in: .whitespaces)
            var value = line[line.index(after: equals)...].trimmingCharacters(in: .whitespaces)
            if value.count >= 2, value.hasPrefix("\""), value.hasSuffix("\"") {
                value = Self.unescaped(String(value.dropFirst().dropLast()))
            }
            values[section.isEmpty ? key : "\(section).\(key)"] = value
        }
    }

    /// `~/.config/calm/config.toml`, overridable with `CALM_CONFIG_FILE` (self-tests, development).
    public static var standardURL: URL {
        if let override = ProcessInfo.processInfo.environment["CALM_CONFIG_FILE"], !override.isEmpty {
            return URL(filePath: override)
        }
        return FileManager.default.homeDirectoryForCurrentUser.appending(path: ".config/calm/config.toml")
    }

    public static func load(from url: URL = standardURL) -> CalmSettings {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return CalmSettings() }
        return CalmSettings(text: text)
    }

    public func bool(_ key: String, default fallback: Bool) -> Bool {
        switch values[key]?.lowercased() {
        case "true", "yes", "on", "1": true
        case "false", "no", "off", "0": false
        default: fallback
        }
    }

    public func string(_ key: String) -> String? {
        values[key]
    }

    // MARK: Known settings

    /// Sessions move between projects when their folder changes (specs/FEATURES.md → F2).
    public var autoGrouping: Bool {
        bool("sidebar.auto-grouping", default: true)
    }

    /// Calm asks GitHub once a day whether a newer release is out (specs/FEATURES.md → Updates). Checking
    /// by hand from the Calm menu doesn't depend on it.
    public var checksForUpdates: Bool {
        bool("updates.check", default: true)
    }

    /// What a file opens as, one setting each (specs/FEATURES.md → F8). Pictures include SVG; code includes
    /// any other text file.
    public enum FileKind: String, Sendable, CaseIterable {
        case markdown, html, images, pdf, code

        /// The key under `[files]`: `open-markdown`, `open-html` and so on.
        public var key: String {
            "files.open-" + rawValue
        }
    }

    /// Where a file opens: Calm's viewer, the app macOS picks for it (a browser for a web page), or the editor.
    public enum FileOpener: String, Sendable, CaseIterable {
        case calm
        case system = "default"
        case editor
    }

    /// Where a file of this kind opens. Web pages open in the system's app unless asked otherwise; the
    /// rest open in Calm. An older config's `files.open-in = "editor"` still sends every kind that
    /// isn't set to the editor.
    public func opener(for kind: FileKind) -> FileOpener {
        if let value = values[kind.key]?.lowercased(), let opener = FileOpener(rawValue: value) {
            return opener
        }
        if values["files.open-in"]?.lowercased() == "editor" {
            return .editor
        }
        return kind == .html ? .system : .calm
    }

    public enum MotionLevel: String, Sendable, CaseIterable {
        case full, reduced, off
    }

    /// How much Calm animates (specs/UIUX.md → Motion). The system's Reduce Motion always wins.
    public var motion: MotionLevel {
        values["motion"].flatMap { MotionLevel(rawValue: $0.lowercased()) } ?? .full
    }

    /// A basic TOML string's `\"` and `\\` (an agent's flags can hold quotes); any other escape is
    /// kept as written.
    private static func unescaped(_ value: String) -> String {
        var result = ""
        var escaping = false
        for character in value {
            if escaping {
                if character != "\"", character != "\\" {
                    result.append("\\")
                }
                result.append(character)
                escaping = false
            } else if character == "\\" {
                escaping = true
            } else {
                result.append(character)
            }
        }
        if escaping {
            result.append("\\")
        }
        return result
    }

    private static func stripComment(_ line: String) -> String {
        var inQuotes = false
        var escaping = false
        for (index, character) in line.enumerated() {
            if escaping {
                escaping = false
                continue
            }
            if character == "\\", inQuotes {
                escaping = true
                continue
            }
            if character == "\"" {
                inQuotes.toggle()
            }
            if character == "#", !inQuotes {
                return String(line.prefix(index))
            }
        }
        return line
    }
}

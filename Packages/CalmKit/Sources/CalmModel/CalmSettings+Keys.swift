import Foundation

/// Every key Calm reads from config.toml, for `calm config` (CLI.md → `calm config`): what it takes,
/// what applies when it isn't set, and what it does. A key Calm starts reading goes here too, or
/// `calm config` won't know it; tests check the choices and defaults against the typed accessors.
public extension CalmSettings {
    struct Key: Sendable, Equatable {
        public enum Kind: Sendable, Equatable {
            case bool
            case choice([String])
            /// A theme's name (`ThemeLibrary`).
            case theme
            /// One of the known editors by name, or an application's `.app` path.
            case editor
            /// Anything, written as given (an agent's extra flags).
            case text
        }

        public let name: String
        public let kind: Kind
        /// What applies when config.toml doesn't set it.
        public let defaultValue: String
        public let about: String

        public init(name: String, kind: Kind, defaultValue: String, about: String) {
            self.name = name
            self.kind = kind
            self.defaultValue = defaultValue
            self.about = about
        }

        /// The values it takes, in words.
        public var takes: String {
            switch kind {
            case .bool: "true or false"
            case let .choice(choices): choices.dropLast().joined(separator: ", ") + " or " + (choices.last ?? "")
            case .theme: "a theme's name; unset, the Ghostty config's colors, else Calm"
            case .editor: "automatic, " + Editor.allCases.map(\.rawValue).joined(separator: ", ") + ", or an app's path"
            case .text: "any text, typed as written"
            }
        }
    }

    static let keys: [Key] = [
        Key(
            name: "theme",
            kind: .theme,
            // No value: unset, the Ghostty config's colors apply, else Calm's own theme.
            defaultValue: "",
            about: "The colors of the whole window",
        ),
        Key(
            name: "motion",
            kind: .choice(MotionLevel.allCases.map(\.rawValue)),
            defaultValue: "full",
            about: "How much Calm animates; the system's Reduce Motion always wins",
        ),
        Key(
            name: "ui-size",
            kind: .choice(InterfaceSize.allCases.map(\.rawValue)),
            defaultValue: "standard",
            about: "How large Calm draws its own interface (not the terminal's text)",
        ),
        Key(
            name: "window.background",
            kind: .choice(WindowBackground.allCases.map(\.rawValue)),
            defaultValue: "solid",
            about: "A solid window, or the system's glass behind it",
        ),
        Key(
            name: "window.layout",
            kind: .choice(WindowLayout.allCases.map(\.rawValue)),
            defaultValue: "edge",
            about: "The terminal edge to edge, or a rounded card",
        ),
        Key(
            name: "session-cards",
            kind: .choice(SessionCardSize.allCases.map(\.rawValue)),
            defaultValue: "full",
            about: "How much an agent's card in the sidebar shows",
        ),
        Key(
            name: "session-cards-fit",
            kind: .bool,
            defaultValue: "false",
            about: "Cards shrink while the sessions don't fit the sidebar",
        ),
        Key(
            name: "sidebar.footer",
            kind: .bool,
            defaultValue: "true",
            about: "The ways to start under the sidebar: ⌘N's agent, New Session, Scratch, New Project…, Show Files",
        ),
        Key(
            name: "auto-grouping",
            kind: .bool,
            defaultValue: "true",
            about: "Sessions move between projects when their folder changes",
        ),
        Key(
            name: "editor",
            kind: .editor,
            defaultValue: "automatic",
            about: "The editor files open in",
        ),
        Key(
            name: "open-paths",
            kind: .choice(["viewer", "editor"]),
            defaultValue: "viewer",
            about: "Where ⌘-clicked files open: Calm's viewer, or the editor",
        ),
        Key(
            name: "agents.notify",
            kind: .choice(["needs-you", "all"]),
            defaultValue: "needs-you",
            about: "Which states notify: needs you only, or done and failed too",
        ),
        Key(
            name: "agents.sound",
            kind: .bool,
            defaultValue: "false",
            about: "Notifications play a sound",
        ),
        Key(
            name: "agents.send-with-cmd-return",
            kind: .bool,
            defaultValue: "false",
            about: "⌘ Return sends in Claude Code, OpenCode and pi; Return starts a new line",
        ),
        Key(
            name: "agents.claude-code-hooks",
            kind: .bool,
            defaultValue: "true",
            about: "Claude Code reports through Calm's plugin in Calm's shells",
        ),
        Key(
            name: "agents.new-session",
            kind: .choice(AgentKind.allCases.map(\.configName)),
            defaultValue: AgentKind.claudeCode.configName,
            about: "The agent ⌘N and ⌘⇧N start; unset, Claude Code, or the first agent installed",
        ),
    ] + AgentKind.allCases.flatMap { kind in
        [
            Key(
                name: extraFlagsKey(of: kind),
                kind: .text,
                defaultValue: "",
                about: "More flags \(kind.displayName) starts with on ⌘N, typed as written after its name",
            ),
            Key(
                name: commandKey(of: kind),
                kind: .text,
                defaultValue: "",
                about: "The whole command ⌘N types for \(kind.displayName), as written; set, its flags and options don't apply",
            ),
        ]
    }

    static func key(named name: String) -> Key? {
        keys.first { $0.name == name.lowercased() }
    }

    /// What a `set` does to config.toml.
    enum Change: Sendable, Equatable {
        case write(String)
        /// Back to the default, which Calm applies when the key isn't there, as Settings does.
        case remove
    }

    /// The change for setting `key` to `input`, or why it can't be. `themes` are the names of the
    /// themes there are; nil when they can't be listed, and then any name is taken.
    static func change(_ input: String, for key: Key, themes: [String]? = nil) -> Result<Change, KeyError> {
        let value = input.trimmingCharacters(in: .whitespaces)
        let lowered = value.lowercased()
        switch key.kind {
        case .bool:
            let parsed: String? = switch lowered {
            case "true", "yes", "on", "1": "true"
            case "false", "no", "off", "0": "false"
            default: nil
            }
            guard let parsed else { return .failure(KeyError(key: key, value: value)) }
            return .success(parsed == key.defaultValue ? .remove : .write(parsed))
        case let .choice(choices):
            guard choices.contains(lowered) else { return .failure(KeyError(key: key, value: value)) }
            return .success(lowered == key.defaultValue ? .remove : .write(lowered))
        case .theme:
            // The picker writes the default theme's name too: unset is the Ghostty config's colors.
            guard let themes else { return value.isEmpty ? .failure(KeyError(key: key, value: value)) : .success(.write(value)) }
            guard let name = themes.first(where: { $0.lowercased() == lowered }) else {
                return .failure(KeyError(key: key, value: value, among: themes))
            }
            return .success(.write(name))
        case .text:
            return .success(value.isEmpty ? .remove : .write(value))
        case .editor:
            if lowered == "automatic" {
                return .success(.remove)
            }
            if let editor = Editor(rawValue: lowered) {
                return .success(.write(editor.rawValue))
            }
            guard value.hasSuffix(".app") else { return .failure(KeyError(key: key, value: value)) }
            return .success(.write(value))
        }
    }

    struct KeyError: Error, Sendable, Equatable, CustomStringConvertible {
        public let key: Key
        public let value: String
        public var among: [String]?

        public init(key: Key, value: String, among: [String]? = nil) {
            self.key = key
            self.value = value
            self.among = among
        }

        public var description: String {
            let takes = among.map { "one of " + $0.joined(separator: ", ") } ?? key.takes
            return "\(key.name) can't be '\(value)': it takes \(takes)"
        }
    }

    /// The value in force: what config.toml says, else the default.
    func value(of key: Key) -> String {
        values[key.name].flatMap { $0.isEmpty ? nil : $0 } ?? key.defaultValue
    }
}

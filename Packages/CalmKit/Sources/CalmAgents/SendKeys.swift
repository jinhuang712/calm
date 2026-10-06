import Foundation

/// Send with ⌘ Return (FEATURES.md → F5): the bindings that make ⌘ Return send an agent's prompt
/// and Return start a new line in it, and the file of the agent's own they go in.
///
/// Only the prompt changes. Each agent scopes these bindings to its prompt itself, so every other
/// Return (a question's options and its typed answer, permission prompts, pickers) stays as it was.
/// Calm intercepts no keys: it lets ⌘ Return through to the program (`CalmDefaults`), which gets
/// it as `ESC[13;9u` under the kitty keyboard protocol and as `ESC[27;9;13~` without it; Claude
/// Code, OpenCode and pi read both. Each adapter's bindings were checked against the installed
/// agent in a pty answering as Ghostty does (2026-10-06: Claude Code 2.1.291, OpenCode 2.0.20,
/// pi 0.99.1).
public struct SendKeys: Sendable, Equatable {
    /// An action's keys as the agent's file writes them: one string, or a list.
    public enum Keys: Sendable, Equatable {
        case one(String)
        case several([String])

        var json: Any {
            switch self {
            case let .one(key): key
            case let .several(keys): keys
            }
        }

        func matches(_ value: Any?) -> Bool {
            switch self {
            case let .one(key): (value as? String) == key
            case let .several(keys): (value as? [String]) == keys
            }
        }
    }

    /// One block of Claude Code's `keybindings.json`: keys to actions in one context.
    public struct Block: Sendable, Equatable {
        public let context: String
        public let bindings: [String: String]

        public init(context: String, bindings: [String: String]) {
            self.context = context
            self.bindings = bindings
        }

        var json: [String: Any] {
            ["context": context, "bindings": bindings]
        }

        /// The same block (a block the user edited is theirs).
        func matches(_ value: Any) -> Bool {
            guard let block = value as? [String: Any], block.count == 2 else { return false }
            return block["context"] as? String == context && block["bindings"] as? [String: String] == bindings
        }
    }

    public enum Shape: Sendable, Equatable {
        /// Claude Code: blocks in a `bindings` array. Calm's go first: a block of the user's that
        /// binds the same key in the same context comes later, and the later one wins.
        case blocks([Block])
        /// pi and OpenCode: actions to keys, at the top level or under one key. The actions only
        /// work together, so a value the user set for any of them keeps the agent as it is.
        case actions(under: String?, [String: Keys])
    }

    public let file: URL
    public let shape: Shape
    /// Whether a running agent picks the change up (Claude Code watches its file); the others read
    /// theirs when they start (pi also on `/reload`).
    public let appliesLive: Bool

    public init(file: URL, shape: Shape, appliesLive: Bool) {
        self.file = file
        self.shape = shape
        self.appliesLive = appliesLive
    }

    /// The folder `inherited[variable]` names, else `fallback` under home: where agents look for
    /// their config when an environment variable moves it.
    static func folder(_ variable: String, or fallback: String, home: URL, inherited: [String: String]) -> URL {
        inherited[variable].flatMap { $0.isEmpty ? nil : URL(filePath: $0, directoryHint: .isDirectory) }
            ?? home.appending(path: fallback, directoryHint: .isDirectory)
    }
}

public extension ClaudeCodeAdapter {
    /// `~/.claude/keybindings.json` (or under `CLAUDE_CONFIG_DIR`), which Claude Code re-reads within
    /// seconds. In the prompt (`Chat`) Return inserts a line and ⌘ Return queues the message:
    /// `chat:submit` there did nothing while a `/` or `@` menu was open, `chat:queueSubmit` sends
    /// (or runs the command) either way. In those menus (`Autocomplete`) Return fills in the
    /// suggestion; without it Return would close the menu and add a line. Questions, permission
    /// prompts and pickers have their own contexts and keep Return.
    func sendKeys(home: URL, inherited: [String: String]) -> SendKeys? {
        let folder = SendKeys.folder("CLAUDE_CONFIG_DIR", or: ".claude", home: home, inherited: inherited)
        return SendKeys(
            file: folder.appending(path: "keybindings.json"),
            shape: .blocks([
                SendKeys.Block(context: "Chat", bindings: ["enter": "chat:newline", "cmd+enter": "chat:queueSubmit"]),
                SendKeys.Block(context: "Autocomplete", bindings: ["enter": "autocomplete:accept"]),
            ]),
            appliesLive: true,
        )
    }
}

public extension OpenCodeAdapter {
    /// `keybinds` in `cli.json`, read when OpenCode starts. Return joins the keys that already add a
    /// line; ⌥ Return stays among them, or opentui's own default for it would send. Only the prompt
    /// reads `input.*`: the question tool's own answer, the permission prompt, dialogs and the
    /// `/` and `@` menus keep Return.
    func sendKeys(home: URL, inherited: [String: String]) -> SendKeys? {
        SendKeys(
            file: Self.cliConfigURL(home: home, inherited: inherited),
            shape: .actions(under: "keybinds", [
                "input.submit": .one("super+return"),
                "input.newline": .one("return,shift+return,ctrl+return,alt+return,ctrl+j"),
            ]),
            appliesLive: false,
        )
    }
}

public extension PiAdapter {
    /// `~/.pi/agent/keybindings.json` (or under `PI_CODING_AGENT_DIR`), read when pi starts or on
    /// `/reload`. Return stays in `submit` after ⌘ Return: the editor checks `newLine` first, so it
    /// still adds a line there, while one-line inputs (login, rename) only check `submit` and would
    /// otherwise lose Return. ⌘ Return also confirms a list, so with the `/` menu open it runs the
    /// command instead of sending the half-typed name. Ctrl+S sends in terminals that never report ⌘.
    func sendKeys(home: URL, inherited: [String: String]) -> SendKeys? {
        let folder = SendKeys.folder("PI_CODING_AGENT_DIR", or: ".pi/agent", home: home, inherited: inherited)
        return SendKeys(
            file: folder.appending(path: "keybindings.json"),
            shape: .actions(under: nil, [
                "tui.input.submit": .several(["super+enter", "enter", "ctrl+s"]),
                "tui.input.newLine": .several(["enter", "shift+enter", "ctrl+j"]),
                "tui.select.confirm": .several(["enter", "super+enter"]),
            ]),
            appliesLive: false,
        )
    }
}

/// Puts an agent's `SendKeys` into its file and takes them out again. It only ever adds or removes
/// Calm's own bindings, and it leaves alone a file it can't read as plain JSON (rewriting one with
/// comments would lose them) and an agent whose own keys are set.
public enum SendKeysFile {
    public enum State: Sendable, Equatable {
        /// Calm's bindings aren't in the file.
        case off
        /// They are, and nothing of the user's overrides them.
        case on
        /// The user's own keys decide Return: a later block of theirs (Claude Code), or a value
        /// they set, which Calm leaves in place (pi, OpenCode).
        case ownKeys
        /// The file isn't plain JSON (broken, or with comments), so Calm leaves it as it is.
        case unreadable
    }

    /// What turning the setting on or off does to the file.
    enum Edit {
        case unchanged
        case write([String: Any])
        case delete
    }

    public static func state(of keys: SendKeys) -> State {
        switch read(keys.file) {
        case .missing: .off
        case .unreadable: .unreadable
        case let .object(object): state(keys.shape, object: object)
        }
    }

    /// Adds Calm's bindings (the setting is on) and says where the agent stands.
    @discardableResult
    public static func turnOn(_ keys: SendKeys) throws -> State {
        let object: [String: Any]?
        switch read(keys.file) {
        case .unreadable: return .unreadable
        case .missing: object = nil
        case let .object(existing): object = existing
        }
        let (edit, state) = on(keys.shape, object: object)
        try apply(edit, to: keys.file)
        return state
    }

    /// Takes Calm's bindings out again (the setting is off).
    public static func turnOff(_ keys: SendKeys) throws {
        guard case let .object(object) = read(keys.file) else { return }
        try apply(off(keys.shape, object: object), to: keys.file)
    }

    // MARK: The JSON

    static func state(_ shape: SendKeys.Shape, object: [String: Any]) -> State {
        switch shape {
        case let .blocks(blocks):
            guard let list = object["bindings"] as? [Any] else { return object["bindings"] == nil ? .off : .unreadable }
            guard blocks.allSatisfy({ block in list.contains { block.matches($0) } }) else { return .off }
            return overridden(blocks, in: list) ? .ownKeys : .on
        case let .actions(under, actions):
            guard let container = container(under, in: object) else { return .unreadable }
            if actions.allSatisfy({ $0.value.matches(container[$0.key]) }) {
                return .on
            }
            return actions.contains { container[$0.key] != nil && !$0.value.matches(container[$0.key]) } ? .ownKeys : .off
        }
    }

    static func on(_ shape: SendKeys.Shape, object: [String: Any]?) -> (Edit, State) {
        switch shape {
        case let .blocks(blocks):
            var updated = object ?? [
                "$schema": "https://www.schemastore.org/claude-code-keybindings.json",
                "$docs": "https://code.claude.com/docs/en/keybindings",
            ]
            var list: [Any] = []
            if let value = updated["bindings"] {
                guard let existing = value as? [Any] else { return (.unchanged, .unreadable) }
                list = existing
            }
            let theirs = list.filter { item in !blocks.contains { $0.matches(item) } }
            updated["bindings"] = blocks.map(\.json) + theirs
            let state: State = overridden(blocks, in: theirs) ? .ownKeys : .on
            if let object, NSDictionary(dictionary: object).isEqual(to: updated) {
                return (.unchanged, state)
            }
            return (.write(updated), state)
        case let .actions(under, actions):
            var updated = object ?? [:]
            guard var container = container(under, in: updated) else { return (.unchanged, .unreadable) }
            if actions.contains(where: { container[$0.key] != nil && !$0.value.matches(container[$0.key]) }) {
                return (.unchanged, .ownKeys)
            }
            guard !actions.allSatisfy({ $0.value.matches(container[$0.key]) }) else { return (.unchanged, .on) }
            for (action, keys) in actions {
                container[action] = keys.json
            }
            if let under {
                updated[under] = container
            } else {
                updated = container
            }
            return (.write(updated), .on)
        }
    }

    static func off(_ shape: SendKeys.Shape, object: [String: Any]) -> Edit {
        switch shape {
        case let .blocks(blocks):
            guard let list = object["bindings"] as? [Any] else { return .unchanged }
            let theirs = list.filter { item in !blocks.contains { $0.matches(item) } }
            guard theirs.count < list.count else { return .unchanged }
            // A file holding nothing but Calm's blocks (and the schema links) goes.
            if theirs.isEmpty, Set(object.keys).isSubset(of: ["$schema", "$docs", "bindings"]) {
                return .delete
            }
            var updated = object
            updated["bindings"] = theirs
            return .write(updated)
        case let .actions(under, actions):
            guard var container = container(under, in: object) else { return .unchanged }
            let ours = actions.filter { $0.value.matches(container[$0.key]) }
            guard !ours.isEmpty else { return .unchanged }
            for action in ours.keys {
                container.removeValue(forKey: action)
            }
            var updated = object
            if let under {
                updated[under] = container.isEmpty ? nil : container
            } else {
                updated = container
            }
            return updated.isEmpty ? .delete : .write(updated)
        }
    }

    /// Whether a block of the user's binds Return or ⌘ Return in the prompt to something else, after
    /// Calm's, where it wins.
    static func overridden(_ blocks: [SendKeys.Block], in list: [Any]) -> Bool {
        guard let chat = blocks.first(where: { $0.context == "Chat" }) else { return false }
        let ours = Dictionary(chat.bindings.map { (normalized($0.key), $0.value) }) { first, _ in first }
        return list.contains { item in
            guard let block = item as? [String: Any], !blocks.contains(where: { $0.matches(item) }),
                  block["context"] as? String == chat.context, let bindings = block["bindings"] as? [String: Any]
            else { return false }
            return bindings.contains { key, action in
                guard let wanted = ours[normalized(key)] else { return false }
                return action as? String != wanted
            }
        }
    }

    /// A keystroke as Claude Code reads it: case doesn't matter, modifiers have aliases and any
    /// order, `return` is `enter`.
    static func normalized(_ keystroke: String) -> String {
        let aliases = [
            "command": "cmd", "super": "cmd", "win": "cmd", "control": "ctrl",
            "opt": "alt", "option": "alt", "meta": "alt", "return": "enter",
        ]
        let parts = keystroke.lowercased().split(separator: "+").map { aliases[String($0)] ?? String($0) }
        guard let key = parts.last else { return keystroke }
        return (parts.dropLast().sorted() + [key]).joined(separator: "+")
    }

    private static func container(_ under: String?, in object: [String: Any]) -> [String: Any]? {
        guard let under else { return object }
        guard let value = object[under] else { return [:] }
        return value as? [String: Any]
    }

    // MARK: The file

    enum Contents {
        case missing
        case object([String: Any])
        case unreadable
    }

    /// The file as a JSON object. Strict JSON only: a file with comments (OpenCode and pi accept
    /// some) reads as unreadable, so Calm never rewrites it without them.
    static func read(_ file: URL) -> Contents {
        guard let data = try? Data(contentsOf: file) else {
            return FileManager.default.fileExists(atPath: file.path) ? .unreadable : .missing
        }
        if String(bytes: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true {
            return .missing
        }
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return .unreadable }
        return .object(object)
    }

    private static func apply(_ edit: Edit, to file: URL) throws {
        switch edit {
        case .unchanged:
            return
        case .delete:
            try FileManager.default.removeItem(at: file)
        case let .write(object):
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try (JSONText.text(object) + "\n").write(to: file, atomically: true, encoding: .utf8)
        }
    }
}

/// JSON as people write it by hand: two-space indents, `"key": value`, links unescaped. Keys are
/// sorted so a file always comes out the same, except that `$schema`-style keys lead and a
/// block's `context` comes before its `bindings`, as the agents' own docs write them.
enum JSONText {
    static func text(_ value: Any, indent: String = "") -> String {
        let inner = indent + "  "
        switch value {
        case let object as [String: Any]:
            guard !object.isEmpty else { return "{}" }
            let lines = object.sorted { order($0.key, $1.key) }.map { key, value in
                "\(inner)\(string(key)): \(text(value, indent: inner))"
            }
            return "{\n" + lines.joined(separator: ",\n") + "\n\(indent)}"
        case let array as [Any]:
            guard !array.isEmpty else { return "[]" }
            // A short list of strings stays on one line, as the agents' docs write keys.
            if let strings = array as? [String], strings.count <= 4, strings.allSatisfy({ $0.count <= 24 }) {
                return "[" + strings.map(string).joined(separator: ", ") + "]"
            }
            return "[\n" + array.map { "\(inner)\(text($0, indent: inner))" }.joined(separator: ",\n") + "\n\(indent)]"
        case let string as String:
            return Self.string(string)
        case let number as NSNumber:
            return CFGetTypeID(number) == CFBooleanGetTypeID() ? (number.boolValue ? "true" : "false") : number.stringValue
        default:
            return "null"
        }
    }

    private static func string(_ value: String) -> String {
        let options: JSONSerialization.WritingOptions = [.fragmentsAllowed, .withoutEscapingSlashes]
        guard let data = try? JSONSerialization.data(withJSONObject: value, options: options),
              let text = String(bytes: data, encoding: .utf8)
        else { return "\"\"" }
        return text
    }

    private static func order(_ first: String, _ second: String) -> Bool {
        func rank(_ key: String) -> Int {
            key.hasPrefix("$") ? 0 : key == "context" ? 1 : 2
        }
        return (rank(first), first) < (rank(second), second)
    }
}

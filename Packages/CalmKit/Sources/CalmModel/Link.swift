import Foundation

/// What a ⌘-clicked link points at (FEATURES.md → F8): a URL, or a file with an optional line
/// and column (`path:line[:column]`).
public enum Link: Equatable, Sendable {
    case url(URL)
    case file(path: String, line: Int?, column: Int?)

    /// URL schemes opened as URLs; anything else with a colon is a path (`main.swift:42`).
    static let schemes: Set<String> = [
        "http", "https", "ftp", "ssh", "git", "mailto", "tel", "magnet", "ipfs", "ipns", "gemini", "gopher", "news",
    ]

    /// Reads a link as the terminal matched it. Relative paths resolve against `directory` (the
    /// session's folder); `~` against `home`.
    public static func parse(_ text: String, relativeTo directory: String?, home: String) -> Link? {
        let trimmed = text.trimmingCharacters(in: CharacterSet(charactersIn: " \t\"'`"))
        guard !trimmed.isEmpty else { return nil }
        if let url = URL(string: trimmed), let scheme = url.scheme?.lowercased() {
            if schemes.contains(scheme) {
                return .url(url)
            }
            if scheme == "file" {
                return url.path.isEmpty ? nil : .file(path: url.standardizedFileURL.path, line: nil, column: nil)
            }
        }
        var path = trimmed
        var numbers: [Int] = []
        // Up to two trailing ":<digits>": line, then column.
        while numbers.count < 2, let colon = path.lastIndex(of: ":"),
              let number = Int(path[path.index(after: colon)...]), number > 0 {
            numbers.insert(number, at: 0)
            path = String(path[..<colon])
        }
        guard !path.isEmpty else { return nil }
        if path == "~" || path.hasPrefix("~/") {
            path = home + path.dropFirst()
        } else if !path.hasPrefix("/") {
            guard let directory else { return nil }
            path = (directory as NSString).appendingPathComponent(path)
        }
        return .file(
            path: (path as NSString).standardizingPath,
            line: numbers.first,
            column: numbers.count > 1 ? numbers[1] : nil,
        )
    }

    /// What to try for a link's text, longest first. The terminal lets a path run on across single
    /// spaces (for folders with spaces in their names), which also sweeps up the words after a
    /// plain path ("~/dev/apps and then"); those are dropped one at a time, a few at most.
    public static func candidates(for text: String) -> [String] {
        var candidates = [text]
        var rest = text
        while candidates.count < 5, let space = rest.lastIndex(of: " ") {
            rest = String(rest[..<space])
            if !rest.isEmpty, !rest.hasSuffix(" ") {
                candidates.append(rest)
            }
        }
        return candidates
    }
}

/// Editors Calm can open a file in at a line, and how each takes the position. In detection
/// order: Xcode comes last because `xed` exists on every Mac with Xcode, editor of choice or not.
public enum Editor: String, CaseIterable, Sendable {
    case vscode = "code"
    case cursor
    case trae
    case windsurf
    case zed
    case sublime = "subl"
    case idea
    case xcode = "xed"

    public var displayName: String {
        switch self {
        case .vscode: "Visual Studio Code"
        case .cursor: "Cursor"
        case .trae: "Trae"
        case .windsurf: "Windsurf"
        case .zed: "Zed"
        case .sublime: "Sublime Text"
        case .xcode: "Xcode"
        case .idea: "IntelliJ IDEA"
        }
    }

    /// The app bundles that ship this editor's command-line tool, with the tool's place inside
    /// each. Chosen apps are matched by bundle name, wherever they are installed.
    public var bundledTools: [(app: String, tool: String)] {
        switch self {
        case .vscode: [("Visual Studio Code.app", "Contents/Resources/app/bin/code")]
        case .cursor: [("Cursor.app", "Contents/Resources/app/bin/cursor")]
        case .trae: [("Trae.app", "Contents/Resources/app/bin/trae")]
        case .windsurf: [("Windsurf.app", "Contents/Resources/app/bin/windsurf")]
        case .zed: [("Zed.app", "Contents/MacOS/cli")]
        case .sublime: [("Sublime Text.app", "Contents/SharedSupport/bin/subl")]
        case .idea: [("IntelliJ IDEA.app", "Contents/MacOS/idea"), ("IntelliJ IDEA CE.app", "Contents/MacOS/idea")]
        case .xcode: [("Xcode.app", "Contents/Developer/usr/bin/xed")]
        }
    }

    /// Command-line arguments that open `file` at the position.
    public func arguments(file: String, line: Int?, column: Int?) -> [String] {
        let position = [line.map(String.init), column.map(String.init)].compactMap(\.self).joined(separator: ":")
        let located = position.isEmpty ? file : "\(file):\(position)"
        switch self {
        case .vscode, .cursor, .trae, .windsurf: return ["-g", located] // VS Code and its forks
        case .zed, .sublime: return [located]
        case .xcode: return line.map { ["-l", String($0), file] } ?? [file]
        case .idea: return line.map { ["--line", String($0), file] } ?? [file]
        }
    }
}

/// The `editor` setting: left to Calm, one of the known editors by name, or an application the
/// user chose (its `.app` path). Anything else in config.toml (a path to a tool) reads as automatic.
public enum EditorSetting: Hashable, Sendable {
    case automatic
    case editor(Editor)
    case application(path: String)

    public init(configured: String?) {
        guard let configured, !configured.isEmpty else {
            self = .automatic
            return
        }
        if configured.hasSuffix(".app") {
            self = .application(path: configured)
        } else if let editor = Editor(rawValue: (configured as NSString).lastPathComponent) {
            self = .editor(editor)
        } else {
            self = .automatic
        }
    }

    /// What config.toml holds; nil (automatic) removes the key.
    public var configured: String? {
        switch self {
        case .automatic: nil
        case let .editor(editor): editor.rawValue
        case let .application(path): path
        }
    }

    /// An application's name as the user knows it: "Visual Studio Code" for the bundle
    /// "Visual Studio Code.app".
    public static func applicationName(path: String) -> String {
        ((path as NSString).lastPathComponent as NSString).deletingPathExtension
    }
}

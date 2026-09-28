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

import Foundation

public extension OpenCodeAdapter {
    /// OpenCode's own themes paint every cell in fixed truecolor, so a Calm theme never reached it
    /// (DESIGNS.md → Themes). Its `system` theme is drawn from the terminal's colors instead, so the
    /// shells Calm starts ask for it through `OPENCODE_CLI_CONFIG_CONTENT`, which OpenCode 2 merges
    /// over `cli.json` without writing it; older versions don't read it. A theme the user named in
    /// `cli.json`, or their own value of the variable, is left alone. While the variable is set it
    /// outranks the file, so a theme picked inside OpenCode shows from the next session on.
    func shellEnvironment(home: URL, inherited: [String: String]) -> [String: String] {
        if let own = inherited[Self.cliConfigVariable], !own.isEmpty {
            return [:]
        }
        if Self.namesTheme(cliConfig: Self.cliConfigURL(home: home, inherited: inherited)) {
            return [:]
        }
        return [Self.cliConfigVariable: Self.systemTheme]
    }

    internal static let cliConfigVariable = "OPENCODE_CLI_CONFIG_CONTENT"
    internal static let systemTheme = #"{"theme":{"name":"system"}}"#

    /// Where OpenCode 2 keeps `cli.json`: `$OPENCODE_CONFIG_DIR`, else `$XDG_CONFIG_HOME/opencode`,
    /// else `~/.config/opencode` (read from 2.0.19's source).
    internal static func cliConfigURL(home: URL, inherited: [String: String]) -> URL {
        let set = { (name: String) in inherited[name].flatMap { $0.isEmpty ? nil : URL(filePath: $0) } }
        let folder = set("OPENCODE_CONFIG_DIR")
            ?? set("XDG_CONFIG_HOME")?.appending(path: "opencode")
            ?? home.appending(path: ".config/opencode")
        return folder.appending(path: "cli.json")
    }

    /// Whether the file names a theme (`theme.name`; a `mode` alone keeps OpenCode's default theme).
    /// The file is JSONC. One that can't be read names none: OpenCode ignores it too.
    internal static func namesTheme(cliConfig url: URL) -> Bool {
        guard let data = try? Data(contentsOf: url),
              let config = try? JSONSerialization.jsonObject(with: data, options: .json5Allowed) as? [String: Any],
              let theme = config["theme"] as? [String: Any]
        else { return false }
        return theme["name"] is String
    }
}

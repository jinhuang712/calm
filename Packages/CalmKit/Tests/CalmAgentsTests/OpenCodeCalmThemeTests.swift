@testable import CalmAgents
import CalmModel
import Foundation
import Testing

/// Calm's own OpenCode theme (`themes/calm.json`) and how Calm keeps it in step.
struct OpenCodeCalmThemeTests {
    private let adapter = OpenCodeAdapter()

    /// Calm's default theme, from `Calm/Resources/Themes/calm.toml`.
    private let dark = CalmTheme.Colors(
        background: "#292a2c", foreground: "#b2b4b7", cursor: "#94a7bb", selection: "#404143",
        palette: [
            "#3e4042", "#bf9490", "#8ca98c", "#ad9f7b", "#88a3c0", "#b395b0", "#7aabaa", "#a2a5a8",
            "#7a7c7e", "#ce9f9b", "#97b697", "#bbab84", "#92b0cf", "#c1a0bd", "#82b8b7", "#bbbec1",
        ],
        sidebar: "#222325", accent: "#92aecb",
    )
    private let light = CalmTheme.Colors(
        background: "#ecedee", foreground: "#545557", cursor: "#495d72", selection: "#d2d2d4",
        palette: [
            "#474849", "#905c57", "#527752", "#7d6a3a", "#4c6f93", "#835d7f", "#327878", "#c8c9ca",
            "#7f8082", "#804945", "#3f6640", "#6c5824", "#385e83", "#734b6f", "#136868", "#dfe0e1",
        ],
        sidebar: "#e4e5e7", accent: "#5d7792",
    )

    private func temporaryHome() throws -> URL {
        let home = FileManager.default.temporaryDirectory.appending(path: "calm-home-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        return home
    }

    private func write(_ text: String, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
    }

    private func connect(in home: URL) throws {
        guard case let .files(files) = adapter.setup else { Issue.record("OpenCode connects through files"); return }
        try AgentSetupFiles.install(files, home: home)
    }

    private func theme(_ colors: CalmTheme.Colors, _ mode: CalmTheme.Mode) throws -> [String: Any] {
        let text = try #require(adapter.themeFile(for: colors, mode: mode))
        return try #require(try JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
    }

    private func hues(_ theme: [String: Any], _ mode: CalmTheme.Mode) throws -> [String: Any] {
        let variant = try #require(theme[mode.rawValue] as? [String: Any])
        return try #require(variant["hue"] as? [String: Any])
    }

    /// `$hue.<name>.<step>` resolved through the aliases (`accent`, `interactive`, `neutral`).
    private func resolve(_ reference: String, in hues: [String: Any]) -> String? {
        let parts = reference.split(separator: ".").map(String.init)
        guard parts.count == 3, parts[0] == "$hue" else { return nil }
        var name = parts[1]
        if let alias = hues[name] as? String {
            name = String(alias.dropFirst("$hue.".count))
        }
        return (hues[name] as? [String: String])?[parts[2]]
    }

    private func isColor(_ text: String?) -> Bool {
        guard let text, text.count == 7, text.hasPrefix("#") else { return false }
        return text.dropFirst().allSatisfy(\.isHexDigit)
    }

    private func references(in value: Any) -> [String] {
        switch value {
        case let text as String: text.hasPrefix("$hue.") ? [text] : []
        case let object as [String: Any]: object.values.flatMap(references)
        case let list as [Any]: list.flatMap(references)
        default: []
        }
    }

    @Test func `the theme holds one appearance, the one on screen, and says Calm wrote it`() throws {
        let dark = try theme(dark, .dark)
        #expect(Set(dark.keys) == ["$schema", "$comment", "base", "dark"])
        #expect((dark["$comment"] as? String)?.contains(AgentSetup.marker) == true)
        #expect(try Set(theme(light, .light).keys) == ["$schema", "$comment", "base", "light"])
        // Stable text, so an unchanged theme never rewrites the file.
        #expect(adapter.themeFile(for: self.dark, mode: .dark) == adapter.themeFile(for: self.dark, mode: .dark))
    }

    @Test func `every role points at a color the scales define`() throws {
        for (colors, mode) in [(dark, CalmTheme.Mode.dark), (light, .light)] {
            let theme = try theme(colors, mode)
            let hues = try hues(theme, mode)
            let references = try references(in: #require(theme["base"]))
            #expect(references.count > 40)
            for reference in references {
                #expect(isColor(resolve(reference, in: hues)), "\(mode) \(reference)")
            }
            let base = try #require(theme["base"] as? [String: Any])
            for name in try #require(base["categorical"] as? [String]) {
                #expect(hues[name] is [String: String], "\(name)")
            }
        }
    }

    @Test func `the accent is Calm's, dim text is dimmer, and boxes barely lift`() throws {
        for (colors, mode) in [(dark, CalmTheme.Mode.dark), (light, .light)] {
            let hues = try hues(theme(colors, mode), mode)
            let base = try #require(try theme(colors, mode)["base"] as? [String: Any])
            // Build, OpenCode's first agent, takes the first categorical hue: Calm's accent.
            let first = try #require((base["categorical"] as? [String])?.first)
            #expect(resolve("$hue.\(first).200", in: hues) == colors.accent)
            let gray = try #require(hues["gray"] as? [String: String])
            let background = colors.background
            let text = try #require(gray["200"]), dim = try #require(gray["400"]), strong = try #require(gray["100"])
            #expect(text == colors.foreground)
            #expect(CalmTheme.contrast(dim, background) < CalmTheme.contrast(text, background) * 0.75, "\(mode)")
            #expect(CalmTheme.contrast(strong, background) > CalmTheme.contrast(text, background), "\(mode)")
            #expect(try CalmTheme.contrast(#require(gray["700"]), background) < 1.2, "\(mode)")
            #expect((base["background"] as? [String: Any])?["base"] as? String == "transparent")
        }
    }

    @Test func `a theme with a short palette and no accent still makes a whole theme`() throws {
        let colors = CalmTheme.Colors(background: "#1e1e1e", foreground: "#d0d0d0", palette: ["#000000", "#cc6666", "#88aa88"])
        let theme = try theme(colors, .dark)
        let hues = try hues(theme, .dark)
        for reference in try references(in: #require(theme["base"])) {
            #expect(isColor(resolve(reference, in: hues)), "\(reference)")
        }
    }

    @Test func `the theme is written while OpenCode is connected, and only then`() throws {
        let home = try temporaryHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let file = home.appending(path: ".config/opencode/themes/calm.json")
        // Not connected: nothing written.
        #expect(try AgentSetupFiles.syncTheme(for: adapter, colors: (dark, .dark), home: home) == false)
        #expect(!FileManager.default.fileExists(atPath: file.path))
        try connect(in: home)
        #expect(try AgentSetupFiles.syncTheme(for: adapter, colors: (dark, .dark), home: home))
        #expect(try String(contentsOf: file, encoding: .utf8) == adapter.themeFile(for: dark, mode: .dark))
        // Unchanged colors leave the file alone; new ones (another appearance) rewrite it.
        #expect(try AgentSetupFiles.syncTheme(for: adapter, colors: (dark, .dark), home: home) == false)
        #expect(try AgentSetupFiles.syncTheme(for: adapter, colors: (light, .light), home: home))
        #expect(try String(contentsOf: file, encoding: .utf8) == adapter.themeFile(for: light, mode: .light))
        // The user's own Ghostty colors on screen: Calm's theme goes, and OpenCode falls back to system.
        #expect(try AgentSetupFiles.syncTheme(for: adapter, colors: nil, home: home))
        #expect(!FileManager.default.fileExists(atPath: file.path))
    }

    @Test func `disconnecting takes the theme away`() throws {
        let home = try temporaryHome()
        defer { try? FileManager.default.removeItem(at: home) }
        try connect(in: home)
        try AgentSetupFiles.syncTheme(for: adapter, colors: (dark, .dark), home: home)
        guard case let .files(files) = adapter.setup else { return }
        try AgentSetupFiles.remove(files, home: home)
        #expect(try AgentSetupFiles.syncTheme(for: adapter, colors: (dark, .dark), home: home))
        #expect(!FileManager.default.fileExists(atPath: home.appending(path: ".config/opencode/themes/calm.json").path))
    }

    @Test func `a calm theme the user made is never touched`() throws {
        let home = try temporaryHome()
        defer { try? FileManager.default.removeItem(at: home) }
        try connect(in: home)
        let file = home.appending(path: ".config/opencode/themes/calm.json")
        let own = #"{ "base": {} }"#
        try write(own, to: file)
        #expect(try AgentSetupFiles.syncTheme(for: adapter, colors: (dark, .dark), home: home) == false)
        #expect(try AgentSetupFiles.syncTheme(for: adapter, colors: nil, home: home) == false)
        #expect(try String(contentsOf: file, encoding: .utf8) == own)
        // And OpenCode isn't pointed at it: it isn't Calm's theme.
        #expect(adapter.shellEnvironment(home: home, inherited: [:])["OPENCODE_CLI_CONFIG_CONTENT"] == OpenCodeAdapter.systemTheme)
    }

    @Test func `with Calm's theme there, OpenCode is asked for it`() throws {
        let home = try temporaryHome()
        defer { try? FileManager.default.removeItem(at: home) }
        try connect(in: home)
        try AgentSetupFiles.syncTheme(for: adapter, colors: (dark, .dark), home: home)
        #expect(adapter.shellEnvironment(home: home, inherited: [:])["OPENCODE_CLI_CONFIG_CONTENT"] == OpenCodeAdapter.calmTheme)
        // A theme the user named still wins.
        try write(#"{ "theme": { "name": "nord" } }"#, to: home.appending(path: ".config/opencode/cli.json"))
        #expect(adapter.shellEnvironment(home: home, inherited: [:]).isEmpty)
    }

    @Test func `other agents have no theme file`() throws {
        let home = try temporaryHome()
        defer { try? FileManager.default.removeItem(at: home) }
        for adapter in Agents.adapters where adapter.kind != .openCode {
            #expect(adapter.themeFilePath == nil)
            #expect(try AgentSetupFiles.syncTheme(for: adapter, colors: (dark, .dark), home: home) == false)
        }
    }

    @Test func `the plugin reloads OpenCode's themes only while OpenCode listens for it`() {
        let source = OpenCodeAdapter.pluginSource
        #expect(source.contains(#"new URL("../../themes/", import.meta.url)"#))
        #expect(source.contains(#"if (name && name !== "calm.json") return;"#))
        #expect(source.contains(#"if (process.listenerCount("SIGUSR2") > 0) process.kill(process.pid, "SIGUSR2");"#))
        #expect(source.contains("followTheme(),"))
    }
}

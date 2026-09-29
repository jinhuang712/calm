@testable import CalmAgents
import CalmModel
import Foundation
import Testing

/// Calm's own pi theme (`themes/calm.json`) and the extension that dresses pi in it.
struct PiCalmThemeTests {
    private let adapter = PiAdapter()

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

    private func theme(_ colors: CalmTheme.Colors, _ mode: CalmTheme.Mode) throws -> [String: Any] {
        let text = try #require(adapter.themeFile(for: colors, mode: mode))
        return try #require(try JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
    }

    /// pi 0.99.1's own `theme-schema.json`.
    private func schema() throws -> [String: Any] {
        let url = try #require(Bundle.module.url(forResource: "theme-schema", withExtension: "json", subdirectory: "Fixtures/pi"))
        return try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
    }

    private func isColor(_ value: Any?) -> Bool {
        guard let text = value as? String, text.count == 7, text.hasPrefix("#") else { return false }
        return text.dropFirst().allSatisfy(\.isHexDigit)
    }

    @Test func `the theme has every color pi's schema names, and no key it doesn't`() throws {
        let schema = try schema()
        let properties = try #require(schema["properties"] as? [String: Any])
        let colorSchema = try #require(properties["colors"] as? [String: Any])
        let required = try #require(colorSchema["required"] as? [String])
        let allowed = try Set(#require(colorSchema["properties"] as? [String: Any]).keys)
        for (colors, mode) in [(dark, CalmTheme.Mode.dark), (light, .light)] {
            let theme = try theme(colors, mode)
            // The schema allows no other key, and pi rejects a theme that breaks it.
            #expect(Set(theme.keys).isSubset(of: Set(properties.keys)), "\(mode)")
            let written = try #require(theme["colors"] as? [String: Any])
            #expect(Set(required).isSubset(of: Set(written.keys)), "\(mode)")
            #expect(Set(written.keys) == allowed, "\(mode): every color, optional ones too")
            for (key, value) in written {
                #expect(isColor(value), "\(mode) \(key)")
            }
            #expect(theme["name"] as? String == "calm")
            #expect(theme["appearance"] as? String == mode.rawValue)
            let vars = try #require(theme["vars"] as? [String: String])
            #expect(vars["calm"]?.contains(AgentSetup.marker) == true)
            // No color refers to a variable: the extension builds the theme from the file as is.
            #expect(!written.values.contains { ($0 as? String) == "calm" })
        }
        #expect(adapter.themeFile(for: dark, mode: .dark) == adapter.themeFile(for: dark, mode: .dark))
    }

    @Test func `the accent frames the prompt, dim text is dimmer, and boxes barely lift`() throws {
        for (colors, mode) in [(dark, CalmTheme.Mode.dark), (light, .light)] {
            let written = try #require(try theme(colors, mode)["colors"] as? [String: String])
            let background = colors.background
            #expect(written["accent"] == colors.accent)
            #expect(written["borderAccent"] == colors.accent)
            #expect(written["thinkingXhigh"] == colors.accent)
            let text = try #require(written["text"]), muted = try #require(written["muted"]), dim = try #require(written["dim"])
            #expect(CalmTheme.contrast(muted, background) < CalmTheme.contrast(text, background), "\(mode)")
            #expect(CalmTheme.contrast(dim, background) < CalmTheme.contrast(muted, background), "\(mode)")
            #expect(try CalmTheme.contrast(#require(written["mdHeading"]), background) > CalmTheme.contrast(text, background), "\(mode)")
            #expect(try CalmTheme.contrast(#require(written["userMessageBg"]), background) < 1.2, "\(mode)")
            #expect(try CalmTheme.contrast(#require(written["toolPendingBg"]), background) < 1.2, "\(mode)")
        }
    }

    @Test func `a theme with a short palette and no accent still makes a whole theme`() throws {
        let colors = CalmTheme.Colors(background: "#1e1e1e", foreground: "#d0d0d0", palette: ["#000000", "#cc6666"])
        let written = try #require(try theme(colors, .dark)["colors"] as? [String: Any])
        #expect(written.values.allSatisfy(isColor))
    }

    @Test func `pi's theme is written while pi is connected`() throws {
        let home = try temporaryHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let file = home.appending(path: ".pi/agent/themes/calm.json")
        #expect(try AgentSetupFiles.syncTheme(for: adapter, colors: (dark, .dark), home: home) == false)
        guard case let .files(files) = adapter.setup else { Issue.record("pi connects through a file"); return }
        try AgentSetupFiles.install(files, home: home)
        #expect(try AgentSetupFiles.syncTheme(for: adapter, colors: (dark, .dark), home: home))
        #expect(try String(contentsOf: file, encoding: .utf8) == adapter.themeFile(for: dark, mode: .dark))
        try AgentSetupFiles.remove(files, home: home)
        #expect(try AgentSetupFiles.syncTheme(for: adapter, colors: (dark, .dark), home: home))
        #expect(!FileManager.default.fileExists(atPath: file.path))
    }

    @Test func `the extension sets Calm's theme as an object, over pi's built-ins only`() {
        let source = PiAdapter.extensionSource
        // Inside Calm only, like the reports.
        #expect(source.contains("if (!cli || !process.env.CALM_SESSION_ID) return;"))
        #expect(source.contains(#"pi.on("session_start", (_event: any, ctx: any) => {"#))
        #expect(source.contains("if (!ctx?.hasUI) return;"))
        // pi's built-ins give way; a theme the user made stays.
        #expect(source.contains(#"const builtIn = new Set(["system", "dark", "light", "calm"]);"#))
        #expect(source.contains("!builtIn.has(current.name)) return;"))
        // A theme object (pi saves a name to settings.json), built with the class of the one in use.
        #expect(source
            .contains(#"ui.setTheme(new current.constructor(fg, bg, current.mode, { name: "calm", appearance: file.appearance }));"#))
        #expect(!source.contains(#"setTheme("calm")"#))
        // pi's background roles (0.99.1's BACKGROUND_TOKENS).
        let roles = ["selectedBg", "searchMatchBg", "userMessageBg", "customMessageBg", "toolPendingBg", "toolSuccessBg", "toolErrorBg"]
        #expect(source.contains("const backgrounds = new Set([\n    " + roles.map { "\"\($0)\"" }.joined(separator: ", ") + ",\n  ]);"))
        // Calm rewrites the file on a theme or appearance change; the extension applies it again.
        #expect(source.contains(#"if (name && name !== "calm.json") return;"#))
        #expect(source.contains("timer = setTimeout(wearCalm, 150);"))
        #expect(!source.contains("await "))
    }
}

import AppKit
@testable import Calm
import CalmModel
import Foundation
import Testing

@MainActor
struct TerminalThemeTests {
    let library = ThemeLibrary(themes: [
        CalmTheme(
            name: "Calm",
            light: .init(background: "#f6f4f1", foreground: "#4f4d4a", palette: [], sidebar: "#efecea"),
            dark: .init(background: "#211d1a", foreground: "#c2bdb7", palette: [], sidebar: "#1b1814"),
        ),
        CalmTheme(name: "Sage", light: nil, dark: .init(background: "#19201a", foreground: "#b5c1b7", palette: [])),
    ])

    private func folder() -> URL {
        FileManager.default.temporaryDirectory.appending(path: "calm-theme-\(UUID().uuidString)")
    }

    @Test func `no theme picked: the default, as a light and dark pair in Calm's defaults`() throws {
        let directory = folder()
        defer { try? FileManager.default.removeItem(at: directory) }
        let settings = CalmSettings()
        #expect(TerminalTheme.active(settings: settings, in: library)?.picked == false)
        let lines = TerminalTheme.defaultLines(settings: settings, directory: directory, library: library)
        let dark = directory.appending(path: "themes/calm-dark")
        let light = directory.appending(path: "themes/calm-light")
        #expect(lines == ["theme = light:\(light.path),dark:\(dark.path)"])
        #expect(try String(contentsOf: dark, encoding: .utf8) == "background = #211d1a\nforeground = #c2bdb7\n")
        #expect(TerminalTheme.choicesFile(settings: settings, directory: directory, library: library) == nil)
    }

    @Test func `a picked theme: plain colors for the current appearance, loaded last`() throws {
        let directory = folder()
        defer { try? FileManager.default.removeItem(at: directory) }
        let settings = CalmSettings(text: "theme = \"sage\"\n")
        #expect(TerminalTheme.active(settings: settings, in: library)?.theme.name == "Sage")
        #expect(TerminalTheme.defaultLines(settings: settings, directory: directory, library: library).isEmpty)
        // Sage has only a dark variant, which then serves light too.
        let file = try #require(TerminalTheme.choicesFile(settings: settings, directory: directory, library: library, dark: false))
        let lines = try String(contentsOf: file, encoding: .utf8).split(separator: "\n").map(String.init)
        #expect(lines.first?.hasPrefix("# Written by Calm") == true)
        #expect(lines.filter { !$0.hasPrefix("#") } == ["background = #19201a", "foreground = #b5c1b7"])
    }

    @Test func `a glass window: the terminal's opacity joins Calm's choices`() throws {
        let directory = folder()
        defer { try? FileManager.default.removeItem(at: directory) }
        let settings = CalmSettings(text: "[window]\nbackground = \"glass\"\n")
        let file = try #require(TerminalTheme.choicesFile(settings: settings, directory: directory, library: library))
        let lines = try String(contentsOf: file, encoding: .utf8).split(separator: "\n").filter { !$0.hasPrefix("#") }
        #expect(lines == ["background-opacity = \(TerminalTheme.glassOpacity)"])
    }

    @Test func `an unknown theme falls back to the default`() {
        let active = TerminalTheme.active(settings: CalmSettings(text: "theme = \"Nope\"\n"), in: library)
        #expect(active?.theme.name == "Calm")
        #expect(active?.picked == false)
    }

    @Test func `the chrome follows the theme only when its background is on screen`() throws {
        let theme = try #require(library.theme(named: "Calm")?.dark)
        let style = try SidebarStyle.derived(from: #require(NSColor(hex: "#211d1a")), theme: theme)
        #expect(NSColor(style.background).hexString == "#1b1814")
        #expect(NSColor(style.primary).hexString == "#c2bdb7")
        let derived = try SidebarStyle.derived(from: #require(NSColor(hex: "#211d1a")))
        #expect(NSColor(derived.background).hexString != "#1b1814")
        #expect(NSColor(hex: "#1e1e2e")?.hexString == "#1e1e2e")
    }

    @Test func `needs you stays amber whatever the theme's accent`() throws {
        // Ink's dark variant: its blue accent is almost *working*'s hue.
        let theme = CalmTheme.Colors(background: "#1d1e20", foreground: "#bcbec1", accent: "#89afd6")
        let background = try #require(NSColor(hex: theme.background))
        let style = SidebarStyle.derived(from: background, theme: theme)
        #expect(NSColor(style.accent).hexString == theme.accent)
        #expect(NSColor(style.attention).hexString == NSColor(SidebarStyle.derived(from: background).attention).hexString)
        #expect(NSColor(style.attention).hexString != theme.accent)
    }
}

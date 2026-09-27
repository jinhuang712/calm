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
        #expect(TerminalTheme.pickedFile(settings: settings, directory: directory, library: library) == nil)
    }

    @Test func `a picked theme: plain colors for the current appearance, loaded last`() throws {
        let directory = folder()
        defer { try? FileManager.default.removeItem(at: directory) }
        let settings = CalmSettings(text: "theme = \"sage\"\n")
        #expect(TerminalTheme.active(settings: settings, in: library)?.theme.name == "Sage")
        #expect(TerminalTheme.defaultLines(settings: settings, directory: directory, library: library).isEmpty)
        // Sage has only a dark variant, which then serves light too.
        let file = try #require(TerminalTheme.pickedFile(settings: settings, directory: directory, library: library, dark: false))
        let lines = try String(contentsOf: file, encoding: .utf8).split(separator: "\n").map(String.init)
        #expect(lines.first?.hasPrefix("# Written by Calm") == true)
        #expect(Array(lines.dropFirst()) == ["background = #19201a", "foreground = #b5c1b7"])
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
}

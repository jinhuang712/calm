@testable import CalmModel
import Foundation
import Testing

struct ThemeTests {
    static let palette = "#000000, #110000, #001100, #111100, #000011, #110011, #001111, #cccccc, "
        + "#333333, #ff0000, #00ff00, #ffff00, #0000ff, #ff00ff, #00ffff, #ffffff"

    let text = """
    # A test theme
    name = "Moss"

    [dark]
    background = "#1a1f1b"
    foreground = "C0C8C1"
    cursor = "#aabbaa"
    selection = "#303830"
    palette = "\(palette)"
    accent = "#8fae96"

    [light]
    background = "#f3f5f3"
    foreground = "#444a45"
    """

    @Test func `a theme file: both variants, colors normalized`() throws {
        var problems: [String] = []
        let theme = try #require(CalmTheme(text: text, fallbackName: "moss-file", problems: &problems))
        #expect(problems.isEmpty)
        #expect(theme.name == "Moss")
        #expect(theme.id == "moss")
        #expect(theme.dark?.foreground == "#c0c8c1")
        #expect(theme.dark?.palette.count == 16)
        #expect(theme.dark?.accent == "#8fae96")
        #expect(theme.dark?.sidebar == nil)
        #expect(theme.light?.palette.isEmpty == true)
        #expect(theme.light?.cursor == nil)
    }

    @Test func `the terminal part as Ghostty config lines`() throws {
        var problems: [String] = []
        let theme = try #require(CalmTheme(text: text, fallbackName: "x", problems: &problems))
        let dark = try CalmTheme.ghosttyLines(#require(theme.dark))
        #expect(Array(dark.prefix(6)) == [
            "background = #1a1f1b", "foreground = #c0c8c1", "cursor-color = #aabbaa",
            "selection-background = #303830", "selection-foreground = #c0c8c1", "palette = 0=#000000",
        ])
        #expect(dark.last == "palette = 15=#ffffff")
        #expect(try CalmTheme.ghosttyLines(#require(theme.light)) == ["background = #f3f5f3", "foreground = #444a45"])
    }

    @Test func `bad colors degrade: dropped or the variant left out, with a problem each`() throws {
        var problems: [String] = []
        let theme = try #require(CalmTheme(text: """
        [dark]
        background = "#111111"
        foreground = "#dddddd"
        cursor = "red"
        palette = "#000000, #111111"
        [light]
        background = "#ffffff"
        """, fallbackName: "half", problems: &problems))
        #expect(theme.name == "half")
        #expect(theme.dark?.cursor == nil)
        #expect(theme.dark?.palette.isEmpty == true)
        #expect(theme.light == nil)
        #expect(theme.colors(for: .light) == theme.dark) // a single variant serves both
        #expect(Set(problems) == [
            "dark.cursor: not a #rrggbb color",
            "dark.palette: needs 16 colors, found 2",
            "light: needs a background and a foreground",
        ])

        var more: [String] = []
        #expect(CalmTheme(text: "name = \"Empty\"", fallbackName: "e", problems: &more) == nil)
        #expect(more == ["no usable [light] or [dark] colors"])
    }

    @Test func `a user theme replaces a built-in of the same name`() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "calm-themes-\(UUID().uuidString)")
        let builtIn = root.appending(path: "builtin")
        let user = root.appending(path: "user")
        defer { try? FileManager.default.removeItem(at: root) }
        for folder in [builtIn, user] {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        }
        try text.write(to: builtIn.appending(path: "moss.toml"), atomically: true, encoding: .utf8)
        try "name = \"Fern\"\n[dark]\nbackground = \"#101010\"\nforeground = \"#d0d0d0\"\n"
            .write(to: builtIn.appending(path: "fern.toml"), atomically: true, encoding: .utf8)
        try "name = \"moss\"\n[dark]\nbackground = \"#222222\"\nforeground = \"#eeeeee\"\n"
            .write(to: user.appending(path: "mine.toml"), atomically: true, encoding: .utf8)
        try "[dark]\nbackground = \"nope\"\n".write(to: user.appending(path: "broken.toml"), atomically: true, encoding: .utf8)

        let library = ThemeLibrary(folders: [builtIn, user, root.appending(path: "missing")])
        #expect(library.themes.map(\.name) == ["Fern", "moss"])
        #expect(library.theme(named: "MOSS")?.dark?.background == "#222222")
        #expect(library.problems.allSatisfy { $0.hasPrefix("broken.toml: ") })
        #expect(library.problems.count == 3)
    }

    @Test func `the Ghostty theme a Ghostty config sets`() {
        #expect(CalmTheme.ghosttyThemePair(configText: "font-size = 13\n") == nil)
        let single = CalmTheme.ghosttyThemePair(configText: "theme = Nord\n")
        #expect(single?.light == "Nord" && single?.dark == "Nord")
        let pair = CalmTheme.ghosttyThemePair(configText: """
        # theme = Old
        theme = "Old"
        theme = light:Paper Light, dark:Ink Dark
        """)
        #expect(pair?.light == "Paper Light" && pair?.dark == "Ink Dark")
        let darkOnly = CalmTheme.ghosttyThemePair(configText: "theme = dark:Night\n")
        #expect(darkOnly?.light == "Night" && darkOnly?.dark == "Night")
        #expect(CalmTheme.ghosttyThemePair(configText: "theme = Nord\ntheme =\n") == nil) // reset
    }

    // MARK: The built-in set

    private static let builtInFolder = URL(filePath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent() // CalmKit
        .deletingLastPathComponent().deletingLastPathComponent() // the repository
        .appending(path: "Calm/Resources/Themes")

    @Test func `the built-in themes: five soft pairs within the contrast range`() throws {
        let library = ThemeLibrary(folders: [Self.builtInFolder])
        #expect(library.problems.isEmpty)
        #expect(library.themes.map(\.name).sorted() == ["Calm", "Dusk", "Forest", "Ink", "Plum"])
        #expect(library.theme(named: ThemeLibrary.defaultName) != nil)
        for theme in library.themes {
            for mode in CalmTheme.Mode.allCases {
                let colors = try #require(mode == .light ? theme.light : theme.dark, "\(theme.name) \(mode)")
                #expect(colors.palette.count == 16)
                #expect(colors.sidebar != nil && colors.accent != nil && colors.cursor != nil && colors.selection != nil)
                // UIUX.md → Color: soft, roughly 6:1 to 11:1 between text and background.
                let text = Self.contrast(colors.foreground, colors.background)
                #expect((6 ... 11).contains(text), "\(theme.name) \(mode): text contrast \(text)")
                // The six hues, normal and bright, stay legible.
                for index in [1, 2, 3, 4, 5, 6, 9, 10, 11, 12, 13, 14] {
                    let ratio = Self.contrast(colors.palette[index], colors.background)
                    #expect(ratio >= 3.8, "\(theme.name) \(mode): color \(index) contrast \(ratio)")
                }
                // Bright white stays a small step above the text, never a jump toward white:
                // agents draw emphasis, and some their body text, in it.
                if mode == .dark {
                    let brightWhite = Self.contrast(colors.palette[15], colors.background)
                    #expect(brightWhite <= text * 1.2, "\(theme.name): bright white \(brightWhite), text \(text)")
                }
            }
        }
    }

    @Test func `with Increase Contrast every text color reaches 4.5:1, and dim stays dimmer than text`() throws {
        let library = ThemeLibrary(folders: [Self.builtInFolder])
        for theme in library.themes {
            for mode in CalmTheme.Mode.allCases {
                let colors = try #require(theme.colors(for: mode)).contrasted()
                let text = Self.contrast(colors.foreground, colors.background)
                #expect(text >= 4.5, "\(theme.name) \(mode): text \(text)")
                let textIndices = mode == .dark ? Array(1 ... 15) : [1, 2, 3, 4, 5, 6, 8, 9, 10, 11, 12, 13, 14]
                for index in textIndices {
                    let ratio = Self.contrast(colors.palette[index], colors.background)
                    #expect(ratio >= 4.5, "\(theme.name) \(mode): color \(index) \(ratio)")
                }
                #expect(Self.contrast(colors.palette[8], colors.background) <= text, "\(theme.name) \(mode): dim above text")
                #expect(colors.background == theme.colors(for: mode)?.background)
            }
        }
        // A color already past the minimum is left alone.
        let calm = try #require(library.theme(named: "Calm")?.dark)
        #expect(calm.contrasted().palette[1] == calm.palette[1])
    }

    /// WCAG contrast ratio of two `#rrggbb` colors.
    static func contrast(_ first: String, _ second: String) -> Double {
        func luminance(_ hex: String) -> Double {
            let value = Int(hex.dropFirst(), radix: 16) ?? 0
            let channels = [(value >> 16) & 0xFF, (value >> 8) & 0xFF, value & 0xFF].map { Double($0) / 255 }
            let linear = channels.map { $0 <= 0.04045 ? $0 / 12.92 : pow(($0 + 0.055) / 1.055, 2.4) }
            return 0.2126 * linear[0] + 0.7152 * linear[1] + 0.0722 * linear[2]
        }
        let (a, b) = (luminance(first), luminance(second))
        return (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }
}

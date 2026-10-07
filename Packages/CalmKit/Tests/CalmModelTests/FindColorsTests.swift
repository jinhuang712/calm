@testable import CalmModel
import Foundation
import Testing

/// The checks the design's color script ran (DESIGNS.md → Find), on the five built-in themes.
struct FindColorsTests {
    private static let themesFolder = URL(filePath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent() // CalmKit
        .deletingLastPathComponent().deletingLastPathComponent() // the repository
        .appending(path: "Calm/Resources/Themes")

    /// What the script measured (the design canvas's table): solid, band and a lone tick's opacity.
    private struct Measured {
        let solid: String, band: String, tick: Double

        init(_ solid: String, _ band: String, _ tick: Double) {
            (self.solid, self.band, self.tick) = (solid, band, tick)
        }
    }

    private static let measured: [String: Measured] = [
        "Calm dark": Measured("#92aecb", "#2b3239", 0.6), "Calm light": Measured("#536d87", "#dfe4e8", 0.8),
        "Dusk dark": Measured("#85b2cb", "#20292e", 0.6), "Dusk light": Measured("#477296", "#e4e9ee", 0.8),
        "Forest dark": Measured("#97bc9d", "#2c342d", 0.6), "Forest light": Measured("#4d7756", "#e4e9e4", 0.85),
        "Ink dark": Measured("#8ca8c5", "#20272e", 0.6), "Ink light": Measured("#57718c", "#e6ebef", 0.85),
        "Plum dark": Measured("#b3a6cf", "#29262e", 0.6), "Plum light": Measured("#7b6593", "#eae7ed", 0.85),
    ]

    @Test func `every built-in theme passes the design's checks`() throws {
        let library = ThemeLibrary(folders: [Self.themesFolder])
        #expect(library.themes.count == 5)
        for theme in library.themes {
            for mode in CalmTheme.Mode.allCases {
                let name = "\(theme.name) \(mode.rawValue)"
                let colors = try #require(theme.colors(for: mode))
                let find = try FindColors(background: colors.background, foreground: colors.foreground, accent: #require(colors.accent))
                let measured = try #require(Self.measured[name])
                // Text in the background color on the pill.
                #expect(CalmTheme.contrast(find.solid, colors.background) >= 4.5, "\(name): pill")
                // The band: the script's exact color, a tint apart from the background and from a selection.
                #expect(find.band == measured.band, "\(name): band \(find.band)")
                // Its lightness moves 0.03 by construction, so 3 less what rounding to 8 bits takes.
                let selection = try #require(colors.selection)
                #expect(Self.distance(find.band, colors.background) >= 2.9, "\(name): band against the background")
                #expect(Self.distance(find.band, selection) >= 4.5, "\(name): band against a selection")
                // The solid moves only as far as 4.5:1 needs: within a step of the script's, which
                // went a little further.
                #expect(Self.channelGap(find.solid, measured.solid) <= 3, "\(name): solid \(find.solid)")
                // A lone tick: 3:1 on its track in a light theme (60% in a dark one, about 3:1 there).
                let track = CalmTheme.mix(colors.background, colors.foreground, 0.06)
                let tick = CalmTheme.contrast(CalmTheme.mix(track, find.solid, find.tickAlpha), track)
                #expect(tick >= (mode == .dark ? 2.9 : 3), "\(name): tick \(tick)")
                #expect(abs(find.tickAlpha - measured.tick) <= 0.05, "\(name): tick opacity \(find.tickAlpha)")
                // The band as a layer over the background comes out as the band.
                let layer = find.bandLayer
                let under = CalmTheme.channels(colors.background)
                let shown = zip([layer.red, layer.green, layer.blue], under).map { $1 + ($0 - $1) * layer.alpha }
                for (channel, want) in zip(shown, CalmTheme.channels(find.band)) {
                    #expect(abs(channel - want) < 1.0 / 255, "\(name): layer")
                }
                #expect(layer.alpha < 0.12, "\(name): the text on the band keeps its contrast")
            }
        }
    }

    @Test func `an accent too faint for the pill moves, a strong one stays`() {
        // A pale accent on a light background darkens until text in the background reads at 4.5:1.
        let pale = FindColors.solid(accent: "#a0b8d0", background: "#f0f0f0")
        #expect(CalmTheme.contrast(pale, "#f0f0f0") >= 4.5)
        #expect(CalmTheme.contrast(pale, "#f0f0f0") < 4.7)
        #expect(FindColors.solid(accent: "#92aecb", background: "#292a2c") == "#92aecb")
        // A dark accent on a dark background lightens.
        let deep = FindColors.solid(accent: "#203040", background: "#101010")
        #expect(CalmTheme.contrast(deep, "#101010") >= 4.5)
    }

    /// ΔE in OKLab, scaled by 100 (about one just-noticeable step per unit).
    private static func distance(_ first: String, _ second: String) -> Double {
        let (a, b) = (OKLab(hex: first), OKLab(hex: second))
        return 100 * ((a.lightness - b.lightness) * (a.lightness - b.lightness) + (a.a - b.a) * (a.a - b.a) + (a.b - b.b) * (a.b - b.b))
            .squareRoot()
    }

    private static func channelGap(_ first: String, _ second: String) -> Int {
        zip(CalmTheme.channels(first), CalmTheme.channels(second)).map { Int((abs($0 - $1) * 255).rounded()) }.max() ?? 0
    }
}

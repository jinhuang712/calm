import Foundation

/// The colors find draws with (FEATURES.md → F16, UIUX.md → Find), from the colors on screen:
/// the background, the text and the accent. Checked on the five built-in themes by a script
/// first (2026-10-07) and now by `FindColorsTests`: text in the background color reads at 4.5:1
/// on the pill, the underline and edge bar stand at 3:1 or more, and the band stays a tint that
/// doesn't read as a selection (DESIGNS.md → Find).
public struct FindColors: Equatable, Sendable {
    public let background: String
    public let foreground: String
    /// The current match's pill, every match's underline, the edge bar and the map's current tick.
    public let solid: String
    /// The current line's band, as it looks over the background.
    public let band: String
    /// How strong a lone tick on the map is over its track (the text color at 6%): 3:1 or more.
    public let tickAlpha: Double

    /// From colors whose pill color is already known (the terminal's `search-selected-background`):
    /// the band takes its hue.
    public init(background: String, foreground: String, solid: String) {
        let dark = Self.isDark(background)
        self.background = background
        self.foreground = foreground
        self.solid = solid
        band = Self.band(background: background, hue: solid, dark: dark)
        tickAlpha = Self.tickAlpha(solid: solid, background: background, foreground: foreground, dark: dark)
    }

    /// From a theme: its accent (palette color 4 for colors that have none) becomes the solid.
    public init(background: String, foreground: String, accent: String) {
        self.init(background: background, foreground: foreground, solid: Self.solid(accent: accent, background: background))
    }

    /// Whether `background` is a dark theme's.
    public static func isDark(_ background: String) -> Bool {
        OKLab(hex: background).lightness < 0.5
    }

    /// The accent, moved in OKLab lightness away from the background (darker in a light theme)
    /// until text in the background color reads at 4.5:1 on it. Hue and chroma stay.
    public static func solid(accent: String, background: String) -> String {
        var color = OKLab(hex: accent)
        let step = isDark(background) ? 0.002 : -0.002
        var hex = accent
        while CalmTheme.contrast(hex, background) < 4.5, (0 ... 1).contains(color.lightness + step) {
            color.lightness += step
            hex = color.hex
        }
        return hex
    }

    /// The background, a little lighter (darker in a light theme), tinted toward the accent's hue.
    /// A tint rather than a lift with the accent: a lift sat too close to a selection.
    static func band(background: String, hue accent: String, dark: Bool) -> String {
        var color = OKLab(hex: background)
        let tint = OKLab(hex: accent)
        let angle = atan2(tint.b, tint.a)
        let chroma = dark ? 0.016 : 0.008
        color.lightness += dark ? 0.03 : -0.03
        color.a = chroma * cos(angle)
        color.b = chroma * sin(angle)
        return color.hex
    }

    /// 60% in a dark theme; in a light one, as strong as a tick needs to reach 3:1 on the track.
    static func tickAlpha(solid: String, background: String, foreground: String, dark: Bool) -> Double {
        guard !dark else { return 0.6 }
        let track = CalmTheme.mix(background, foreground, 0.06)
        var alpha = 0.6
        while alpha < 1, CalmTheme.contrast(CalmTheme.mix(track, solid, alpha), track) < 3 {
            alpha = ((alpha + 0.05) * 100).rounded() / 100
        }
        return alpha
    }

    /// A translucent color, as sRGB components from 0 to 1.
    public struct Layer: Equatable, Sendable {
        public let red: Double, green: Double, blue: Double, alpha: Double
    }

    /// The band as a layer laid over the terminal. It lies above the text (the terminal draws its
    /// own background), so it's as faint as can still make the band over the background: the text
    /// on the current line keeps nearly all its contrast.
    public var bandLayer: Layer {
        let target = CalmTheme.channels(band), under = CalmTheme.channels(background)
        // The least opacity whose color stays within sRGB, with a little room.
        var alpha = 0.0
        for (want, below) in zip(target, under) where want != below {
            alpha = max(alpha, want > below ? (want - below) / (1 - below) : (below - want) / below)
        }
        alpha = min(max(alpha * 1.1, 0.04), 1)
        let color = zip(target, under).map { want, below in min(max(below + (want - below) / alpha, 0), 1) }
        return Layer(red: color[0], green: color[1], blue: color[2], alpha: alpha)
    }
}

/// A color in OKLab (Björn Ottosson's perceptual space), for moving lightness and hue evenly.
struct OKLab: Equatable {
    var lightness: Double
    var a: Double
    var b: Double

    init(hex: String) {
        let linear = CalmTheme.channels(hex).map { $0 <= 0.04045 ? $0 / 12.92 : pow(($0 + 0.055) / 1.055, 2.4) }
        let (red, green, blue) = (linear[0], linear[1], linear[2])
        let l = cbrt(0.4122214708 * red + 0.5363325363 * green + 0.0514459929 * blue)
        let m = cbrt(0.2119034982 * red + 0.6806995451 * green + 0.1073969566 * blue)
        let s = cbrt(0.0883024619 * red + 0.2817188376 * green + 0.6299787005 * blue)
        lightness = 0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s
        a = 1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s
        b = 0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s
    }

    /// As `#rrggbb`, clipped to sRGB.
    var hex: String {
        let l = pow(lightness + 0.3963377774 * a + 0.2158037573 * b, 3)
        let m = pow(lightness - 0.1055613458 * a - 0.0638541728 * b, 3)
        let s = pow(lightness - 0.0894841775 * a - 1.2914855480 * b, 3)
        let linear = [
            4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s,
            -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s,
            -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s,
        ]
        return "#" + linear.map { value in
            let clipped = min(max(value, 0), 1)
            let encoded = clipped <= 0.0031308 ? clipped * 12.92 : 1.055 * pow(clipped, 1 / 2.4) - 0.055
            return String(format: "%02x", Int((encoded * 255).rounded()))
        }.joined()
    }
}

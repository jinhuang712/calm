import CalmModel
import Foundation

public extension PiAdapter {
    /// pi's own folder for user themes; a file's name is its theme's. pi lists it in `/settings`
    /// too, but Calm's extension applies it without selecting it there (see `extensionSource`).
    internal static let themePath = ".pi/agent/themes/calm.json"

    var themeFilePath: String? {
        Self.themePath
    }

    func themeFile(for colors: CalmTheme.Colors, mode: CalmTheme.Mode) -> String? {
        PiTheme.file(for: colors, mode: mode)
    }
}

/// Calm's theme for pi, in pi's theme format (0.99.1's `theme-schema.json`, which allows no key
/// it doesn't name). pi's built-in `dark` paints the user's message on a blue-green slab, its
/// headings in yellow and the prompt's frame in a pink that grows with the thinking level; its
/// `system` theme takes the palette but places the colors its own way. This gives the roles
/// Calm's colors: its accent for the accent and the prompt's frame (a thinking level only
/// strengthens it), text and a dim text clearly dimmer, message and tool boxes that barely lift,
/// and headings in the palette's strongest text rather than a color.
///
/// Every color is written out, no variables: Calm's extension builds pi's theme object from the
/// file itself. One appearance, the one on screen, as for OpenCode; Calm rewrites the file when it
/// changes. The marker sits in `vars`, the one place the schema takes a free string; nothing refers
/// to it.
enum PiTheme {
    static func file(for colors: CalmTheme.Colors, mode: CalmTheme.Mode) -> String? {
        let theme: [String: Any] = [
            "$schema": "https://raw.githubusercontent.com/earendil-works/pi/main/packages/coding-agent/src/modes/interactive/theme/theme-schema.json",
            "name": "calm",
            "appearance": mode.rawValue,
            "vars": ["calm": "\(AgentSetup.marker) from its theme while pi is connected; Settings → Agents → Disconnect removes it."],
            "colors": self.colors(colors, mode: mode),
            "export": export(colors),
        ]
        // Sorted keys, so the same colors always give the same text and never rewrite the file.
        let options: JSONSerialization.WritingOptions = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        guard let data = try? JSONSerialization.data(withJSONObject: theme, options: options),
              let text = String(bytes: data, encoding: .utf8)
        else { return nil }
        return text + "\n"
    }

    /// Every color pi's schema names, required and optional.
    static func colors(_ colors: CalmTheme.Colors, mode: CalmTheme.Mode) -> [String: String] {
        let background = colors.background, text = colors.foreground
        let palette = colors.palette
        func color(_ index: Int, or fallback: String) -> String {
            index < palette.count ? palette[index] : fallback
        }
        func lift(_ amount: Double) -> String {
            CalmTheme.mix(background, text, amount)
        }
        func tint(_ hue: String, _ amount: Double) -> String {
            CalmTheme.mix(background, hue, amount)
        }
        let accent = colors.accent ?? color(4, or: text)
        // The palette's strongest text: bright white on dark, black on light.
        let strong = mode == .dark ? color(15, or: text) : color(0, or: text)
        let muted = CalmTheme.mix(text, background, 0.3)
        let dim = CalmTheme.mix(text, background, 0.45)
        let red = color(1, or: text), green = color(2, or: text), yellow = color(3, or: text)
        let blue = color(4, or: accent), purple = color(5, or: text), cyan = color(6, or: text)
        let border = lift(0.2)
        return [
            "accent": accent,
            "border": border,
            "borderAccent": accent,
            "borderMuted": lift(0.13),
            "success": green,
            "error": red,
            "warning": yellow,
            "muted": muted,
            "dim": dim,
            "text": text,
            "thinkingText": muted,
            "selectedBg": colors.selection ?? lift(0.14),
            "scrollbarTrack": lift(0.07),
            "scrollbarThumb": lift(0.3),
            "searchMatchBg": tint(yellow, 0.25),
            "searchMatchText": text,
            // The user's message: a slight lift, not a colored slab.
            "userMessageBg": lift(0.055),
            "userMessageText": text,
            "customMessageBg": lift(0.04),
            "customMessageText": muted,
            "customMessageLabel": accent,
            "toolPendingBg": lift(0.04),
            "toolSuccessBg": tint(green, 0.09),
            "toolErrorBg": tint(red, 0.12),
            "toolTitle": text,
            "toolOutput": muted,
            "mdHeading": strong,
            "mdLink": accent,
            "mdLinkUrl": dim,
            "mdCode": green,
            "mdCodeBlock": text,
            "mdCodeBlockBorder": border,
            "mdQuote": muted,
            "mdQuoteBorder": border,
            "mdHr": border,
            "mdListBullet": dim,
            "toolDiffAdded": green,
            "toolDiffRemoved": red,
            "toolDiffContext": muted,
            "syntaxComment": dim,
            "syntaxKeyword": purple,
            "syntaxFunction": blue,
            "syntaxVariable": text,
            "syntaxString": green,
            "syntaxNumber": yellow,
            "syntaxType": cyan,
            "syntaxOperator": muted,
            "syntaxPunctuation": muted,
            // The prompt's frame by thinking level: gray when off, then Calm's accent, stronger
            // with each level, never another hue.
            "thinkingOff": border,
            "thinkingMinimal": CalmTheme.mix(accent, background, 0.65),
            "thinkingLow": CalmTheme.mix(accent, background, 0.5),
            "thinkingMedium": CalmTheme.mix(accent, background, 0.35),
            "thinkingHigh": CalmTheme.mix(accent, background, 0.18),
            "thinkingXhigh": accent,
            "thinkingMax": color(12, or: accent),
            "bashMode": green,
        ]
    }

    /// HTML exports' backgrounds.
    static func export(_ colors: CalmTheme.Colors) -> [String: String] {
        [
            "pageBg": colors.background,
            "cardBg": CalmTheme.mix(colors.background, colors.foreground, 0.05),
            "infoBg": CalmTheme.mix(colors.background, colors.palette.count > 3 ? colors.palette[3] : colors.foreground, 0.15),
        ]
    }
}

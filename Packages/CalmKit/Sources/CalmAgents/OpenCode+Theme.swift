import CalmModel
import Foundation

public extension OpenCodeAdapter {
    /// OpenCode's own themes paint every cell in fixed truecolor, so a Calm theme never reached it
    /// (DESIGNS.md → Themes). The shells Calm starts ask for a theme through
    /// `OPENCODE_CLI_CONFIG_CONTENT`, which OpenCode 2 merges over `cli.json` without writing it;
    /// older versions don't read it: Calm's own `calm` theme while its file is there (OpenCode is
    /// connected, see `syncTheme`), else `system`, drawn from the terminal's colors. A theme the
    /// user named in `cli.json`, or their own value of the variable, is left alone. While the
    /// variable is set it outranks the file, so a theme picked inside OpenCode shows from the next
    /// session on.
    func shellEnvironment(home: URL, inherited: [String: String]) -> [String: String] {
        if let own = inherited[Self.cliConfigVariable], !own.isEmpty {
            return [:]
        }
        if Self.namesTheme(cliConfig: Self.cliConfigURL(home: home, inherited: inherited)) {
            return [:]
        }
        let calm = (try? String(contentsOf: home.appending(path: Self.themePath), encoding: .utf8))?.contains(AgentSetup.marker)
        return [Self.cliConfigVariable: calm == true ? Self.calmTheme : Self.systemTheme]
    }

    internal static let cliConfigVariable = "OPENCODE_CLI_CONFIG_CONTENT"
    internal static let systemTheme = #"{"theme":{"name":"system"}}"#
    internal static let calmTheme = #"{"theme":{"name":"calm"}}"#

    /// OpenCode reads every `themes/*.json` in its config folder; the file's name is the theme's.
    internal static let themePath = ".config/opencode/themes/calm.json"

    var themeFilePath: String? {
        Self.themePath
    }

    func themeFile(for colors: CalmTheme.Colors, mode: CalmTheme.Mode) -> String? {
        OpenCodeTheme.file(for: colors, mode: mode)
    }

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

/// Calm's theme for OpenCode 2, in OpenCode's theme format (read from 2.0.19's built-in `opencode`
/// theme): `base` gives each role as a reference into hue scales, and a mode gives the scales,
/// here built from the colors on screen. Where OpenCode's `system` theme puts its agent color in
/// the palette's magenta, its boxes in a lift of its own and its dim text in a fixed gray nearly as
/// bright as the text, this uses Calm's accent, a slight lift and a dim text clearly dimmer.
///
/// One mode only, the one on screen: for any theme but `system`, OpenCode picks light or dark
/// from the palette it cached the last time `system` ran, not from the terminal, and a theme with
/// one mode is always shown in it. Calm rewrites the file when the appearance changes.
enum OpenCodeTheme {
    static func file(for colors: CalmTheme.Colors, mode: CalmTheme.Mode) -> String? {
        let theme: [String: Any] = [
            "$schema": "https://opencode.ai/theme.json",
            "$comment": "\(AgentSetup.marker) from its theme while OpenCode is connected; Settings → Agents → Disconnect removes it.",
            "base": base,
            mode.rawValue: ["hue": hues(colors, mode: mode)],
        ]
        // Sorted keys, so the same colors always give the same text and never rewrite the file.
        let options: JSONSerialization.WritingOptions = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        guard let data = try? JSONSerialization.data(withJSONObject: theme, options: options),
              let text = String(bytes: data, encoding: .utf8)
        else { return nil }
        return text + "\n"
    }

    /// The scales OpenCode's roles point into, 100 the strongest and 900 the faintest.
    static func hues(_ colors: CalmTheme.Colors, mode: CalmTheme.Mode) -> [String: Any] {
        let background = colors.background, text = colors.foreground
        let palette = colors.palette
        func color(_ index: Int, or fallback: String) -> String {
            index < palette.count ? palette[index] : fallback
        }
        /// A hue: its bright color, itself, then toward the background (tints for diffs).
        func scale(_ normal: String, bright: String) -> [String: String] {
            let steps = [0.2, 0.35, 0.5, 0.62, 0.74, 0.84, 0.92]
            var scale = ["100": bright, "200": normal]
            for (index, amount) in steps.enumerated() {
                scale["\(index + 3)00"] = CalmTheme.mix(normal, background, amount)
            }
            return scale
        }
        func hue(_ index: Int) -> [String: String] {
            let normal = color(index, or: text)
            return scale(normal, bright: color(index + 8, or: normal))
        }
        // The palette's strongest text: bright white on dark, black on light.
        let strong = mode == .dark ? color(15, or: text) : color(0, or: text)
        let accent = colors.accent ?? color(4, or: text)
        return [
            "gray": [
                "100": strong,
                "200": text,
                "300": CalmTheme.mix(text, background, 0.2),
                // Dim text (model, timings, hints), clearly dimmer than the text.
                "400": CalmTheme.mix(text, background, 0.42),
                // Borders and the raised surfaces: message and prompt boxes lift only slightly.
                "500": CalmTheme.mix(background, text, 0.16),
                "600": CalmTheme.mix(background, text, 0.1),
                "700": CalmTheme.mix(background, text, 0.055),
                "800": background,
                "900": colors.sidebar ?? CalmTheme.mix(background, mode == .dark ? "#000000" : "#ffffff", 0.2),
            ],
            "red": hue(1),
            // Calm's palettes have no orange: warnings and numbers take its yellow.
            "orange": hue(3),
            "green": hue(2),
            "cyan": hue(6),
            "blue": scale(accent, bright: color(12, or: accent)),
            "purple": hue(5),
            "accent": "$hue.blue",
            "interactive": "$hue.blue",
            "neutral": "$hue.gray",
        ]
    }

    /// Every role OpenCode's own theme sets, pointed at the scales; the background stays the
    /// terminal's, so the padding and title strip match it.
    static var base: [String: Any] {
        [
            // Agent colors, in order: Build takes the accent.
            "categorical": ["blue", "purple", "green", "orange", "red"],
            "text": [
                "base": "$hue.neutral.200",
                "muted": "$hue.neutral.400",
                "action": [
                    "primary": [
                        "base": "$text.base", "$disabled": "$hue.neutral.400", "$focused": "$hue.neutral.800",
                        "$selected": "$hue.interactive.200",
                    ],
                    "secondary": ["base": "$text.muted", "$hovered": "$text.base"],
                    "destructive": ["base": "$hue.neutral.800", "$disabled": "$hue.neutral.400"],
                ],
                "formfield": [
                    "base": "$hue.neutral.200", "$hovered": "$hue.interactive.200", "$focused": "$hue.interactive.200",
                    "$pressed": "$hue.interactive.200", "$disabled": "$hue.neutral.400", "$selected": "$hue.interactive.200",
                ],
                "feedback": [
                    "error": ["base": "$hue.red.200"], "warning": ["base": "$hue.orange.200"],
                    "success": ["base": "$hue.green.200"], "info": ["base": "$hue.cyan.200"],
                ],
            ],
            "background": [
                "base": "transparent",
                "raised": ["base": "$hue.neutral.700", "high": "$hue.neutral.600", "max": "$hue.neutral.500"],
                "action": [
                    "primary": [
                        "base": "transparent", "$hovered": "$hue.neutral.600", "$focused": "$hue.interactive.200",
                        "$selected": "transparent",
                    ],
                    "secondary": ["base": "transparent"],
                    "destructive": ["base": "$hue.red.200"],
                ],
                "formfield": ["base": "$background.base"],
                "feedback": [
                    "error": ["base": "$background.base"], "warning": ["base": "$background.base"],
                    "success": ["base": "$background.base"], "info": ["base": "$background.base"],
                ],
            ],
            "border": ["base": "$hue.neutral.500"],
            "scrollbar": ["base": "$hue.neutral.500"],
            "diff": [
                "text": [
                    "added": "$hue.green.200",
                    "removed": "$hue.red.200",
                    "context": "$hue.neutral.400",
                    "hunkHeader": "$hue.neutral.400",
                ],
                "background": ["added": "$hue.green.800", "removed": "$hue.red.800", "context": "$hue.neutral.700"],
                "highlight": ["added": "$hue.green.100", "removed": "$hue.red.100"],
                "lineNumber": ["text": "$hue.neutral.400", "background": ["added": "$hue.green.900", "removed": "$hue.red.900"]],
            ],
            "syntax": [
                "comment": "$hue.neutral.400", "keyword": "$hue.purple.200", "function": "$hue.blue.200", "variable": "$hue.neutral.200",
                "string": "$hue.green.200", "number": "$hue.orange.200", "type": "$hue.cyan.200", "operator": "$hue.cyan.200",
                "punctuation": "$hue.neutral.300",
            ],
            // Headings and bold in the strongest text, not a color: emphasis stays quiet.
            "markdown": [
                "text": "$hue.neutral.200", "heading": "$hue.neutral.100", "link": "$hue.interactive.200", "linkText": "$hue.cyan.200",
                "code": "$hue.green.200", "blockQuote": "$hue.neutral.400", "emphasis": "$hue.neutral.200", "strong": "$hue.neutral.100",
                "horizontalRule": "$hue.neutral.500", "listItem": "$hue.neutral.400", "listEnumeration": "$hue.neutral.400",
                "image": "$hue.interactive.200", "imageText": "$hue.cyan.200", "codeBlock": "$hue.neutral.200",
            ],
            "@dialog": ["background": ["base": "$background.raised.base", "action": ["primary": ["$hovered": "$background.raised.high"]]]],
        ]
    }
}

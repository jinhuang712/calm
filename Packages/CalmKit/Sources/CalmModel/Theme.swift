import Foundation

/// A Calm theme (FEATURES.md → F11): terminal colors plus two chrome tints, in a light and a dark
/// variant, from a small TOML file (DESIGNS.md → Themes).
public struct CalmTheme: Equatable, Sendable, Identifiable {
    public enum Mode: String, CaseIterable, Sendable {
        case light, dark
    }

    public struct Colors: Equatable, Sendable {
        public var background: String
        public var foreground: String
        public var cursor: String?
        public var selection: String?
        /// The 16 ANSI colors, or empty to keep the terminal's own.
        public var palette: [String]
        /// The sidebar's background; derived from `background` when unset.
        public var sidebar: String?
        /// The *needs you* highlight; Calm's soft amber when unset.
        public var accent: String?

        public init(
            background: String, foreground: String, cursor: String? = nil, selection: String? = nil,
            palette: [String] = [], sidebar: String? = nil, accent: String? = nil,
        ) {
            self.background = background
            self.foreground = foreground
            self.cursor = cursor
            self.selection = selection
            self.palette = palette
            self.sidebar = sidebar
            self.accent = accent
        }
    }

    public var name: String
    public var light: Colors?
    public var dark: Colors?

    public var id: String {
        name.lowercased()
    }

    /// The colors for `mode`, or the other variant for a theme that has only one.
    public func colors(for mode: Mode) -> Colors? {
        switch mode {
        case .light: light ?? dark
        case .dark: dark ?? light
        }
    }

    /// Reads a theme file. A variant missing its background or foreground is left out, bad
    /// optional colors are dropped, and each problem is reported; `nil` if no variant is usable.
    public init?(text: String, fallbackName: String, problems: inout [String]) {
        let values = CalmSettings(text: text).values
        name = values["name"].flatMap { $0.isEmpty ? nil : $0 } ?? fallbackName
        func variant(_ mode: Mode) -> Colors? {
            let prefix = mode.rawValue + "."
            guard values.keys.contains(where: { $0.hasPrefix(prefix) }) else { return nil }
            func color(_ key: String) -> String? {
                guard let value = values[prefix + key] else { return nil }
                guard let hex = Self.hex(value) else {
                    problems.append("\(mode.rawValue).\(key): not a #rrggbb color")
                    return nil
                }
                return hex
            }
            guard let background = color("background"), let foreground = color("foreground") else {
                problems.append("\(mode.rawValue): needs a background and a foreground")
                return nil
            }
            var palette = (values[prefix + "palette"] ?? "").split(separator: ",").compactMap { Self.hex(String($0)) }
            if !palette.isEmpty, palette.count != 16 {
                problems.append("\(mode.rawValue).palette: needs 16 colors, found \(palette.count)")
                palette = []
            }
            return Colors(
                background: background, foreground: foreground, cursor: color("cursor"), selection: color("selection"),
                palette: palette, sidebar: color("sidebar"), accent: color("accent"),
            )
        }
        light = variant(.light)
        dark = variant(.dark)
        guard light != nil || dark != nil else {
            problems.append("no usable [light] or [dark] colors")
            return nil
        }
    }

    public init(name: String, light: Colors?, dark: Colors?) {
        self.name = name
        self.light = light
        self.dark = dark
    }

    /// The Ghostty theme a Ghostty config sets (the last `theme =` line): one name, or a
    /// `light:…,dark:…` pair.
    public static func ghosttyThemePair(configText: String) -> (light: String, dark: String)? {
        var pair: (light: String, dark: String)?
        for line in configText.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.hasPrefix("#"), let equals = trimmed.firstIndex(of: "="),
                  trimmed[..<equals].trimmingCharacters(in: .whitespaces) == "theme" else { continue }
            var value = trimmed[trimmed.index(after: equals)...].trimmingCharacters(in: .whitespaces)
            if value.count >= 2, value.hasPrefix("\""), value.hasSuffix("\"") {
                value = String(value.dropFirst().dropLast())
            }
            guard !value.isEmpty else {
                pair = nil
                continue
            }
            var light: String?
            var dark: String?
            for part in value.split(separator: ",").map({ $0.trimmingCharacters(in: .whitespaces) }) {
                if part.hasPrefix("light:") {
                    light = String(part.dropFirst(6))
                } else if part.hasPrefix("dark:") {
                    dark = String(part.dropFirst(5))
                }
            }
            if light == nil, dark == nil {
                pair = (value, value)
            } else if let either = light ?? dark {
                pair = (light ?? either, dark ?? either)
            }
        }
        return pair
    }

    /// The WCAG contrast ratio of two `#rrggbb` colors.
    public static func contrast(_ first: String, _ second: String) -> Double {
        let (a, b) = (luminance(first), luminance(second))
        return (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }

    static func channels(_ hex: String) -> [Double] {
        let value = Int(hex.dropFirst(), radix: 16) ?? 0
        return [(value >> 16) & 0xFF, (value >> 8) & 0xFF, value & 0xFF].map { Double($0) / 255 }
    }

    static func luminance(_ hex: String) -> Double {
        let linear = channels(hex).map { $0 <= 0.04045 ? $0 / 12.92 : pow(($0 + 0.055) / 1.055, 2.4) }
        return 0.2126 * linear[0] + 0.7152 * linear[1] + 0.0722 * linear[2]
    }

    /// `#rrggbb` (lowercased), from `#rrggbb` or `rrggbb`.
    static func hex(_ text: String) -> String? {
        var value = text.trimmingCharacters(in: .whitespaces).lowercased()
        if value.hasPrefix("#") {
            value.removeFirst()
        }
        guard value.count == 6, value.allSatisfy(\.isHexDigit) else { return nil }
        return "#" + value
    }

    /// The terminal part as Ghostty config lines (also a valid Ghostty theme file).
    public static func ghosttyLines(_ colors: Colors) -> [String] {
        var lines = ["background = \(colors.background)", "foreground = \(colors.foreground)"]
        if let cursor = colors.cursor {
            lines.append("cursor-color = \(cursor)")
        }
        if let selection = colors.selection {
            lines.append("selection-background = \(selection)")
            lines.append("selection-foreground = \(colors.foreground)")
        }
        for (index, color) in colors.palette.enumerated() {
            lines.append("palette = \(index)=\(color)")
        }
        return lines
    }
}

public extension CalmTheme.Colors {
    /// For Increase Contrast (UIUX.md → Accessibility): every text color reaches `minimum`
    /// against the background by moving toward white (a dark theme) or black (a light one), so
    /// hues and the soft hierarchy stay (dim stays dimmer than text). Ghostty's own
    /// `minimum-contrast` swaps short colors to white or black instead, flattening that hierarchy.
    func contrasted(minimum: Double = 4.5) -> CalmTheme.Colors {
        let isDark = CalmTheme.luminance(background) < 0.2
        func lift(_ hex: String) -> String {
            let start = CalmTheme.channels(hex)
            var color = hex
            var amount = 0.0
            while CalmTheme.contrast(color, background) < minimum, amount < 1 {
                amount = min(1, amount + 0.02)
                let mixed = start.map { isDark ? $0 + (1 - $0) * amount : $0 * (1 - amount) }
                color = "#" + mixed.map { String(format: "%02x", Int(($0 * 255).rounded())) }.joined()
            }
            return color
        }
        var colors = self
        colors.foreground = lift(foreground)
        colors.cursor = cursor.map(lift)
        // Black (0) is a background color in dark themes, and the whites (7, 15) in light ones.
        let backgrounds: Set<Int> = isDark ? [0] : [0, 7, 15]
        colors.palette = palette.enumerated().map { backgrounds.contains($0) ? $1 : lift($1) }
        return colors
    }
}

/// The themes Calm can use: the built-in set, then the user's own from `~/.config/calm/themes/`.
/// A user theme with a built-in's name replaces it.
public struct ThemeLibrary: Sendable {
    public static let defaultName = "Calm"
    public private(set) var themes: [CalmTheme] = []
    public private(set) var problems: [String] = []

    public init(themes: [CalmTheme]) {
        self.themes = themes
    }

    /// Loads `*.toml` from each folder in order.
    public init(folders: [URL]) {
        var byID: [String: CalmTheme] = [:]
        var order: [String] = []
        for folder in folders {
            let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
            for file in files.filter({ $0.pathExtension == "toml" }).sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
                guard let text = try? String(contentsOf: file, encoding: .utf8) else { continue }
                var fileProblems: [String] = []
                let fallback = file.deletingPathExtension().lastPathComponent
                if let theme = CalmTheme(text: text, fallbackName: fallback, problems: &fileProblems) {
                    if byID[theme.id] == nil {
                        order.append(theme.id)
                    }
                    byID[theme.id] = theme
                }
                problems += fileProblems.map { "\(file.lastPathComponent): \($0)" }
            }
        }
        themes = order.compactMap { byID[$0] }
    }

    public func theme(named name: String) -> CalmTheme? {
        themes.first { $0.id == name.lowercased() }
    }

    /// The user's own themes folder.
    public static var userFolder: URL {
        FileManager.default.homeDirectoryForCurrentUser.appending(path: ".config/calm/themes", directoryHint: .isDirectory)
    }
}

public extension CalmSettings {
    /// The theme picked in Calm (`theme = "Sage"`), or `nil` for the default, which gives way to a
    /// theme or colors set in the user's Ghostty config (DESIGNS.md → Themes).
    var themeName: String? {
        values["theme"].flatMap { $0.isEmpty ? nil : $0 }
    }
}

import AppKit
import CalmModel

/// Applies Calm's themes to the terminal (DESIGNS.md → Themes).
///
/// Ghostty ranks a theme's colors below any color set directly in the config, wherever it is
/// set, while `theme =` itself goes to the last file that sets it. So:
/// - the **default** theme goes in Calm's defaults as `theme = light:…,dark:…`: a theme or colors
///   in the user's Ghostty config still win, and Ghostty switches light and dark itself;
/// - a theme **picked** in Calm is written as plain colors for the current appearance to a file
///   loaded after the user's config (`choicesFile`), so it wins; Calm rewrites it when the
///   appearance changes.
@MainActor
enum TerminalTheme {
    /// Read on each config load (`refreshLibrary`), so a new or edited theme file counts after
    /// Reload Configuration.
    private(set) static var library = loadLibrary()

    static func refreshLibrary() {
        library = loadLibrary()
        for problem in library.problems {
            FileHandle.standardError.write(Data("calm: theme \(problem)\n".utf8))
        }
    }

    private static func loadLibrary() -> ThemeLibrary {
        let builtIn = Bundle.main.url(forResource: "Themes", withExtension: nil)
        return ThemeLibrary(folders: [builtIn, ThemeLibrary.userFolder].compactMap(\.self))
    }

    /// The theme in effect and whether it was picked in Calm (`theme` in config.toml).
    static func active(settings: CalmSettings = SessionManager.shared.settings, in library: ThemeLibrary = library)
        -> (theme: CalmTheme, picked: Bool)? {
        if let name = settings.themeName {
            if let theme = library.theme(named: name) {
                return (theme, true)
            }
            FileHandle.standardError.write(Data("calm: theme \"\(name)\" not found; using the default\n".utf8))
        }
        return library.theme(named: ThemeLibrary.defaultName).map { ($0, false) }
    }

    static var isDark: Bool {
        NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }

    /// The line for Calm's defaults: the default theme as a light/dark pair of Ghostty theme files.
    /// Nothing when a theme was picked (it's loaded later, from `choicesFile`).
    static func defaultLines(settings: CalmSettings, directory: URL, library: ThemeLibrary = library) -> [String] {
        guard let (theme, picked) = active(settings: settings, in: library), !picked else { return [] }
        let folder = directory.appending(path: "themes", directoryHint: .isDirectory)
        var paths: [CalmTheme.Mode: String] = [:]
        for mode in CalmTheme.Mode.allCases {
            guard let colors = theme.colors(for: mode) else { continue }
            let file = folder.appending(path: "\(theme.id)-\(mode.rawValue)")
            if write(CalmTheme.ghosttyLines(colors), to: file) {
                paths[mode] = file.path
            }
        }
        guard let light = paths[.light], let dark = paths[.dark] else { return [] }
        return ["theme = light:\(light),dark:\(dark)"]
    }

    /// How opaque the terminal is on a glass window: enough to read comfortably, with the blur
    /// showing through.
    static let glassOpacity = 0.84

    /// The terminal side of choices made in Calm's settings, as a file to load after the user's
    /// Ghostty config so they win: a picked theme's colors for the current appearance, and the
    /// terminal's opacity on a glass window. `nil` when there's nothing to override.
    static func choicesFile(settings: CalmSettings, directory: URL, library: ThemeLibrary = library, dark: Bool = isDark) -> URL? {
        var lines: [String] = []
        if let (theme, picked) = active(settings: settings, in: library), picked, let colors = theme.colors(for: dark ? .dark : .light) {
            lines.append("# The theme picked in Calm (\(theme.name)), for the current appearance.")
            lines += CalmTheme.ghosttyLines(colors)
        }
        if settings.windowBackground == .glass {
            lines.append("# A glass window: the terminal lets the blur behind it show through.")
            lines.append("background-opacity = \(glassOpacity)")
        }
        guard !lines.isEmpty else { return nil }
        let file = directory.appending(path: "choices.ghostty")
        return write(["# Written by Calm from its settings; loaded after your Ghostty config."] + lines, to: file) ? file : nil
    }

    /// The theme's variant whose background the terminal actually shows, for the chrome's tints.
    /// `nil` when the user's own Ghostty colors are in effect instead.
    static func chromeColors(matching background: NSColor) -> CalmTheme.Colors? {
        guard let (theme, _) = active() else { return nil }
        let hex = background.hexString
        return [theme.dark, theme.light].compactMap(\.self).first { $0.background == hex }
    }

    private static func write(_ lines: [String], to file: URL) -> Bool {
        do {
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try (lines.joined(separator: "\n") + "\n").write(to: file, atomically: true, encoding: .utf8)
            return true
        } catch {
            FileHandle.standardError.write(Data("calm: could not write \(file.lastPathComponent): \(error)\n".utf8))
            return false
        }
    }
}

extension NSColor {
    /// `#rrggbb` in sRGB.
    var hexString: String {
        let color = usingColorSpace(.sRGB) ?? self
        return String(
            format: "#%02x%02x%02x",
            Int((color.redComponent * 255).rounded()), Int((color.greenComponent * 255).rounded()),
            Int((color.blueComponent * 255).rounded()),
        )
    }

    /// From `#rrggbb`.
    convenience init?(hex: String) {
        guard hex.count == 7, hex.hasPrefix("#"), let value = Int(hex.dropFirst(), radix: 16) else { return nil }
        self.init(
            srgbRed: CGFloat((value >> 16) & 0xFF) / 255, green: CGFloat((value >> 8) & 0xFF) / 255,
            blue: CGFloat(value & 0xFF) / 255, alpha: 1,
        )
    }
}

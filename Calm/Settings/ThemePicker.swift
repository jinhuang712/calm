import AppKit
import CalmModel
import SwiftUI

/// The theme picker's model (FEATURES.md → F11, UIUX.md → Themes): each theme's colors for its
/// previews; one click writes `theme` to config.toml and applies it.
@MainActor
@Observable
final class ThemePickerModel {
    /// The colors a preview is drawn with.
    struct Preview: Equatable {
        var background: Color
        var foreground: Color
        var sidebar: Color
        /// Red, green, yellow, blue, magenta, cyan.
        var hues: [Color]
        var cursor: Color
        /// The theme's accent (its *needs you*); blue for colors that name none.
        var accent: Color
    }

    struct Choice: Identifiable, Equatable {
        /// A theme's id, or `ghostty` for the user's own Ghostty colors.
        var id: String
        var name: String
        var light: Preview
        var dark: Preview
    }

    static let ghosttyID = "ghostty"
    private(set) var choices: [Choice] = []
    private(set) var selectedID = ThemeLibrary.defaultName.lowercased()

    func refresh() {
        var choices: [Choice] = []
        let user = [false, true].map { dark in
            TerminalConfig.userColors(dark: dark).map { Self.preview(
                background: $0.background,
                foreground: $0.foreground,
                palette: $0.palette,
            ) }
        }
        if let light = user[0] ?? user[1], let dark = user[1] ?? user[0] {
            choices.append(Choice(id: Self.ghosttyID, name: "Ghostty", light: light, dark: dark))
        }
        for theme in TerminalTheme.library.themes {
            guard let light = theme.colors(for: .light), let dark = theme.colors(for: .dark) else { continue }
            choices.append(Choice(id: theme.id, name: theme.name, light: Self.preview(light), dark: Self.preview(dark)))
        }
        self.choices = choices
        let picked = SessionManager.shared.settings.themeName?.lowercased()
        selectedID = picked.flatMap { id in choices.contains { $0.id == id } ? id : nil }
            ?? (choices.first?.id == Self.ghosttyID ? Self.ghosttyID : ThemeLibrary.defaultName.lowercased())
    }

    /// Applies a choice: a theme is written to config.toml; "Ghostty" removes Calm's choice, so
    /// the user's Ghostty colors apply again.
    func pick(_ id: String) {
        guard id != selectedID else { return }
        let name = id == Self.ghosttyID ? nil : choices.first { $0.id == id }?.name
        do {
            SessionManager.shared.settings = try CalmSettings.save("theme", name)
        } catch {
            FileHandle.standardError.write(Data("calm: could not save the theme: \(error)\n".utf8))
            return
        }
        selectedID = id
        TerminalEngine.shared.reloadConfig(soft: false)
    }

    private static func preview(_ colors: CalmTheme.Colors) -> Preview {
        let color = { (hex: String?) in hex.flatMap(NSColor.init(hex:)) }
        let background = color(colors.background) ?? .black
        let foreground = color(colors.foreground) ?? .white
        return preview(
            background: background, foreground: foreground, palette: colors.palette.compactMap { color($0) },
            sidebar: color(colors.sidebar), cursor: color(colors.cursor), accent: color(colors.accent),
        )
    }

    private static func preview(
        background: NSColor, foreground: NSColor, palette: [NSColor], sidebar: NSColor? = nil, cursor: NSColor? = nil,
        accent: NSColor? = nil,
    ) -> Preview {
        let hues = palette.count >= 7 ? Array(palette[1 ... 6]) : Array(repeating: foreground.withAlphaComponent(0.6), count: 6)
        let derivedSidebar = SidebarStyle.derived(from: background).background
        return Preview(
            background: Color(nsColor: background), foreground: Color(nsColor: foreground),
            sidebar: sidebar.map { Color(nsColor: $0) } ?? derivedSidebar, hues: hues.map { Color(nsColor: $0) },
            cursor: Color(nsColor: cursor ?? foreground), accent: Color(nsColor: accent ?? hues[3]),
        )
    }
}

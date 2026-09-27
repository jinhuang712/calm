import AppKit
import CalmModel
import SwiftUI

/// The theme picker (FEATURES.md → F11, UIUX.md → Themes): a grid of small live previews drawn
/// from each theme's colors; one click writes `theme` to config.toml and applies it.
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
            sidebar: color(colors.sidebar), cursor: color(colors.cursor),
        )
    }

    private static func preview(
        background: NSColor, foreground: NSColor, palette: [NSColor], sidebar: NSColor? = nil, cursor: NSColor? = nil,
    ) -> Preview {
        let hues = palette.count >= 7 ? Array(palette[1 ... 6]) : Array(repeating: foreground.withAlphaComponent(0.6), count: 6)
        let derivedSidebar = SidebarStyle.derived(from: background).background
        return Preview(
            background: Color(nsColor: background), foreground: Color(nsColor: foreground),
            sidebar: sidebar.map { Color(nsColor: $0) } ?? derivedSidebar, hues: hues.map { Color(nsColor: $0) },
            cursor: Color(nsColor: cursor ?? foreground),
        )
    }
}

struct ThemePickerView: View {
    let model: ThemePickerModel
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 16), count: 3), spacing: 16) {
            ForEach(model.choices) { choice in
                let selected = choice.id == model.selectedID
                Button {
                    model.pick(choice.id)
                } label: {
                    VStack(spacing: 7) {
                        ThemePreview(preview: colorScheme == .dark ? choice.dark : choice.light)
                            .overlay {
                                RoundedRectangle(cornerRadius: 9, style: .continuous)
                                    .strokeBorder(selected ? Color.accentColor : .clear, lineWidth: 2)
                                    .padding(-3)
                            }
                        Text(choice.name)
                            .font(.system(size: 12, weight: selected ? .medium : .regular))
                            .foregroundStyle(selected ? .primary : .secondary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(choice.name) theme")
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
    }
}

/// A miniature of the window in a theme's colors: the sidebar, a few lines of output, the cursor.
struct ThemePreview: View {
    let preview: ThemePickerModel.Preview

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 5) {
                bar(preview.foreground.opacity(0.14), width: 22, height: 7)
                bar(preview.foreground.opacity(0.3), width: 18)
                bar(preview.foreground.opacity(0.3), width: 14)
                Spacer(minLength: 0)
            }
            .padding(.top, 14)
            .padding(.horizontal, 6)
            .frame(width: 36, alignment: .leading)
            .frame(maxHeight: .infinity)
            .background(preview.sidebar)

            VStack(alignment: .leading, spacing: 5) {
                line([(preview.hues[1], 12), (preview.foreground, 28)])
                line([(preview.foreground.opacity(0.7), 20), (preview.hues[3], 16)])
                line([(preview.hues[2], 10), (preview.hues[4], 18), (preview.hues[5], 12)])
                line([(preview.hues[0], 24), (preview.foreground.opacity(0.45), 14)])
                bar(preview.cursor, width: 5, height: 8)
                Spacer(minLength: 0)
            }
            .padding(.top, 12)
            .padding(.horizontal, 9)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(preview.background)
        }
        .frame(height: 84)
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(Color.primary.opacity(0.1)))
    }

    private func line(_ parts: [(Color, CGFloat)]) -> some View {
        HStack(spacing: 4) {
            ForEach(parts.indices, id: \.self) { index in
                bar(parts[index].0, width: parts[index].1)
            }
        }
    }

    private func bar(_ color: Color, width: CGFloat, height: CGFloat = 4) -> some View {
        RoundedRectangle(cornerRadius: height / 2).fill(color).frame(width: width, height: height)
    }
}

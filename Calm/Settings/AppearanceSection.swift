import CalmModel
import SwiftUI

/// Settings → Appearance (UIUX.md → Settings, Themes): a live miniature of the window in the
/// picked theme and window options, the themes as chips, then background, layout, motion and
/// where the terminal font comes from.
struct AppearanceSection: View {
    let themes: ThemePickerModel
    let windowOptions: WindowOptionsModel
    let style: SidebarStyle

    private var picked: ThemePickerModel.Preview? {
        themes.choices.first { $0.id == themes.selectedID }.map { style.isDark ? $0.dark : $0.light }
    }

    private var calmThemes: [ThemePickerModel.Choice] {
        themes.choices.filter { $0.id != ThemePickerModel.ghosttyID }
    }

    private var ghostty: ThemePickerModel.Choice? {
        themes.choices.first { $0.id == ThemePickerModel.ghosttyID }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsTitle(title: "Appearance", style: style)
                .padding(.bottom, 24.scaled)
            if let picked {
                WindowPreview(
                    preview: picked, card: windowOptions.layout == .card, glass: windowOptions.background == .glass,
                    isDark: style.isDark,
                )
                .padding(.bottom, 32.scaled)
            }
            GroupHeading(title: "Theme", style: style)
            // The chips share the column's width, so the row ends where the rows below it do.
            HStack(alignment: .top, spacing: 12.scaled) {
                ForEach(calmThemes) { choice in
                    chip(choice, name: choice.name)
                }
                if let ghostty {
                    Rectangle()
                        .fill(style.hairline)
                        .frame(width: 1, height: 68)
                    chip(ghostty, name: "Your Ghostty")
                        .help("The colors your Ghostty config sets, instead of a Calm theme")
                }
            }
            .padding(.bottom, 32.scaled)
            SettingsGroup(style: style) {
                // Closures, not method references: passing a model's method crashed the Swift 6.3.3
                // compiler (IRGen, isolated reabstraction thunk; see AgentsSection).
                // How large all of Calm's chrome is drawn, this page included; the terminal
                // keeps its own font (⌘+ and ⌘−).
                SettingsRow(title: "Interface size", style: style) {
                    CalmSegmented(
                        title: "Interface size",
                        options: [(.standard, "Default"), (.large, "Large"), (.larger, "Larger"), (.largest, "Largest")],
                        selection: windowOptions.interfaceSize, segmentWidth: 92, style: style,
                    ) { windowOptions.setInterfaceSize($0) }
                }
                RowDivider(style: style)
                // No help lines: the preview above shows what each choice does.
                SettingsRow(title: "Background", style: style) {
                    CalmSegmented(
                        title: "Background", options: [(.solid, "Solid"), (.glass, "Glass")],
                        selection: windowOptions.background, style: style,
                    ) { windowOptions.setBackground($0) }
                }
                RowDivider(style: style)
                SettingsRow(title: "Layout", style: style) {
                    CalmSegmented(
                        title: "Layout", options: [(.edge, "Edge to edge"), (.card, "Card")],
                        selection: windowOptions.layout, style: style,
                    ) { windowOptions.setLayout($0) }
                }
                RowDivider(style: style)
                SettingsRow(title: "Motion", note: motionNote, style: style) {
                    CalmSegmented(
                        title: "Motion", options: [(.full, "Full"), (.reduced, "Reduced"), (.off, "Off")],
                        selection: AccessibilitySettings.reduceMotion ? .off : windowOptions.motion, segmentWidth: 100,
                        isDisabled: AccessibilitySettings.reduceMotion, style: style,
                    ) { windowOptions.setMotion($0) }
                }
            }
        }
    }

    /// Only when the control can't do what it shows.
    private var motionNote: String? {
        AccessibilitySettings.reduceMotion ? "Reduce Motion is on in System Settings, so Calm keeps still." : nil
    }

    private func chip(_ choice: ThemePickerModel.Choice, name: String) -> some View {
        let selected = choice.id == themes.selectedID
        let preview = style.isDark ? choice.dark : choice.light
        return Button {
            themes.pick(choice.id)
        } label: {
            VStack(spacing: 6.scaled) {
                ThemeChipPreview(preview: preview)
                    .overlay {
                        RoundedRectangle(cornerRadius: 12.scaled, style: .continuous)
                            .strokeBorder(selected ? style.accent : .clear, lineWidth: 2)
                            .padding(-4)
                    }
                Text(name)
                    .calmFont(size: SettingsMetrics.note, weight: selected ? .medium : .regular)
                    .foregroundStyle(selected ? style.primary : style.secondary)
                    .lineLimit(1)
                    .fixedSize()
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(name) theme")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// A theme at a glance: its sidebar, a few colored lines and its accent.
private struct ThemeChipPreview: View {
    let preview: ThemePickerModel.Preview

    var body: some View {
        HStack(spacing: 0) {
            preview.sidebar.frame(width: 22)
            VStack(alignment: .leading, spacing: 5) {
                bar(preview.hues[1], width: 30)
                bar(preview.foreground.opacity(0.6), width: 40)
                bar(preview.accent, width: 22)
            }
            .padding(.horizontal, 9)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .background(preview.background)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 68)
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(preview.foreground.opacity(0.14)))
    }

    private func bar(_ color: Color, width: CGFloat) -> some View {
        Capsule().fill(color).frame(width: width, height: 4)
    }
}

/// A miniature of Calm's window in a theme's colors, with the chosen layout and background.
/// Glass shows as a soft desktop behind a see-through window.
struct WindowPreview: View {
    let preview: ThemePickerModel.Preview
    let card: Bool
    let glass: Bool
    let isDark: Bool

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let height = proxy.size.height
            ZStack {
                desk(width: width, height: height)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                // A solid window fills the column, lined up with the rows below; glass sits inset
                // on its desktop so there's something to show through.
                window(width: glass ? width - 44 : width, height: glass ? height - 32 : height)
            }
            .frame(width: width, height: height)
        }
        // Short: a terminal is mostly empty below its prompt, and a taller miniature was a dark
        // block that outweighed the choices under it.
        .aspectRatio(720 / 210, contentMode: .fit)
        .animation(.easeInOut(duration: 0.25), value: card)
        .animation(.easeInOut(duration: 0.25), value: glass)
        .accessibilityHidden(true)
    }

    /// Behind the window: nothing for a solid one (the page shows around it), a quiet desktop
    /// with a little color for glass to show through.
    private func desk(width: CGFloat, height: CGFloat) -> some View {
        ZStack {
            if glass {
                Color(white: isDark ? 0.14 : 0.87)
                Circle()
                    .fill(Color(hue: 0.53, saturation: 0.25, brightness: isDark ? 0.55 : 0.8))
                    .frame(width: width * 0.4)
                    .offset(x: -width * 0.25, y: -height * 0.3)
                    .blur(radius: 30)
                Circle()
                    .fill(Color(hue: 0.06, saturation: 0.3, brightness: isDark ? 0.55 : 0.85))
                    .frame(width: width * 0.45)
                    .offset(x: width * 0.3, y: height * 0.35)
                    .blur(radius: 36)
            }
        }
    }

    private func window(width: CGFloat, height: CGFloat) -> some View {
        let sidebarWidth = width * 0.29
        let surface = glass ? 0.6 : 1.0
        return HStack(spacing: 0) {
            sidebar
                .frame(width: sidebarWidth)
                .background(card ? Color.clear : preview.sidebar.opacity(surface))
            terminal
                .background(preview.background.opacity(glass ? 0.84 : 1))
                .clipShape(RoundedRectangle(cornerRadius: card ? 7 : 0, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: card ? 7 : 0, style: .continuous)
                        .strokeBorder(preview.foreground.opacity(card ? 0.08 : 0))
                }
                .padding(card ? 5 : 0)
                .padding(.leading, card ? -5 : 0)
        }
        .frame(width: width, height: height)
        .background(card ? preview.sidebar.opacity(surface) : .clear)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(.black.opacity(0.3)))
        .shadow(color: .black.opacity(0.3), radius: 14, y: 8)
    }

    private static let trafficLights = [
        Color(red: 1, green: 0.37, blue: 0.34), Color(red: 1, green: 0.74, blue: 0.18), Color(red: 0.16, green: 0.78, blue: 0.25),
    ]

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 4) {
                ForEach(Self.trafficLights, id: \.self) {
                    Circle().fill($0).frame(width: 6, height: 6)
                }
            }
            .padding(.bottom, 4)
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(preview.foreground.opacity(0.07))
                .frame(height: 16)
            bar(preview.foreground.opacity(0.3), width: 26, height: 3)
                .padding(.top, 4)
            card(fill: preview.accent.opacity(0.14), mark: preview.accent.opacity(0.6), state: preview.accent.opacity(0.8))
            card(fill: preview.foreground.opacity(0.08), mark: preview.hues[3].opacity(0.6), state: preview.foreground.opacity(0.45))
            card(fill: .clear, mark: preview.hues[1].opacity(0.5), state: preview.foreground.opacity(0.45))
            Spacer(minLength: 0)
            ForEach([48.0, 68, 54], id: \.self) { width in
                bar(preview.foreground.opacity(0.4), width: width, height: 3)
            }
        }
        .padding(8)
    }

    private func card(fill: Color, mark: Color, state: Color) -> some View {
        HStack(alignment: .top, spacing: 6) {
            RoundedRectangle(cornerRadius: 3, style: .continuous).fill(mark).frame(width: 11, height: 11)
            VStack(alignment: .leading, spacing: 3) {
                bar(preview.foreground.opacity(0.75), width: 58, height: 3)
                bar(state, width: 72, height: 2.5)
                bar(preview.foreground.opacity(0.3), width: 88, height: 2.5)
            }
            .padding(.top, 1)
        }
        .padding(6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(fill))
    }

    private var terminal: some View {
        let hues = preview.hues
        let lines: [(CGFloat, [(Color, CGFloat)])] = [
            (0, [(hues[1], 8), (preview.foreground, 48)]),
            (0, [(preview.foreground.opacity(0.55), 30), (preview.foreground.opacity(0.35), 64)]),
            (0, [(hues[3], 18), (preview.foreground.opacity(0.7), 36), (hues[5], 24)]),
            (12, [(preview.foreground.opacity(0.45), 56), (hues[4], 32)]),
            (12, [(hues[2], 42), (preview.foreground.opacity(0.35), 76)]),
            (12, [(hues[0], 24), (preview.foreground.opacity(0.5), 52)]),
            (0, [(preview.foreground.opacity(0.3), 96)]),
            (0, [(hues[1], 8), (preview.foreground, 38), (hues[3], 20)]),
        ]
        return VStack(alignment: .leading, spacing: 6) {
            ForEach(lines.indices, id: \.self) { index in
                HStack(spacing: 4) {
                    ForEach(lines[index].1.indices, id: \.self) { part in
                        bar(lines[index].1[part].0, width: lines[index].1[part].1, height: 4)
                    }
                }
                .padding(.leading, lines[index].0)
            }
            RoundedRectangle(cornerRadius: 1.5).fill(preview.cursor).frame(width: 5, height: 9)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func bar(_ color: Color, width: CGFloat, height: CGFloat) -> some View {
        Capsule().fill(color).frame(width: width, height: height)
    }
}

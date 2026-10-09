import CalmModel
import SwiftUI

// The sidebar's small controls: the footer's rows and handle, and a group header's hover glyphs.

/// A sidebar control: a full-height target with a quiet hover background.
struct FooterButton<Label: View>: View {
    let style: SidebarStyle
    let help: String
    let action: () -> Void
    @ViewBuilder let label: Label
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            label
                .frame(minHeight: 40.scaled)
                .foregroundStyle(hovering ? style.primary : style.secondary)
                .background(RoundedRectangle(cornerRadius: 10.scaled, style: .continuous).fill(hovering ? style.selection : .clear))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(help)
    }
}

/// Hides the sidebar's footer, or brings it back: a small chevron in a strip above the footer's
/// line (or along the bottom edge when hidden) that lights up under the pointer.
struct FooterHandle: View {
    let style: SidebarStyle
    let symbol: String
    let help: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .calmFont(size: 10, weight: .semibold)
                .foregroundStyle(hovering ? style.primary : style.tertiary)
                .frame(width: 44.scaled, height: 16.scaled)
                .background(RoundedRectangle(cornerRadius: 6.scaled, style: .continuous).fill(hovering ? style.selection : .clear))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(help)
        .accessibilityLabel(help)
    }
}

/// One of a group header's hover controls: a small glyph that lights up under the pointer.
struct GroupControl: View {
    let style: SidebarStyle
    let glyph: GroupControlLabel.Glyph
    let help: String
    let action: () -> Void

    init(style: SidebarStyle, glyph: GroupControlLabel.Glyph, help: String, action: @escaping () -> Void) {
        self.style = style
        self.glyph = glyph
        self.help = help
        self.action = action
    }

    init(style: SidebarStyle, systemImage: String, help: String, action: @escaping () -> Void) {
        self.init(style: style, glyph: .symbol(systemImage), help: help, action: action)
    }

    var body: some View {
        Button(action: action) {
            GroupControlLabel(style: style, glyph: glyph)
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
    }
}

struct GroupControlLabel: View {
    /// What the control shows: a symbol, an agent's own mark (a session running it), or `>_` (a
    /// plain shell), so the two ways to start in a group say which is which.
    enum Glyph {
        case symbol(String)
        case agent(AgentKind)
        case shell
    }

    let style: SidebarStyle
    let glyph: Glyph
    @State private var hovering = false

    init(style: SidebarStyle, glyph: Glyph) {
        self.style = style
        self.glyph = glyph
    }

    init(style: SidebarStyle, systemImage: String) {
        self.init(style: style, glyph: .symbol(systemImage))
    }

    var body: some View {
        content
            .foregroundStyle(hovering ? style.primary : style.tertiary)
            .frame(width: 22.scaled, height: 22.scaled)
            .background(RoundedRectangle(cornerRadius: 6.scaled, style: .continuous).fill(hovering ? style.selection : .clear))
            .contentShape(Rectangle())
            .onHover { hovering = $0 }
    }

    @ViewBuilder
    private var content: some View {
        switch glyph {
        case let .symbol(name):
            Image(systemName: name)
                .calmFont(size: 11, weight: .semibold)
        case let .agent(kind):
            AgentLogo(agent: kind, size: 16, style: style)
        case .shell:
            Text(">_")
                .calmFont(size: 10.5, weight: .semibold, design: .monospaced)
        }
    }
}

/// A shortcut drawn as small key caps (⌘ T), the way the menu bar would print it but calmer.
/// (Moved here from SidebarView.swift, which had reached its file-length limit.)
struct KeyCaps: View {
    let keys: [String]
    let style: SidebarStyle
    /// The welcome page's bigger caps.
    var large = false

    var body: some View {
        HStack(spacing: (large ? 4 : 3).scaled) {
            ForEach(Array(keys.enumerated()), id: \.offset) { _, key in
                Text(key)
                    .calmFont(size: large ? 12 : 11.5)
                    .foregroundStyle(style.tertiary)
                    .frame(minWidth: (large ? 24 : 20).scaled, minHeight: (large ? 24 : 20).scaled)
                    .padding(.horizontal, (key.count > 1 ? 4 : 0).scaled)
                    .background(
                        RoundedRectangle(cornerRadius: (large ? 6 : 5).scaled, style: .continuous)
                            .fill(style.primary.opacity(0.06)),
                    )
            }
        }
        .accessibilityHidden(true)
    }
}

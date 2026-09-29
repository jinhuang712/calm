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
    let systemImage: String
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            GroupControlLabel(style: style, systemImage: systemImage)
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
    }
}

struct GroupControlLabel: View {
    let style: SidebarStyle
    let systemImage: String
    @State private var hovering = false

    var body: some View {
        Image(systemName: systemImage)
            .calmFont(size: 11, weight: .semibold)
            .foregroundStyle(hovering ? style.primary : style.tertiary)
            .frame(width: 22.scaled, height: 22.scaled)
            .background(RoundedRectangle(cornerRadius: 6.scaled, style: .continuous).fill(hovering ? style.selection : .clear))
            .contentShape(Rectangle())
            .onHover { hovering = $0 }
    }
}

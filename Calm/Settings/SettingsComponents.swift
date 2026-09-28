import SwiftUI

// The pieces every Settings section is built from (UIUX.md → Settings): grouped rows with the
// label on the left and the control on the right, in the theme's own colors. Controls are drawn
// here rather than taken from AppKit, whose segmented control and switch only know the
// system's accent, which would clash with the theme's (UIUX.md → Color).

/// The page's sizes, in one place: roomy enough to read at a glance in a large window, as the
/// sidebar is (UIUX.md → Settings screen).
@MainActor
enum SettingsMetrics {
    // Type sizes at the standard interface size: `.calmFont` grows them.
    static let title: CGFloat = 34
    static let heading: CGFloat = 16
    static let label: CGFloat = 17
    static let note: CGFloat = 14
    static let control: CGFloat = 15
    /// The section list's type, a step above the sidebar's to match the page.
    static let listTitle: CGFloat = 24
    static let listItem: CGFloat = 16

    /// Lengths, already at the interface size.
    static var controlHeight: CGFloat {
        32.scaled
    }

    static var rowHeight: CGFloat {
        64.scaled
    }

    static var rowInset: CGFloat {
        20.scaled
    }

    static var listRow: CGFloat {
        46.scaled
    }

    static var listTile: CGFloat {
        32.scaled
    }
}

/// A section's title, and the line under it when it has one.
struct SettingsTitle: View {
    let title: String
    var note: String?
    let style: SidebarStyle

    var body: some View {
        VStack(alignment: .leading, spacing: 6.scaled) {
            Text(title)
                .calmFont(size: SettingsMetrics.title, weight: .medium)
                .tracking(-0.3)
                .foregroundStyle(style.primary)
                .accessibilityAddTraits(.isHeader)
            if let note {
                Text(note)
                    .calmFont(size: SettingsMetrics.label)
                    .foregroundStyle(style.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A group's heading, with an optional note on the right.
struct GroupHeading: View {
    let title: String
    var note: String?
    let style: SidebarStyle

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .calmFont(size: SettingsMetrics.heading, weight: .medium)
                .foregroundStyle(style.secondary)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 12)
            if let note {
                Text(note)
                    .calmFont(size: SettingsMetrics.note)
                    .foregroundStyle(style.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.bottom, 12.scaled)
        .padding(.leading, 2.scaled)
    }
}

/// Rows on one rounded surface; put `RowDivider`s between them.
struct SettingsGroup<Content: View>: View {
    let style: SidebarStyle
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 0) {
            content
        }
        .background(RoundedRectangle(cornerRadius: 14.scaled, style: .continuous).fill(style.groupFill))
        .overlay(RoundedRectangle(cornerRadius: 14.scaled, style: .continuous).strokeBorder(style.hairline))
    }
}

struct RowDivider: View {
    let style: SidebarStyle

    var body: some View {
        Rectangle()
            .fill(style.hairline)
            .frame(height: 1)
            .padding(.horizontal, SettingsMetrics.rowInset)
    }
}

/// A label (and one line of help at most) on the left, its control on the right.
struct SettingsRow<Control: View>: View {
    let title: String
    var note: String?
    let style: SidebarStyle
    @ViewBuilder let control: Control

    var body: some View {
        HStack(spacing: 16.scaled) {
            VStack(alignment: .leading, spacing: 4.scaled) {
                Text(title)
                    .calmFont(size: SettingsMetrics.label)
                    .foregroundStyle(style.primary)
                if let note {
                    Text(note)
                        .calmFont(size: SettingsMetrics.note)
                        .foregroundStyle(style.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            control
        }
        .padding(.horizontal, SettingsMetrics.rowInset)
        .padding(.vertical, 14.scaled)
        .frame(minHeight: SettingsMetrics.rowHeight)
        .accessibilityElement(children: .contain)
    }
}

/// A segmented choice with equal segments; the chosen one is a lighter, raised surface, as a
/// selected card is in the sidebar.
struct CalmSegmented<Value: Hashable>: View {
    let title: String
    let options: [(value: Value, label: String)]
    let selection: Value
    var segmentWidth: CGFloat = 128
    var isDisabled = false
    let style: SidebarStyle
    let onSelect: (Value) -> Void

    var body: some View {
        HStack(spacing: 2.scaled) {
            ForEach(options, id: \.value) { option in
                segment(option.value, label: option.label)
            }
        }
        .padding(2.scaled)
        .background(RoundedRectangle(cornerRadius: 8.scaled, style: .continuous).fill(style.primary.opacity(0.08)))
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.45 : 1)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
        .animation(.easeOut(duration: 0.15), value: selection)
    }

    private func segment(_ value: Value, label: String) -> some View {
        let chosen = value == selection
        let shadow: Double = chosen ? (style.isDark ? 0.3 : 0.12) : 0
        return Button {
            onSelect(value)
        } label: {
            Text(label)
                .calmFont(size: SettingsMetrics.control)
                .foregroundStyle(chosen ? style.primary : style.secondary)
                .frame(width: segmentWidth.scaled, height: SettingsMetrics.controlHeight)
                .background(
                    RoundedRectangle(cornerRadius: 6.scaled, style: .continuous)
                        .fill(chosen ? style.raisedFill : Color.clear)
                        .shadow(color: .black.opacity(shadow), radius: 1, y: 1),
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityAddTraits(chosen ? .isSelected : [])
    }
}

/// A switch in the theme's accent.
struct CalmSwitchStyle: ToggleStyle {
    let style: SidebarStyle

    func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            Capsule()
                .fill(configuration.isOn ? style.accent : style.primary.opacity(style.isDark ? 0.2 : 0.16))
                .frame(width: 44.scaled, height: 26.scaled)
                .overlay(alignment: configuration.isOn ? .trailing : .leading) {
                    Circle()
                        .fill(style.isDark ? Color(white: 0.93) : .white)
                        .shadow(color: .black.opacity(0.3), radius: 1, y: 1)
                        .padding(2.scaled)
                }
                .animation(.easeOut(duration: 0.15), value: configuration.isOn)
        }
        .buttonStyle(.plain)
        .accessibilityRepresentation {
            Toggle(isOn: configuration.$isOn) { configuration.label }
        }
    }
}

/// A small push button on the page's surface.
struct SettingsButtonStyle: ButtonStyle {
    let style: SidebarStyle

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .calmFont(size: SettingsMetrics.control)
            .foregroundStyle(style.primary)
            .padding(.horizontal, 16.scaled)
            .frame(height: SettingsMetrics.controlHeight)
            .background(
                RoundedRectangle(cornerRadius: 7.scaled, style: .continuous)
                    .fill(style.buttonFill.opacity(configuration.isPressed ? 0.7 : 1))
                    .shadow(color: .black.opacity(style.isDark ? 0 : 0.12), radius: 0.5, y: 0.5),
            )
            .fixedSize()
    }
}

/// A pop-up choice: the current value and chevrons; the menu checks the chosen item.
struct SettingsMenu<Value: Hashable>: View {
    let title: String
    let options: [(value: Value, label: String)]
    let selection: Value
    let style: SidebarStyle
    let onSelect: (Value) -> Void

    private var current: String {
        options.first { $0.value == selection }?.label ?? ""
    }

    var body: some View {
        Menu {
            Picker(title, selection: Binding(get: { selection }, set: { onSelect($0) })) {
                ForEach(options, id: \.value) { option in
                    Text(option.label).tag(option.value)
                }
            }
            .pickerStyle(.inline)
            .labelsHidden()
        } label: {
            HStack(spacing: 8.scaled) {
                Text(current)
                Image(systemName: "chevron.up.chevron.down")
                    .calmFont(size: 12, weight: .semibold)
            }
            .calmFont(size: SettingsMetrics.control)
            .foregroundStyle(style.primary)
        }
        .menuStyle(.button)
        .buttonStyle(SettingsButtonStyle(style: style))
        .menuIndicator(.hidden)
        .fixedSize()
        .accessibilityLabel(title)
        .accessibilityValue(current)
    }
}

/// Something in a section is broken: a triangle in the theme's red (never color alone).
struct WarningMark: View {
    let style: SidebarStyle
    var size: CGFloat = 13

    var body: some View {
        Image(systemName: "exclamationmark.triangle")
            .calmFont(size: size - 1, weight: .medium)
            .foregroundStyle(style.failure)
            .accessibilityLabel("Needs attention")
    }
}

extension SidebarStyle {
    /// A settings group's surface on the page.
    var groupFill: Color {
        isDark ? primary.opacity(0.04) : Color.white.opacity(0.6)
    }

    /// Group borders and the lines between rows.
    var hairline: Color {
        primary.opacity(isDark ? 0.09 : 0.11)
    }

    /// The chosen segment.
    var raisedFill: Color {
        isDark ? primary.opacity(0.2) : .white
    }

    var buttonFill: Color {
        isDark ? primary.opacity(0.13) : .white
    }
}

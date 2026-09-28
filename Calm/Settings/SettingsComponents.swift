import SwiftUI

// The pieces every Settings section is built from (UIUX.md → Settings): grouped rows with the
// label on the left and the control on the right, in the theme's own colors. Controls are drawn
// here rather than taken from AppKit, whose segmented control and switch only know the
// system's accent, which would clash with the theme's (UIUX.md → Color).

/// A section's title, and the line under it when it has one.
struct SettingsTitle: View {
    let title: String
    var note: String?
    let style: SidebarStyle

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 26, weight: .medium))
                .tracking(-0.2)
                .foregroundStyle(style.primary)
                .accessibilityAddTraits(.isHeader)
            if let note {
                Text(note)
                    .font(.system(size: 14))
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
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(style.primary)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 12)
            if let note {
                Text(note)
                    .font(.system(size: 12))
                    .foregroundStyle(style.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.bottom, 10)
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
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(style.groupFill))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(style.hairline))
    }
}

struct RowDivider: View {
    let style: SidebarStyle

    var body: some View {
        Rectangle()
            .fill(style.hairline)
            .frame(height: 1)
            .padding(.horizontal, 16)
    }
}

/// A label (and one line of help at most) on the left, its control on the right.
struct SettingsRow<Control: View>: View {
    let title: String
    var note: String?
    let style: SidebarStyle
    @ViewBuilder let control: Control

    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 14))
                    .foregroundStyle(style.primary)
                if let note {
                    Text(note)
                        .font(.system(size: 12))
                        .foregroundStyle(style.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            control
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
        .frame(minHeight: 52)
        .accessibilityElement(children: .contain)
    }
}

/// A segmented choice with equal segments; the chosen one is a lighter, raised surface, as a
/// selected card is in the sidebar.
struct CalmSegmented<Value: Hashable>: View {
    let title: String
    let options: [(value: Value, label: String)]
    let selection: Value
    var segmentWidth: CGFloat = 104
    var isDisabled = false
    let style: SidebarStyle
    let onSelect: (Value) -> Void

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.value) { option in
                segment(option.value, label: option.label)
            }
        }
        .padding(2)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(style.primary.opacity(0.08)))
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
                .font(.system(size: 13))
                .foregroundStyle(chosen ? style.primary : style.secondary)
                .frame(width: segmentWidth, height: 26)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
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
                .fill(configuration.isOn ? style.attention : style.primary.opacity(style.isDark ? 0.2 : 0.16))
                .frame(width: 34, height: 20)
                .overlay(alignment: configuration.isOn ? .trailing : .leading) {
                    Circle()
                        .fill(style.isDark ? Color(white: 0.93) : .white)
                        .shadow(color: .black.opacity(0.3), radius: 1, y: 1)
                        .padding(2)
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
            .font(.system(size: 13))
            .foregroundStyle(style.primary)
            .padding(.horizontal, 14)
            .frame(height: 26)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
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
            HStack(spacing: 8) {
                Text(current)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 10, weight: .semibold))
            }
            .font(.system(size: 13))
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
            .font(.system(size: size - 1, weight: .medium))
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

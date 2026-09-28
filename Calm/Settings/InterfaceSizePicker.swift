import CalmModel
import SwiftUI

/// Settings → Appearance → Interface size, drawn the way macOS draws display scaling: one small
/// window per size, the same box each time with its text growing inside, the chosen one ringed
/// in the theme's accent.
struct InterfaceSizePicker: View {
    let selection: CalmSettings.InterfaceSize
    /// The picked theme's colors for the little windows; nil draws them in the page's own.
    let preview: ThemePickerModel.Preview?
    let style: SidebarStyle
    let onSelect: (CalmSettings.InterfaceSize) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            ForEach(CalmSettings.InterfaceSize.allCases, id: \.self) { size in
                option(size)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.top, 24.scaled)
        .padding(.bottom, 18.scaled)
        .padding(.horizontal, 12.scaled)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Interface size")
    }

    private func option(_ size: CalmSettings.InterfaceSize) -> some View {
        let chosen = size == selection
        return Button {
            onSelect(size)
        } label: {
            VStack(spacing: 10.scaled) {
                SizeThumbnail(size: size, preview: preview, style: style)
                    .overlay {
                        RoundedRectangle(cornerRadius: 13.scaled, style: .continuous)
                            .strokeBorder(chosen ? style.attention : .clear, lineWidth: 3)
                            .padding(-5.scaled)
                    }
                VStack(spacing: 2.scaled) {
                    Text(Self.label(size))
                        .calmFont(size: 14, weight: chosen ? .semibold : .regular)
                        .foregroundStyle(chosen ? style.primary : style.secondary)
                    Text(Self.percent(size))
                        .calmFont(size: 12)
                        .foregroundStyle(style.tertiary)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(Self.label(size)), \(Self.percent(size))")
        .accessibilityAddTraits(chosen ? .isSelected : [])
    }

    static func label(_ size: CalmSettings.InterfaceSize) -> String {
        switch size {
        case .standard: "Default"
        case .large: "Large"
        case .larger: "Larger"
        case .largest: "Largest"
        }
    }

    static func percent(_ size: CalmSettings.InterfaceSize) -> String {
        "\(Int((size.scale * 100).rounded()))%"
    }
}

/// A little window at one interface size: the frame stays put and the text grows, so a larger
/// size shows fewer words, as macOS's "Larger Text" does.
private struct SizeThumbnail: View {
    let size: CalmSettings.InterfaceSize
    let preview: ThemePickerModel.Preview?
    let style: SidebarStyle

    private static let words = "Calm keeps an eye on your agents and says when one of them needs you."

    var body: some View {
        let background = preview?.background ?? style.background
        let bar = preview?.sidebar ?? style.background
        let ink = preview?.foreground ?? style.primary
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 4.scaled * CGFloat(size.scale)) {
                ForEach(Self.lights, id: \.self) { color in
                    Circle().fill(color).frame(width: 7.scaled * CGFloat(size.scale), height: 7.scaled * CGFloat(size.scale))
                }
            }
            .padding(.horizontal, 7.scaled)
            .frame(maxWidth: .infinity, minHeight: 16.scaled * CGFloat(size.scale), alignment: .leading)
            .background(bar)
            Text(Self.words)
                .calmFont(size: 8.5 * CGFloat(size.scale), weight: .medium)
                .foregroundStyle(ink.opacity(0.85))
                .lineSpacing(0)
                // Runs past the bottom edge and is cut there, as macOS's previews are, rather than
                // ending in "…".
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 7.scaled)
                .padding(.top, 5.scaled)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        // Held to the top, so text too long for the box runs off its bottom edge, not the title bar.
        .frame(width: 104.scaled, height: 72.scaled, alignment: .top)
        .background(background)
        .clipShape(RoundedRectangle(cornerRadius: 9.scaled, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 9.scaled, style: .continuous).strokeBorder(ink.opacity(0.14)))
        .accessibilityHidden(true)
    }

    private static let lights = [
        Color(red: 1, green: 0.37, blue: 0.34), Color(red: 1, green: 0.74, blue: 0.18), Color(red: 0.16, green: 0.78, blue: 0.25),
    ]
}

import CalmModel
import SwiftUI

/// Settings → Appearance → Interface size: the sizes as chips like the themes above them, each a
/// strip of Calm in the picked theme at that size (UIUX.md → Accessibility).
struct InterfaceSizePicker: View {
    let selection: CalmSettings.InterfaceSize
    let preview: ThemePickerModel.Preview
    let style: SidebarStyle
    let onSelect: (CalmSettings.InterfaceSize) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12.scaled) {
            ForEach(CalmSettings.InterfaceSize.allCases, id: \.self) { size in
                ChoiceChip(
                    name: Self.label(size), selected: size == selection, style: style,
                    action: { onSelect(size) },
                    picture: { SizeChipPreview(preview: preview, scale: CGFloat(size.scale)) },
                )
                .help(Self.percent(size))
                .accessibilityLabel("\(Self.label(size)) interface size, \(Self.percent(size))")
            }
        }
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

/// Calm at one interface size: the sidebar and its cards grow and fewer of them fit, while the
/// terminal's lines stay as they are, which is what the setting does. Drawn in fixed points, like
/// the theme chips, so the page's own size doesn't change the comparison.
private struct SizeChipPreview: View {
    let preview: ThemePickerModel.Preview
    let scale: CGFloat

    var body: some View {
        HStack(spacing: 0) {
            // An overlay, so cards taller than the chip don't make the chip taller.
            preview.sidebar
                .frame(width: 54 * scale)
                .overlay(alignment: .top) { sidebar }
                .clipped()
            terminal
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background(preview.background)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 68)
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(preview.foreground.opacity(0.14)))
        .accessibilityHidden(true)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 3 * scale) {
            card(fill: preview.accent.opacity(0.14), mark: preview.accent.opacity(0.6))
            card(fill: .clear, mark: preview.hues[3].opacity(0.6))
            card(fill: .clear, mark: preview.hues[1].opacity(0.5))
            card(fill: .clear, mark: preview.hues[4].opacity(0.5))
        }
        .padding(5 * scale)
        // Taller than the chip at the larger sizes: the cards that no longer fit run off the
        // bottom instead of squeezing.
        .fixedSize(horizontal: false, vertical: true)
    }

    private func card(fill: Color, mark: Color) -> some View {
        HStack(alignment: .top, spacing: 3 * scale) {
            RoundedRectangle(cornerRadius: 1.5 * scale, style: .continuous).fill(mark).frame(width: 6 * scale, height: 6 * scale)
            VStack(alignment: .leading, spacing: 2 * scale) {
                bar(preview.foreground.opacity(0.75), width: 22 * scale, height: 2.5 * scale)
                bar(preview.foreground.opacity(0.35), width: 28 * scale, height: 2 * scale)
            }
        }
        .padding(3 * scale)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 3 * scale, style: .continuous).fill(fill))
    }

    private var terminal: some View {
        let hues = preview.hues
        let lines: [[(Color, CGFloat)]] = [
            [(hues[1], 6), (preview.foreground.opacity(0.8), 34)],
            [(preview.foreground.opacity(0.45), 22), (preview.foreground.opacity(0.3), 40)],
            [(hues[3], 14), (preview.foreground.opacity(0.6), 26), (hues[5], 16)],
            [(preview.foreground.opacity(0.35), 48)],
            [(hues[1], 6), (preview.foreground.opacity(0.8), 28)],
        ]
        return VStack(alignment: .leading, spacing: 5) {
            ForEach(lines.indices, id: \.self) { index in
                HStack(spacing: 3) {
                    ForEach(lines[index].indices, id: \.self) { part in
                        bar(lines[index][part].0, width: lines[index][part].1, height: 3)
                    }
                }
            }
        }
        .padding(10)
    }

    private func bar(_ color: Color, width: CGFloat, height: CGFloat) -> some View {
        Capsule().fill(color).frame(width: width, height: height)
    }
}

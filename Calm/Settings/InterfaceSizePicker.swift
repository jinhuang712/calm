import CalmModel
import SwiftUI

/// Settings → Appearance → Interface size: the sizes as "Aa" growing from left to right, on the
/// same quiet track as the other choices, the chosen one a lighter surface. A picture of what
/// changes without a louder control than its neighbors (UIUX.md → Accessibility).
struct InterfaceSizePicker: View {
    let selection: CalmSettings.InterfaceSize
    let style: SidebarStyle
    let onSelect: (CalmSettings.InterfaceSize) -> Void

    var body: some View {
        HStack(spacing: 2.scaled) {
            ForEach(CalmSettings.InterfaceSize.allCases, id: \.self) { size in
                segment(size)
            }
        }
        .padding(2.scaled)
        .background(RoundedRectangle(cornerRadius: 8.scaled, style: .continuous).fill(style.primary.opacity(0.08)))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Interface size")
        .animation(.easeOut(duration: 0.15), value: selection)
    }

    private func segment(_ size: CalmSettings.InterfaceSize) -> some View {
        let chosen = size == selection
        let shadow: Double = chosen ? (style.isDark ? 0.3 : 0.12) : 0
        return Button {
            onSelect(size)
        } label: {
            Text("Aa")
                // Each sample is drawn at its own size, so the row reads small to large.
                .calmFont(size: 12 * CGFloat(size.scale), weight: .medium)
                .foregroundStyle(chosen ? style.primary : style.secondary)
                // Four of 63 make the track as wide as the two-choice rows below (2 × 128).
                .frame(width: 63.scaled, height: SettingsMetrics.controlHeight)
                .background(
                    RoundedRectangle(cornerRadius: 6.scaled, style: .continuous)
                        .fill(chosen ? style.raisedFill : Color.clear)
                        .shadow(color: .black.opacity(shadow), radius: 1, y: 1),
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("\(Self.label(size)), \(Self.percent(size))")
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

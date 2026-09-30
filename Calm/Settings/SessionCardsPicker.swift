import CalmModel
import SwiftUI

/// Settings → Appearance → Session cards: Full, Compact and Minimal as chips like the interface
/// sizes above them, each a slice of the sidebar in the picked theme with its cards at that size
/// (UIUX.md → Session cards). The amber card keeps a line more at every size, as the cards that
/// wait for you do.
struct SessionCardsPicker: View {
    let selection: CalmSettings.SessionCardSize
    let preview: ThemePickerModel.Preview
    let style: SidebarStyle
    let onSelect: (CalmSettings.SessionCardSize) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12.scaled) {
            ForEach(CalmSettings.SessionCardSize.allCases, id: \.self) { size in
                ChoiceChip(
                    name: Self.label(size), selected: size == selection, style: style,
                    action: { onSelect(size) },
                    picture: { CardsChipPreview(preview: preview, style: style, size: size) },
                )
                .help(Self.summary(size))
                .accessibilityLabel("\(Self.label(size)) session cards, \(Self.summary(size))")
            }
        }
    }

    static func label(_ size: CalmSettings.SessionCardSize) -> String {
        switch size {
        case .full: "Full"
        case .compact: "Compact"
        case .minimal: "Minimal"
        }
    }

    /// The Shrink cards to fit row's line: what the switch does from the size chosen above, the
    /// largest the cards get with it on.
    static func fitNote(_ size: CalmSettings.SessionCardSize) -> String {
        guard size.smaller != nil else { return "Minimal is the smallest size, so there's nothing to step down to." }
        return "Cards step down from \(label(size)) when the sessions don't fit, and back when there's room."
    }

    static func summary(_ size: CalmSettings.SessionCardSize) -> String {
        switch size {
        case .full: "every line"
        case .compact: "the state and the recap on one line"
        case .minimal: "the name and the time"
        }
    }
}

/// A slice of the sidebar beside a terminal: six cards at one size, fewer lines each step down
/// and more cards in view. Drawn in fixed points, like the other chips.
private struct CardsChipPreview: View {
    let preview: ThemePickerModel.Preview
    let style: SidebarStyle
    let size: CalmSettings.SessionCardSize

    /// Working, needs you, idle, done, idle, working: the states a sidebar mostly holds.
    private static let cards: [(SessionState, CGFloat)] = [
        (.working, 58), (.needsYou, 50), (.idle, 64), (.done, 46), (.idle, 40), (.working, 54),
    ]

    var body: some View {
        HStack(spacing: 0) {
            // An overlay, so cards taller than the chip run off its bottom instead of squeezing.
            preview.sidebar
                .frame(width: 118)
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
        VStack(alignment: .leading, spacing: 3) {
            ForEach(Self.cards.indices, id: \.self) { index in
                card(Self.cards[index].0, titleWidth: Self.cards[index].1, mark: index)
            }
        }
        .padding(5)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func card(_ state: SessionState, titleWidth: CGFloat, mark: Int) -> some View {
        let layout = SessionCardLayout(size: size, state: state)
        return VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 3) {
                RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                    .fill(state == .idle ? preview.foreground.opacity(0.22) : preview.hues[[4, 1, 3][mark % 3]].opacity(0.7))
                    .frame(width: 9, height: 9)
                bar(preview.foreground.opacity(state == .idle ? 0.45 : 0.78), width: titleWidth, height: 3)
                Spacer(minLength: 2)
                bar(size == .minimal && state != .idle ? color(state) : preview.foreground.opacity(0.3), width: 6, height: 2.5)
            }
            VStack(alignment: .leading, spacing: 3) {
                switch layout {
                case .titleOnly:
                    EmptyView()
                case .recap:
                    recap(width: state == .idle ? 60 : 58)
                case .stacked:
                    bar(color(state), width: 26, height: 2.5)
                    recap(width: 70)
                    recap(width: 50)
                case let .merged(lines):
                    HStack(spacing: 3) {
                        bar(color(state), width: 14, height: 2.5)
                        recap(width: 48)
                    }
                    if lines > 1 {
                        recap(width: 40)
                    }
                }
            }
            .padding(.leading, 12)
        }
        .padding(.horizontal, 4)
        .padding(.vertical, layout.isOneLine ? 2.5 : 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 3, style: .continuous).fill(fill(state)))
    }

    private func color(_ state: SessionState) -> Color {
        switch state {
        case .working: style.working
        case .needsYou: style.attention
        case .done: style.done
        case .failed: style.failure
        case .idle: preview.foreground.opacity(0.3)
        }
    }

    /// A little stronger than a real card's tint, so it reads at this size.
    private func fill(_ state: SessionState) -> Color {
        switch state {
        case .working: style.working.opacity(0.14)
        case .needsYou: style.attention.opacity(0.2)
        case .done: style.done.opacity(0.14)
        case .idle, .failed: .clear
        }
    }

    private func recap(width: CGFloat) -> some View {
        bar(preview.foreground.opacity(0.32), width: width, height: 2)
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

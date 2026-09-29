import CalmModel
import SwiftUI

/// A plain shell in the sidebar: one compact line (UIUX.md → Session cards). Agent sessions
/// get a `SessionCard`.
struct SessionRow: View {
    let session: Session
    let isSelected: Bool
    let style: SidebarStyle
    /// The pointer rests on the row: a long name glides to its end.
    var isHovered = false

    var body: some View {
        HStack(spacing: 10.scaled) {
            Image(systemName: "chevron.right")
                .calmFont(size: 10, weight: .semibold)
                .foregroundStyle(style.tertiary)
                .frame(width: 26.scaled, height: 26.scaled)
                .background(RoundedRectangle(cornerRadius: 8.scaled, style: .continuous).strokeBorder(style.tertiary.opacity(0.4)))
            ScrollingTitle(text: session.displayTitle, isHovered: isHovered)
                .calmFont(size: 14, weight: isSelected ? .medium : .regular)
                .foregroundStyle(isSelected ? style.primary : style.secondary)
            Spacer(minLength: 4)
            if session.state != .idle {
                StateMark(state: session.state, style: style)
            }
        }
        .padding(.horizontal, 12.scaled)
        .frame(height: 40.scaled)
        .background(
            RoundedRectangle(cornerRadius: 10.scaled, style: .continuous)
                .fill(session.state == .needsYou ? style.attention.opacity(0.14) : isSelected ? style.selection : .clear),
        )
        .background(RoundedRectangle(cornerRadius: 10.scaled, style: .continuous).fill(isSelected ? style.selectionLift : .clear))
        .overlay(
            RoundedRectangle(cornerRadius: 10.scaled, style: .continuous)
                .strokeBorder(isSelected ? style.selectionEdge : .clear, lineWidth: SidebarStyle.selectionRingWidth),
        )
        .contentShape(Rectangle())
        // A scratch session's folder stays hidden.
        .help(session.lastReport?.message ?? (session.isScratch ? "" : session.workingDirectory))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            [session.displayTitle, session.state == .idle ? nil : session.state.label]
                .compactMap(\.self).joined(separator: ", "),
        )
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

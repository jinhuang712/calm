import CalmModel
import SwiftUI

/// A plain shell in the sidebar: one compact line (specs/UIUX.md → Session cards). Agent sessions
/// get a `SessionCard`.
struct SessionRow: View {
    let session: Session
    let isSelected: Bool
    let style: SidebarStyle
    /// The project of a pinned row, which names it above the title, since the row has left it.
    var pinnedIn: Project?
    /// The pointer rests on the row: a long name glides to its end.
    var isHovered = false
    /// On screen beside the session you're in, in a split: lifted like the selected row, with no
    /// ring (specs/UIUX.md → Split panes).
    var inView = false
    /// The name field while the session is renamed, in the title's place (`SessionCard.nameEditor`).
    var nameEditor: AnyView?

    var body: some View {
        VStack(alignment: .leading, spacing: 2.scaled) {
            if let pinnedIn {
                PinnedProjectLine(project: pinnedIn, style: style)
            }
            line
        }
        .padding(.horizontal, 12.scaled)
        .frame(height: (pinnedIn == nil ? 40 : 58).scaled)
        .background(
            RoundedRectangle(cornerRadius: 10.scaled, style: .continuous)
                .fill(session.state == .needsYou ? style.attention.opacity(0.14) : isSelected ? style.selection : .clear),
        )
        .background(RoundedRectangle(cornerRadius: 10.scaled, style: .continuous).fill(isSelected || inView ? style.selectionLift : .clear))
        .overlay(
            RoundedRectangle(cornerRadius: 10.scaled, style: .continuous)
                .strokeBorder(isSelected ? style.selectionEdge : .clear, lineWidth: SidebarStyle.selectionRingWidth),
        )
        .contentShape(Rectangle())
        // A scratch session's folder stays hidden.
        .help(session.lastReport?.message ?? (session.isScratch ? "" : session.workingDirectory))
        // Combined, the row would hide the field inside it.
        .accessibilityElement(children: nameEditor == nil ? .combine : .contain)
        .accessibilityLabel(
            [session.displayTitle, session.state == .idle ? nil : session.state.label]
                .compactMap(\.self).joined(separator: ", "),
        )
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var line: some View {
        HStack(spacing: 10.scaled) {
            Image(systemName: "chevron.right")
                .calmFont(size: 10, weight: .semibold)
                .foregroundStyle(style.tertiary)
                .frame(width: 26.scaled, height: 26.scaled)
                .background(RoundedRectangle(cornerRadius: 8.scaled, style: .continuous).strokeBorder(style.tertiary.opacity(0.4)))
            if let nameEditor {
                nameEditor
            } else {
                ScrollingTitle(text: session.displayTitle, isHovered: isHovered)
                    .calmFont(size: 14, weight: isSelected ? .medium : .regular)
                    .foregroundStyle(isSelected ? style.primary : style.secondary)
                Spacer(minLength: 4)
                if session.state != .idle {
                    StateMark(state: session.state, style: style)
                }
            }
        }
    }
}

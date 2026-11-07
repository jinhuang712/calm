import CalmModel
import SwiftUI

/// The sidebar's Pinned group (specs/FEATURES.md → F2): first in the list, gone with its last pin.
extension SidebarView {
    @ViewBuilder
    var pinnedSection: some View {
        let sessions = manager.workspace.pinnedSessions
        if !sessions.isEmpty {
            let isCollapsed = manager.workspace.pinnedIsCollapsed == true
            VStack(alignment: .leading, spacing: 6.scaled) {
                PinnedGroupHeader(
                    summary: GroupSummary(sessions.map(\.state)), isCollapsed: isCollapsed, style: style,
                    toggle: { manager.togglePinnedCollapsed() },
                )
                if !isCollapsed {
                    ForEach(sessions) { session in
                        sessionRow(session)
                    }
                }
            }
        }
    }
}

/// Pinned's header, drawn like Scratch's: the group is Calm's, so it has only its chevron.
private struct PinnedGroupHeader: View {
    let summary: GroupSummary
    let isCollapsed: Bool
    let style: SidebarStyle
    let toggle: () -> Void
    @State private var hovering = false

    var body: some View {
        let tinted = isCollapsed && summary.needsYou
        Button(action: toggle) {
            HStack(spacing: 8.scaled) {
                Image(systemName: "chevron.down")
                    .calmFont(size: 9, weight: .semibold)
                    .rotationEffect(.degrees(isCollapsed ? -90 : 0))
                    .frame(width: 10.scaled)
                Image(systemName: "pin.fill")
                    .calmFont(size: 11)
                    .frame(width: 20.scaled)
                Text("PINNED")
                    .calmFont(size: 12, weight: .semibold)
                    .tracking(0.7)
                    .lineLimit(1)
                Spacer(minLength: 4)
                if isCollapsed {
                    GroupSummaryView(summary: summary, style: style)
                }
            }
            .foregroundStyle(style.tertiary)
            .padding(.horizontal, 8.scaled)
            .frame(minHeight: 26.scaled)
            .background(
                RoundedRectangle(cornerRadius: 10.scaled, style: .continuous)
                    .fill(tinted ? style.attention.opacity(0.14) : hovering ? style.selection.opacity(0.55) : .clear)
                    .padding(.vertical, -5.scaled)
                    .animation(.easeInOut(duration: 0.2), value: tinted)
                    .animation(.easeOut(duration: 0.12), value: hovering),
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(isCollapsed ? summary.words : "")
        .accessibilityLabel("Pinned")
        .accessibilityValue(isCollapsed ? "Collapsed" : "Expanded")
    }
}

/// The line above a pinned card's title: the project it belongs to, since the card has left it.
/// Its mark sits in the agent mark's column and its name starts with the title.
struct PinnedProjectLine: View {
    let project: Project
    let style: SidebarStyle

    var body: some View {
        HStack(spacing: 10.scaled) {
            GroupMark(project: project, style: style, side: 14)
                .frame(width: SessionCard.indent - 10.scaled)
                // The mark's click swaps it on a header. On a card, a click opens the session.
                .allowsHitTesting(false)
            Text(project.name)
                .calmFont(size: 12)
                .foregroundStyle(style.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Pinned, in \(project.name)")
    }
}

/// The mark beside a pinned card's time. It says what the card is and does nothing: the session
/// menu and ⌘P pin and unpin (specs/UIUX.md → Session cards).
struct PinGlyph: View {
    let style: SidebarStyle

    var body: some View {
        Image(systemName: "pin.fill")
            .calmFont(size: 10)
            .foregroundStyle(style.tertiary)
            .accessibilityHidden(true)
    }
}

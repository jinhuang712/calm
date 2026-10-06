import CalmModel
import SwiftUI

/// The agent ⌘N starts and the other agents installed, for the ways to start (FEATURES.md → New
/// agent sessions): the sidebar's footer, the first-launch rows and the start line. Read when
/// those are built and passed in, since the settings aren't observed.
struct StartAgents: Equatable {
    /// Nil with no agent installed: the ways to start read as they did before ⌘N.
    var chosen: AgentKind?
    var others: [AgentKind] = []
}

/// What the ⌄ beside ⌘N's row and button opens: a session running each other agent, and the way
/// to change which one ⌘N starts.
struct OtherAgentsMenu: View {
    let agents: StartAgents
    let start: (AgentKind) -> Void
    let choose: () -> Void

    var body: some View {
        ForEach(agents.others, id: \.self) { kind in
            Button("New \(kind.displayName) Session") { start(kind) }
        }
        if !agents.others.isEmpty {
            Divider()
        }
        Button("Choose What ⌘N Starts…", action: choose)
    }
}

/// ⌘N's row at the top of the sidebar's footer: the agent's mark on its tile and its full name.
/// Under the pointer the key caps give their place to a ⌄ for the other agents, so the name keeps
/// its room in the 320 pt sidebar.
struct AgentFooterRow: View {
    let agent: AgentKind
    let agents: StartAgents
    let style: SidebarStyle
    let actions: SidebarActions
    @State private var hovering = false

    var body: some View {
        ZStack(alignment: .trailing) {
            FooterButton(style: style, help: "New \(agent.displayName) Session (⌘N)", action: startChosen) {
                HStack(spacing: 11.scaled) {
                    AgentLogo(agent: agent, size: 28, style: style)
                    Text("New \(agent.displayName) Session")
                        .calmFont(size: 14)
                        // As the footer's other rows: brighter than the tile's symbol.
                        .foregroundStyle(.foreground)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    KeyCaps(keys: ["⌘", "N"], style: style)
                        .opacity(hovering ? 0 : 1)
                }
                .padding(.horizontal, 8.scaled)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Menu {
                OtherAgentsMenu(agents: agents, start: { actions.newAgentSession($0) }, choose: actions.chooseNewSessionAgent)
            } label: {
                ChevronMenuLabel(style: style)
            }
            .plainMenu()
            .padding(.trailing, 8.scaled)
            .opacity(hovering ? 1 : 0)
            .accessibilityLabel("More ways to start")
        }
        .onHover { hovering = $0 }
        .animation(Motion.isReduced ? nil : .easeOut(duration: 0.15), value: hovering)
    }

    /// The agent ⌘N starts (the ⌄ starts the others).
    private func startChosen() {
        actions.newAgentSession(nil)
    }
}

/// The ⌄ itself: quiet until the pointer is on it, then on a soft tile.
struct ChevronMenuLabel: View {
    let style: SidebarStyle
    @State private var hovering = false

    var body: some View {
        Image(systemName: "chevron.down")
            .calmFont(size: 10, weight: .semibold)
            .foregroundStyle(hovering ? style.primary : style.tertiary)
            .frame(width: 22.scaled, height: 22.scaled)
            .background(RoundedRectangle(cornerRadius: 6.scaled, style: .continuous).fill(style.primary.opacity(hovering ? 0.08 : 0)))
            .contentShape(Rectangle())
            .onHover { hovering = $0 }
    }
}

extension View {
    /// A menu drawn as its label alone, as the ⌄ menus are.
    func plainMenu() -> some View {
        menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
    }
}

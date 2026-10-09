import CalmModel
import SwiftUI

// The ways to start on the welcome page (UIUX.md → Welcome page): the start line under the lists,
// and the first launch's rows. ⌘N's carry a ⌄ for the other agents (FEATURES.md → New agent sessions).

extension OtherAgentsMenu {
    init(actions: WelcomeView.Actions) {
        self.init(agents: actions.agents, start: { actions.newAgentSession($0) }, choose: actions.chooseNewSessionAgent)
    }
}

/// The bottom line of the page: the ways to start, shortcut first. Each is a button with a faint
/// fill of its own, so it reads as something to press without the weight of a toolbar.
struct HintLine: View {
    let style: SidebarStyle
    let actions: WelcomeView.Actions

    var body: some View {
        HStack(spacing: 8.scaled) {
            if let agent = actions.agents.chosen {
                HintButton(
                    keys: "⌘N", title: agent.displayName, help: "New \(agent.displayName) Session (⌘N)", style: style,
                    action: { actions.newAgentSession(nil) },
                    menu: { OtherAgentsMenu(actions: actions) },
                )
                HintButton(keys: "⌘T", title: "Shell", help: "New Session (⌘T)", style: style, action: actions.newSession)
            } else {
                HintButton(keys: "⌘T", title: "New session", help: "New Session (⌘T)", style: style, action: actions.newSession)
            }
            HintButton(keys: "⌘⇧N", title: "Scratch", help: "New Scratch Session (⌘⇧N)", style: style, action: actions.newScratchSession)
            HintButton(keys: "⌘O", title: "New project…", help: "New Project (⌘O)", style: style, action: actions.newProject)
        }
    }
}

/// One way to start. ⌘N's has a ⌄ in the same fill, for the other agents.
struct HintButton<MenuContent: View>: View {
    let keys: String
    let title: String
    let help: String
    let style: SidebarStyle
    let action: () -> Void
    @ViewBuilder let menu: () -> MenuContent
    @State private var hovering = false

    private var hasMenu: Bool {
        MenuContent.self != EmptyView.self
    }

    var body: some View {
        HStack(spacing: 0) {
            Button(action: action) {
                HStack(spacing: 9.scaled) {
                    Text(keys)
                        .calmFont(size: 13.5, weight: .medium)
                        .tracking(0.5)
                        .foregroundStyle(style.primary)
                    Text(title)
                        .calmFont(size: 13.5)
                        .foregroundStyle(style.primary.opacity(0.84))
                }
                .padding(.leading, 16.scaled)
                .padding(.trailing, (hasMenu ? 6 : 16).scaled)
                .padding(.vertical, 9.scaled)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(help)
            .accessibilityLabel(title)
            if hasMenu {
                Menu(content: menu) {
                    ChevronMenuLabel(style: style)
                }
                .plainMenu()
                .padding(.trailing, 8.scaled)
                .accessibilityLabel("More ways to start")
            }
        }
        .background(RoundedRectangle(cornerRadius: 9.scaled, style: .continuous).fill(style.primary.opacity(hovering ? 0.11 : 0.055)))
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.15), value: hovering)
    }
}

extension HintButton where MenuContent == EmptyView {
    init(keys: String, title: String, help: String, style: SidebarStyle, action: @escaping () -> Void) {
        self.init(keys: keys, title: title, help: help, style: style, action: action) { EmptyView() }
    }
}

/// One of the ways to start on the first-run page, drawn like the list rows and the sidebar's
/// footer. None is drawn as chosen: a filled first row read as picked for the user, though no key
/// pressed it. The first is first; the pointer lights the one it's on.
struct WelcomeActionRow: View {
    let title: String
    let symbol: String
    /// ⌘N's row shows the agent's mark instead of a symbol, and leaves room for its ⌄.
    var agent: AgentKind?
    let keys: String
    let style: SidebarStyle
    let action: () -> Void
    @State private var hovering = false

    private var fill: Color {
        hovering ? style.primary.opacity(0.06) : .clear
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12.scaled) {
                if let agent {
                    AgentLogo(agent: agent, size: 30, style: style)
                } else {
                    Image(systemName: symbol)
                        .calmFont(size: 14)
                        .foregroundStyle(style.secondary)
                        .frame(width: 30.scaled, height: 30.scaled)
                        .background(RoundedRectangle(cornerRadius: 9.scaled, style: .continuous).fill(style.primary.opacity(0.06)))
                }
                Text(title)
                    .calmFont(size: 14.5, weight: .medium)
                    .foregroundStyle(style.primary)
                Spacer(minLength: 8)
                Text(keys)
                    .calmFont(size: 12)
                    .tracking(0.6)
                    .foregroundStyle(style.tertiary)
            }
            .padding(.leading, 12.scaled)
            .padding(.trailing, (agent == nil ? 16 : 40).scaled)
            .frame(width: 340.scaled, height: 54.scaled)
            .background(RoundedRectangle(cornerRadius: 10.scaled, style: .continuous).fill(fill))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.15), value: hovering)
        .accessibilityLabel(title)
    }
}

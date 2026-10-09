import CalmModel
import SwiftUI

/// A project's home (UIUX.md → Project home): its mark, name and folder at the left, the ways to
/// start a session in it as the welcome page's start line, and the sessions that ran there before.
struct ProjectHomeView: View {
    struct Actions {
        var agents = StartAgents()
        /// A session in the project running ⌘N's agent (nil), or another from the ⌄.
        let newAgentSession: (AgentKind?) -> Void
        let chooseNewSessionAgent: () -> Void
        /// A plain shell in the project, as ⌘T there.
        let newShell: () -> Void
        /// Resumes a past session, as a row on the welcome page does.
        let open: (SearchPanelModel.Item) -> Void
        /// Esc: the home goes, and the main area shows what it showed before one was open.
        let leave: () -> Void
    }

    @Bindable var model: ProjectHomeModel
    let style: SidebarStyle
    let background: Color
    let actions: Actions

    @FocusState private var focused: Bool

    /// Wide enough for a session's title, narrow enough to read as one column.
    private static let width: CGFloat = 560

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header
                startLine
                    .padding(.top, 28.scaled)
                if !model.sessions.isEmpty {
                    list
                        .padding(.top, 44.scaled)
                }
            }
            .frame(maxWidth: Self.width.scaled, alignment: .leading)
            .padding(.horizontal, 64.scaled)
            .padding(.top, 64.scaled)
            .padding(.bottom, 32.scaled)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollIndicators(.never)
        .background(background.ignoresSafeArea())
        .environment(\.colorScheme, style.isDark ? .dark : .light)
        .focusable()
        .focused($focused)
        .focusEffectDisabled()
        .onAppear { focused = true }
        .onChange(of: model.focusRequests) { focused = true }
        .onKeyPress(.downArrow) {
            model.step(1)
            return .handled
        }
        .onKeyPress(.upArrow) {
            model.step(-1)
            return .handled
        }
        .onKeyPress(.return) {
            guard let item = model.selectedItem else { return .ignored }
            actions.open(item)
            return .handled
        }
        .onKeyPress(.escape) {
            actions.leave()
            return .handled
        }
    }

    private var header: some View {
        HStack(spacing: 16.scaled) {
            IdenticonTile(identicon: Identicon(name: model.project.name, seed: model.project.markSeed), style: style, side: 52)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 5.scaled) {
                Text(model.project.name.uppercased())
                    .calmFont(size: 24, weight: .semibold)
                    .tracking(0.9)
                    .foregroundStyle(style.primary)
                    .lineLimit(1)
                    .accessibilityAddTraits(.isHeader)
                Text([WorkspacePath.abbreviated(model.project.path), model.branch].compactMap(\.self).joined(separator: " · "))
                    .calmFont(size: 12.5)
                    .foregroundStyle(style.tertiary)
                    .lineLimit(1)
                    .truncationMode(.head)
            }
        }
    }

    /// The welcome page's start line, for this project: ⌘N and ⌘T start here while its home is up.
    private var startLine: some View {
        HStack(spacing: 8.scaled) {
            if let agent = actions.agents.chosen {
                HintButton(
                    keys: "⌘N", title: agent.displayName, help: "New \(agent.displayName) Session (⌘N)", style: style,
                    action: { actions.newAgentSession(nil) },
                    menu: {
                        OtherAgentsMenu(
                            agents: actions.agents,
                            start: { actions.newAgentSession($0) },
                            choose: actions.chooseNewSessionAgent,
                        )
                    },
                )
                HintButton(keys: "⌘T", title: "Shell", help: "New Session (⌘T)", style: style, action: actions.newShell)
            } else {
                HintButton(keys: "⌘T", title: "New session", help: "New Session (⌘T)", style: style, action: actions.newShell)
            }
        }
    }

    private var list: some View {
        VStack(alignment: .leading, spacing: 8.scaled) {
            Text("EARLIER IN \(model.project.name.uppercased())")
                .calmFont(size: 12, weight: .semibold)
                .tracking(0.7)
                .foregroundStyle(style.tertiary)
                .lineLimit(1)
                .accessibilityAddTraits(.isHeader)
            VStack(spacing: 2.scaled) {
                ForEach(Array(model.sessions.enumerated()), id: \.element.id) { index, item in
                    ProjectHomeRow(item: item, isSelected: model.selected == index, style: style) {
                        model.selected = index
                        actions.open(item)
                    }
                }
            }
            // The rows' icons stand under the project's mark, their fill reaching past it.
            .padding(.horizontal, -12.scaled)
        }
    }
}

/// A past session in the project: the agent's mark, its title and how long ago. The pointer lights
/// it faintly; the arrow keys fill it and put ↵ where the time was, since only then does ↵ open it.
private struct ProjectHomeRow: View {
    let item: SearchPanelModel.Item
    let isSelected: Bool
    let style: SidebarStyle
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12.scaled) {
                AgentLogo(agent: item.result.agent, size: 28, style: style)
                Text(item.result.title)
                    .calmFont(size: 13.5, weight: .medium)
                    .foregroundStyle(isSelected || hovering ? style.primary : style.primary.opacity(0.84))
                    .lineLimit(1)
                Spacer(minLength: 8.scaled)
                ZStack(alignment: .trailing) {
                    Text(SearchPanelView.when(item.result.lastActive, now: Date()))
                        .calmFont(size: 12)
                        .foregroundStyle(style.tertiary)
                        .opacity(isSelected ? 0 : 1)
                    KeyCaps(keys: ["↵"], style: style).opacity(isSelected ? 1 : 0)
                }
            }
            .padding(.horizontal, 12.scaled)
            .frame(maxWidth: .infinity, minHeight: 54.scaled, maxHeight: 54.scaled, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 10.scaled, style: .continuous).fill(
                isSelected ? style.selection : hovering ? style.primary.opacity(0.04) : .clear,
            ))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
        .help(item.result.transcriptDeleted ? "The agent deleted this conversation" : "Resume in a new session")
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

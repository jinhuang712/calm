import CalmModel
import SwiftUI

/// A group's header in the sidebar (UIUX.md → Layout): its chevron, mark and name, and under the
/// pointer its controls in the place of a folded group's summary. A project's header is one bar
/// that opens the project's home; its chevron alone folds it. A folder's or scratch's header folds.
/// (Its own file: SidebarView.swift had reached its length limit.)
struct SidebarGroupHeader: View {
    let project: Project
    let summary: GroupSummary
    /// The project's home is in the main area: the bar is drawn selected, as a session's card is.
    let isHome: Bool
    let style: SidebarStyle
    /// ⌘N's agent, which the agent control starts; nil with none installed (the shell control stays).
    let agent: AgentKind?
    let actions: SidebarActions
    let toggleCollapsed: () -> Void
    let shuffleMark: () -> Void
    @State private var hovering = false

    private var opensHome: Bool {
        project.kind == .project
    }

    var body: some View {
        let tinted = project.isCollapsed && summary.needsYou
        Button {
            if opensHome {
                actions.showProjectHome(project.id)
            } else {
                toggleCollapsed()
            }
        } label: {
            HStack(spacing: 8.scaled) {
                chevron
                GroupMark(project: project, style: style, shuffle: shuffleMark)
                VStack(alignment: .leading, spacing: 1.scaled) {
                    name
                    if let location = project.location() {
                        // Where the folder is, so two groups with the same name can be told
                        // apart. Cut at the front: the folders nearest it say the most.
                        Text(location)
                            .calmFont(size: 11)
                            .foregroundStyle(style.tertiary)
                            .lineLimit(1)
                            .truncationMode(.head)
                    }
                }
                Spacer(minLength: 4)
                if hovering {
                    // Room for the hover controls laid over this end of the header.
                    Color.clear.frame(width: controlsWidth.scaled, height: 1)
                } else if project.isCollapsed {
                    GroupSummaryView(summary: summary, style: style)
                }
            }
            .foregroundStyle(isHome || (hovering && opensHome) ? style.secondary : style.tertiary)
            .padding(.horizontal, 8.scaled)
            .padding(.vertical, project.location() == nil ? 0 : 3.scaled)
            .frame(minHeight: 26.scaled)
            .background(
                // Drawn a little past the header's height, so the bar reads as a row without the
                // sidebar's spacing changing.
                RoundedRectangle(cornerRadius: 10.scaled, style: .continuous)
                    .fill(fill(tinted: tinted))
                    .padding(.vertical, -5.scaled)
                    .animation(.easeInOut(duration: 0.2), value: tinted)
                    .animation(.easeOut(duration: 0.12), value: hovering),
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
        .overlay(alignment: .trailing) {
            if hovering {
                controls.padding(.trailing, 4.scaled)
            }
        }
        .onHover { hovering = $0 }
        .contextMenu { menu }
        .accessibilityAddTraits(isHome ? .isSelected : [])
    }

    /// A shell row's *needs you* tint, so folding a group never hides one; the selection while the
    /// project's home is up; a faint fill under the pointer, since the whole bar is the target.
    private func fill(tinted: Bool) -> Color {
        if tinted {
            style.attention.opacity(0.14)
        } else if isHome {
            style.selection
        } else if hovering {
            style.selection.opacity(0.55)
        } else {
            .clear
        }
    }

    @ViewBuilder
    private var chevron: some View {
        let image = Image(systemName: "chevron.down")
            .calmFont(size: 9, weight: .semibold)
            .rotationEffect(.degrees(project.isCollapsed ? -90 : 0))
            .frame(width: 10.scaled)
        if opensHome {
            // A project's bar opens its home, so its chevron folds it on its own: a target a
            // little wider than the glyph, winning over the bar as the mark's click does.
            image
                .frame(width: 18.scaled, height: 26.scaled)
                .contentShape(Rectangle())
                .padding(.horizontal, -4.scaled)
                .highPriorityGesture(TapGesture().onEnded(toggleCollapsed))
                .accessibilityLabel(project.isCollapsed ? "Expand" : "Collapse")
                .accessibilityAddTraits(.isButton)
        } else {
            image
        }
    }

    @ViewBuilder
    private var name: some View {
        if project.kind == .directory {
            // A folder's own name, as it is on disk.
            Text(project.name)
                .calmFont(size: 13.5, weight: .medium)
                .foregroundStyle(style.secondary)
                .lineLimit(1)
        } else {
            Text(project.name.uppercased())
                .calmFont(size: 12, weight: .semibold)
                .tracking(0.7)
                .lineLimit(1)
        }
    }

    /// The folder, and for a folded group its line in words, since hovering swaps the marks for
    /// the group's controls. A scratch group's folder is Calm's business; the others show theirs.
    private var help: String {
        [project.kind == .scratch ? nil : project.path, project.isCollapsed ? summary.words : nil]
            .compactMap(\.self)
            .joined(separator: "\n")
    }

    // MARK: Controls

    /// A group's own actions, shown on hover in the place of its summary (UIUX.md → Layout): the
    /// agent's mark starts a session running it there, `>_` a plain shell (a scratch group has one
    /// +, a scratch session); ⋯ holds what changes the group itself, one step away.
    private var controls: some View {
        HStack(spacing: 2.scaled) {
            if project.kind == .scratch {
                GroupControl(style: style, systemImage: "plus", help: "New Scratch Session") { actions.newScratchSession() }
            } else {
                if let agent {
                    GroupControl(style: style, glyph: .agent(agent), help: "New \(agent.displayName) Session Here") {
                        actions.newAgentSessionIn(project)
                    }
                }
                GroupControl(style: style, glyph: .shell, help: "New Shell Here") { actions.newSessionIn(project) }
                Menu {
                    switch project.kind {
                    case .directory: Button("Make Project") { actions.makeProject(project.id) }
                    case .project: Button("Remove Project") { actions.removeProject(project.id) }
                    case .scratch: EmptyView()
                    }
                } label: {
                    GroupControlLabel(style: style, systemImage: "ellipsis")
                }
                .menuStyle(.button)
                .buttonStyle(.plain)
                .menuIndicator(.hidden)
                .fixedSize()
                .help(project.kind == .project ? "Remove Project" : "Make Project")
            }
        }
    }

    /// The controls' width at the standard interface size: 22 points each, 2 between.
    private var controlsWidth: CGFloat {
        let count = project.kind == .scratch ? 1 : (agent == nil ? 2 : 3)
        return CGFloat(count) * 22 + CGFloat(count - 1) * 2
    }

    @ViewBuilder
    private var menu: some View {
        switch project.kind {
        case .scratch:
            Button("New Scratch Session") { actions.newScratchSession() }
        case .project, .directory:
            if project.kind == .project {
                Button("Show Home") { actions.showProjectHome(project.id) }
            } else {
                Button("Make Project") { actions.makeProject(project.id) }
            }
            if let agent {
                Button("New \(agent.displayName) Session Here") { actions.newAgentSessionIn(project) }
            }
            Button("New Shell Here") { actions.newSessionIn(project) }
        }
        Button(project.isCollapsed ? "Expand" : "Collapse", action: toggleCollapsed)
        if project.kind == .project {
            Divider()
            // Only the grouping goes: sessions stay open and files stay put, so no confirmation.
            Button("Remove Project") { actions.removeProject(project.id) }
        }
    }
}

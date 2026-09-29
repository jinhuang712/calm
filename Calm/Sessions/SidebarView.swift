import CalmAgents
import CalmModel
import SwiftUI

/// Colors for the sidebar, derived from the focused terminal's background so the chrome
/// always matches the theme (UIUX.md → Color).
struct SidebarStyle: Equatable {
    var background: Color
    var selection: Color
    var primary: Color
    var secondary: Color
    var tertiary: Color
    /// *Needs you*: a soft, low-saturation amber on every theme, so it never reads as another
    /// state's color (a blue accent looked like *working*, a green one like *done*; UIUX.md → Color).
    var attention: Color
    /// The theme's accent, for chrome only: a switch that's on, the picked theme, the project mark.
    /// Calm's amber when the theme has none.
    var accent: Color
    /// *Failed*: a muted red, used for nothing else but deletions in the files column.
    var failure: Color
    var isDark: Bool
    /// How opaque the sidebar and files column are: less on a glass window (WindowStyle).
    var surfaceOpacity = 1.0

    /// *Working*: a soft, cool blue, quieter than *needs you* (UIUX.md → Color).
    var working: Color {
        Color(hue: 0.59, saturation: isDark ? 0.31 : 0.45, brightness: isDark ? 0.85 : 0.58)
    }

    /// The light that crosses *Working*.
    var workingHighlight: Color {
        isDark ? .white.opacity(0.75) : Color(hue: 0.59, saturation: 0.8, brightness: 0.72)
    }

    /// *Done*, until the user looks: a soft sage. The files column's added lines take it too.
    var done: Color {
        Color(hue: 0.3, saturation: isDark ? 0.23 : 0.42, brightness: isDark ? 0.75 : 0.5)
    }

    /// With `theme` (the Calm theme whose background the terminal shows), the chrome takes the
    /// theme's own sidebar, text, accent and red instead of derived ones (UIUX.md → Color).
    static func derived(from terminalBackground: NSColor, theme: CalmTheme.Colors? = nil) -> SidebarStyle {
        var style = derived(from: terminalBackground)
        guard let theme else { return style }
        if let sidebar = theme.sidebar.flatMap(NSColor.init(hex:)) {
            style.background = Color(nsColor: sidebar)
        }
        if let foreground = NSColor(hex: theme.foreground) {
            style.primary = Color(nsColor: foreground)
            style.secondary = Color(nsColor: foreground.withAlphaComponent(0.66))
            style.tertiary = Color(nsColor: foreground.withAlphaComponent(0.46))
        }
        if let accent = theme.accent.flatMap(NSColor.init(hex:)) {
            style.accent = Color(nsColor: accent)
        }
        if theme.palette.count == 16, let red = NSColor(hex: theme.palette[1]) {
            style.failure = Color(nsColor: red)
        }
        return style
    }

    /// Increase Contrast (UIUX.md → Accessibility): secondary text, hints and the selection get
    /// stronger; the layout and colors stay the same.
    @MainActor
    func contrasted(_ on: Bool = AccessibilitySettings.increaseContrast) -> SidebarStyle {
        guard on else { return self }
        var style = self
        let ink = NSColor(primary).withAlphaComponent(1)
        style.primary = Color(nsColor: ink)
        style.secondary = Color(nsColor: ink.withAlphaComponent(0.82))
        style.tertiary = Color(nsColor: ink.withAlphaComponent(0.66))
        style.selection = Color(nsColor: ink.withAlphaComponent(isDark ? 0.16 : 0.14))
        return style
    }

    private static func derived(from terminalBackground: NSColor) -> SidebarStyle {
        let base = terminalBackground.usingColorSpace(.sRGB) ?? terminalBackground
        let isDark = base.brightnessComponent < 0.5
        let shade = isDark ? NSColor.black : NSColor(white: 0.0, alpha: 1)
        let background = base.blended(withFraction: isDark ? 0.18 : 0.04, of: shade) ?? base
        let ink = isDark ? NSColor.white : NSColor.black
        let amber = Color(hue: 0.11, saturation: isDark ? 0.42 : 0.55, brightness: isDark ? 0.86 : 0.62)
        return SidebarStyle(
            background: Color(nsColor: background),
            selection: Color(nsColor: ink.withAlphaComponent(isDark ? 0.08 : 0.07)),
            primary: Color(nsColor: ink.withAlphaComponent(isDark ? 0.86 : 0.85)),
            secondary: Color(nsColor: ink.withAlphaComponent(isDark ? 0.55 : 0.55)),
            tertiary: Color(nsColor: ink.withAlphaComponent(isDark ? 0.38 : 0.4)),
            attention: amber,
            accent: amber,
            failure: Color(hue: 0.0, saturation: isDark ? 0.38 : 0.5, brightness: isDark ? 0.82 : 0.6),
            isDark: isDark,
        )
    }
}

/// Projects and their sessions: the periphery, where status lives.
struct SidebarView: View {
    /// 320 points at the standard interface size.
    @MainActor
    static var width: CGFloat {
        320.scaled
    }

    let manager: SessionManager
    let style: SidebarStyle
    let onSelect: (Session.ID) -> Void
    let onClose: (Session.ID) -> Void
    let onNewSession: () -> Void
    let onNewProject: () -> Void
    let editing: SidebarEditing
    let actions: SidebarActions
    @State private var draftName = ""
    @FocusState private var nameFieldFocused: Bool
    @State private var hoveredSessionID: Session.ID?
    @State private var hoveredGroupID: Project.ID?

    /// Ties a session's row across projects, so a row that changes project glides there.
    @Namespace private var rows

    private var selectedSessionID: Session.ID? {
        manager.workspace.selectedLayout?.focusedSessionID
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Room for the window's traffic lights. The titlebar's safe area is ignored below, so
            // this is the only gap; counting both left a hole above the search field.
            // As tall as the window's title strip, so the search field and the terminal start level.
            Color.clear.frame(height: CalmWindow.titleStripHeight)
            searchField
                .padding(.horizontal, 14.scaled)
                .padding(.bottom, 18.scaled)

            ScrollView {
                // Not lazy: a row moving between projects needs both ends laid out to glide.
                VStack(alignment: .leading, spacing: 22.scaled) {
                    // Scratch sessions on top, then projects the user made, then directory groups.
                    ForEach(manager.workspace.orderedProjects) { project in
                        projectSection(project)
                    }
                }
                .padding(.horizontal, 12.scaled)
                .padding(.bottom, 16.scaled)
            }
            .scrollIndicators(.never)

            footer
        }
        .frame(width: Self.width)
        .frame(maxHeight: .infinity)
        .ignoresSafeArea(.container, edges: .top)
        .background(style.background.opacity(style.surfaceOpacity))
        // The adaptive background (UIUX.md → Motion): when an app repaints the terminal's
        // background, the sidebar eases into the new colors instead of snapping.
        .animation(Motion.isReduced ? nil : .easeInOut(duration: 0.35), value: style)
        // Laid out at full width and clipped while the sidebar slides, never squeezed.
        .frame(maxWidth: .infinity, alignment: .leading)
        .dropDestination(for: URL.self) { urls, _ in
            let folders = urls.filter(\.hasDirectoryPath)
            actions.addProjects(folders)
            return !folders.isEmpty
        }
        .environment(\.colorScheme, style.isDark ? .dark : .light)
    }

    // MARK: Sections

    private func projectSection(_ project: Project) -> some View {
        let sessions = manager.workspace.sessions(in: project.id)
        return VStack(alignment: .leading, spacing: 6.scaled) {
            Button {
                manager.toggleCollapsed(project.id)
            } label: {
                HStack(spacing: 8.scaled) {
                    Image(systemName: "chevron.down")
                        .calmFont(size: 9, weight: .semibold)
                        .rotationEffect(.degrees(project.isCollapsed ? -90 : 0))
                        .frame(width: 10.scaled)
                    GroupMark(project: project, style: style) { manager.shuffleMark(project.id) }
                    groupName(project)
                    Spacer(minLength: 4)
                    if hoveredGroupID == project.id {
                        // Room for the hover controls laid over this end of the header.
                        Color.clear.frame(width: groupControlsWidth(project), height: 1)
                    } else if project.isCollapsed {
                        Text(summary(sessions))
                            .calmFont(size: 12)
                            .foregroundStyle(style.tertiary)
                    } else if project.kind == .directory, project.path != WorkspacePath.standardize(NSHomeDirectory()) {
                        // Where the folder is, so two groups with the same name can be told apart.
                        Text(WorkspacePath.displayName(for: (project.path as NSString).deletingLastPathComponent))
                            .calmFont(size: 12)
                            .foregroundStyle(style.tertiary)
                            .lineLimit(1)
                            .truncationMode(.head)
                    }
                }
                .foregroundStyle(style.tertiary)
                .padding(.horizontal, 8.scaled)
                .frame(height: 26.scaled)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            // A scratch group's folder is Calm's business; the others show theirs.
            .help(project.kind == .scratch ? "" : project.path)
            .overlay(alignment: .trailing) {
                if hoveredGroupID == project.id {
                    groupControls(project).padding(.trailing, 4.scaled)
                }
            }
            .onHover { hoveredGroupID = $0 ? project.id : (hoveredGroupID == project.id ? nil : hoveredGroupID) }
            .contextMenu { groupMenu(project) }

            if !project.isCollapsed {
                ForEach(sessions) { session in
                    sessionView(session)
                        .onHover { hoveredSessionID = $0 ? session.id : (hoveredSessionID == session.id ? nil : hoveredSessionID) }
                        .onTapGesture { onSelect(session.id) }
                        .contextMenu {
                            SessionMenu(
                                session: session, manager: manager, actions: actions,
                                onRename: { beginRename(session) }, onClose: { onClose(session.id) },
                            )
                        }
                        .matchedGeometryEffect(id: session.id, in: rows)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
        }
    }

    @ViewBuilder
    private func groupMenu(_ project: Project) -> some View {
        switch project.kind {
        case .scratch:
            Button("New Scratch Session") { actions.newScratchSession() }
        case .project:
            Button("New Session Here") { actions.newSessionIn(project) }
        case .directory:
            Button("Make Project") { actions.makeProject(project.id) }
            Button("New Session Here") { actions.newSessionIn(project) }
        }
        Button(project.isCollapsed ? "Expand" : "Collapse") { manager.toggleCollapsed(project.id) }
        if project.kind == .project {
            Divider()
            // Only the grouping goes: sessions stay open and files stay put, so no confirmation.
            Button("Remove Project") { actions.removeProject(project.id) }
        }
    }

    /// A group's own actions, shown on hover in the place of its summary (UIUX.md → Layout):
    /// + starts a session there; ⋯ holds what changes the group itself, one step away.
    private func groupControls(_ project: Project) -> some View {
        HStack(spacing: 2.scaled) {
            GroupControl(style: style, systemImage: "plus", help: project.kind == .scratch ? "New Scratch Session" : "New Session Here") {
                if project.kind == .scratch {
                    actions.newScratchSession()
                } else {
                    actions.newSessionIn(project)
                }
            }
            if project.kind != .scratch {
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

    private func groupControlsWidth(_ project: Project) -> CGFloat {
        project.kind == .scratch ? 22 : 46
    }

    @ViewBuilder
    private func groupName(_ project: Project) -> some View {
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

    private func beginRename(_ session: Session) {
        editing.renamingSessionID = session.id
    }

    /// The inline name field that stands in for a session's card while it's renamed: return keeps
    /// the name, esc keeps the old one, and an empty name gives the session back its own title.
    private func nameField(_ session: Session) -> some View {
        TextField("Name", text: $draftName, prompt: Text(session.title(agentTitle: session.agent?.tail?.title)))
            .textFieldStyle(.plain)
            .calmFont(size: 14.5, weight: .medium)
            .foregroundStyle(style.primary)
            .focused($nameFieldFocused)
            .onSubmit { actions.rename(session.id, draftName) }
            .onExitCommand { editing.renamingSessionID = nil }
            .onChange(of: nameFieldFocused) { _, focused in
                if !focused, editing.renamingSessionID == session.id {
                    actions.rename(session.id, draftName)
                }
            }
            .padding(.horizontal, 12.scaled)
            .frame(height: 40.scaled)
            .background(RoundedRectangle(cornerRadius: 10.scaled, style: .continuous).fill(style.selection))
            .overlay(RoundedRectangle(cornerRadius: 10.scaled, style: .continuous).strokeBorder(style.tertiary.opacity(0.4)))
            .onAppear {
                // Also where the title's ⋯ menu starts a rename, which only sets `editing`.
                draftName = session.customName ?? session.title(agentTitle: session.agent?.tail?.title)
                nameFieldFocused = true
            }
    }

    /// Agent sessions get a card; plain shells stay one compact line (UIUX.md → Session cards).
    @ViewBuilder
    private func sessionView(_ session: Session) -> some View {
        if editing.renamingSessionID == session.id {
            nameField(session)
        } else if let agent = session.agent?.kind {
            SessionCard(
                session: session, agent: agent, isSelected: session.id == selectedSessionID, style: style,
                isHovered: hoveredSessionID == session.id,
            )
        } else {
            SessionRow(
                session: session, isSelected: session.id == selectedSessionID, style: style,
                isHovered: hoveredSessionID == session.id,
            )
        }
    }

    /// "2 sessions · 1 needs you": the collapsed project's one line.
    private func summary(_ sessions: [Session]) -> String {
        var parts = [sessions.count == 1 ? "1 session" : "\(sessions.count) sessions"]
        for state in [SessionState.needsYou, .failed, .done] {
            let count = sessions.count { $0.state == state }
            if count > 0 {
                parts.append("\(count) \(state.label.lowercased())")
            }
        }
        return parts.joined(separator: " · ")
    }

    /// ⌘K's search (FEATURES.md → F7), where the eye looks first: the top of the sidebar.
    private var searchField: some View {
        FooterButton(style: style, help: "Search Sessions (⌘K)", action: actions.search) {
            HStack(spacing: 10.scaled) {
                Image(systemName: "magnifyingglass")
                    .calmFont(size: 14, weight: .medium)
                Text("Search sessions")
                    .calmFont(size: 14)
                Spacer(minLength: 4)
                KeyCaps(keys: ["⌘", "K"], style: style)
            }
            .foregroundStyle(style.tertiary)
            .padding(.leading, 12.scaled)
            .padding(.trailing, 9.scaled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: 38.scaled)
            .background(RoundedRectangle(cornerRadius: 10.scaled, style: .continuous).fill(style.primary.opacity(0.055)))
            .overlay(RoundedRectangle(cornerRadius: 10.scaled, style: .continuous).strokeBorder(style.primary.opacity(0.06)))
        }
        .accessibilityLabel("Search sessions")
    }

    /// The three ways to start something, one row each with its shortcut, so the corner reads at
    /// a glance and every target is a full row.
    private var footer: some View {
        VStack(spacing: 2.scaled) {
            footerRow("New Session", symbol: "square.and.pencil", keys: ["⌘", "T"], action: onNewSession)
            footerRow("New Scratch Session", symbol: "square.dashed", keys: ["⌘", "⇧", "N"], action: actions.newScratchSession)
            footerRow("New Project…", symbol: "plus", keys: ["⌘", "O"], action: onNewProject)
        }
        .padding(.horizontal, 12.scaled)
        .padding(.top, 10.scaled)
        .padding(.bottom, 14.scaled)
        .overlay(alignment: .top) { Rectangle().fill(style.tertiary.opacity(0.14)).frame(height: 1) }
    }

    private func footerRow(_ title: String, symbol: String, keys: [String], action: @escaping () -> Void) -> some View {
        FooterButton(style: style, help: "\(title) (\(keys.joined()))", action: action) {
            HStack(spacing: 11.scaled) {
                Image(systemName: symbol)
                    .calmFont(size: 14)
                    .frame(width: 28.scaled, height: 28.scaled)
                    .background(RoundedRectangle(cornerRadius: 8.scaled, style: .continuous).fill(style.primary.opacity(0.055)))
                Text(title)
                    .calmFont(size: 14)
                Spacer(minLength: 4)
                KeyCaps(keys: keys, style: style)
            }
            .padding(.horizontal, 8.scaled)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// A sidebar control: a full-height target with a quiet hover background.
private struct FooterButton<Label: View>: View {
    let style: SidebarStyle
    let help: String
    let action: () -> Void
    @ViewBuilder let label: Label
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            label
                .frame(minHeight: 40.scaled)
                .foregroundStyle(hovering ? style.primary : style.secondary)
                .background(RoundedRectangle(cornerRadius: 10.scaled, style: .continuous).fill(hovering ? style.selection : .clear))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(help)
    }
}

/// One of a group header's hover controls: a small glyph that lights up under the pointer.
private struct GroupControl: View {
    let style: SidebarStyle
    let systemImage: String
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            GroupControlLabel(style: style, systemImage: systemImage)
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
    }
}

private struct GroupControlLabel: View {
    let style: SidebarStyle
    let systemImage: String
    @State private var hovering = false

    var body: some View {
        Image(systemName: systemImage)
            .calmFont(size: 11, weight: .semibold)
            .foregroundStyle(hovering ? style.primary : style.tertiary)
            .frame(width: 22.scaled, height: 22.scaled)
            .background(RoundedRectangle(cornerRadius: 6.scaled, style: .continuous).fill(hovering ? style.selection : .clear))
            .contentShape(Rectangle())
            .onHover { hovering = $0 }
    }
}

/// A shortcut drawn as small key caps (⌘ T), the way the menu bar would print it but calmer.
struct KeyCaps: View {
    let keys: [String]
    let style: SidebarStyle
    /// The welcome page's bigger caps.
    var large = false

    var body: some View {
        HStack(spacing: (large ? 4 : 3).scaled) {
            ForEach(Array(keys.enumerated()), id: \.offset) { _, key in
                Text(key)
                    .calmFont(size: large ? 12 : 11.5)
                    .foregroundStyle(style.tertiary)
                    .frame(minWidth: (large ? 24 : 20).scaled, minHeight: (large ? 24 : 20).scaled)
                    .padding(.horizontal, (key.count > 1 ? 4 : 0).scaled)
                    .background(
                        RoundedRectangle(cornerRadius: (large ? 6 : 5).scaled, style: .continuous)
                            .fill(style.primary.opacity(0.06)),
                    )
            }
        }
        .accessibilityHidden(true)
    }
}

/// The sidebar's session actions, handled by the window controller.
struct SidebarActions {
    let rename: (Session.ID, String?) -> Void
    let resume: (Session.ID) -> Void
    let fork: (Session.ID, MainWindowController.ForkDestination) -> Void
    let newScratchSession: () -> Void
    let search: () -> Void
    let newSessionIn: (Project) -> Void
    let addProjects: ([URL]) -> Void
    let makeProject: (Project.ID) -> Void
    let removeProject: (Project.ID) -> Void
    let move: (Session.ID, Project.ID) -> Void
    let followFolder: (Session.ID) -> Void
    let keepScratch: (Session.ID) -> Void
    let copy: (Session.ID, SessionCopy) -> Void
    let reveal: (Session.ID) -> Void
}

/// A group's kind at a glance (UIUX.md → Layout): a project the user made, a folder, scratch.
struct GroupMark: View {
    let project: Project
    let style: SidebarStyle
    /// Clicking a project's mark swaps it for another (an easter egg, FEATURES.md → F2).
    var shuffle: () -> Void = {}

    var body: some View {
        switch project.kind {
        case .project:
            let identicon = Identicon(name: project.name, seed: project.markSeed)
            IdenticonTile(identicon: identicon, style: style)
                // A new view per mark, so the old one crossfades into the new.
                .id(identicon)
                .transition(.opacity)
                // Wins over the header's button, so the click doesn't also collapse the group.
                .highPriorityGesture(TapGesture().onEnded(shuffle))
                .accessibilityLabel("Project")
        case .directory:
            Image(systemName: "folder")
                .calmFont(size: 12)
                .accessibilityLabel("Folder")
        case .scratch:
            Image(systemName: "square.dashed")
                .calmFont(size: 12)
                .accessibilityLabel("Scratch")
        }
    }
}

/// A project's pixel mark from its name, a 20 pt tile that fits the 26 pt header: the mark's soft
/// hue on a pale tile of it (a deep one on a dark theme), low in saturation so it sits beside
/// the state colors without competing (UIUX.md → Color).
struct IdenticonTile: View {
    let identicon: Identicon
    let style: SidebarStyle
    /// The tile's side at the standard interface size: 20 in the sidebar, larger on the welcome page.
    var side: CGFloat = 20

    var body: some View {
        let hue = identicon.hue
        let pixels = Color(hue: hue, saturation: style.isDark ? 0.38 : 0.42, brightness: style.isDark ? 0.78 : 0.62)
        let tile = Color(hue: hue, saturation: 0.18, brightness: style.isDark ? 0.26 : 0.93)
        Canvas { context, size in
            // Whole points per cell, so the pixels stay crisp instead of blurring across two: 3 at
            // the standard interface size, growing with the tile.
            let cell = (size.width * 0.15).rounded()
            let inset = (size.width - cell * CGFloat(Identicon.size)) / 2
            var cells = Path()
            for (row, columns) in identicon.cells.enumerated() {
                for (column, isOn) in columns.enumerated() where isOn {
                    cells.addRect(CGRect(x: inset + CGFloat(column) * cell, y: inset + CGFloat(row) * cell, width: cell, height: cell))
                }
            }
            context.fill(
                Path(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: size.width * 0.24, style: .continuous),
                with: .color(tile),
            )
            context.fill(cells, with: .color(pixels))
        }
        .frame(width: side.scaled, height: side.scaled)
    }
}

/// A compact session row. Rich cards (state, progress, recap, worktree) arrive in Milestone 3.
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

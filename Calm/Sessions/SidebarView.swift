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
    /// *Needs you*: a soft, low-saturation amber, the only tint a card gets (UIUX.md → Color).
    var attention: Color
    /// *Failed*: a muted red, used for nothing else.
    var failure: Color
    var isDark: Bool
    /// How opaque the sidebar and files column are: less on a glass window (WindowStyle).
    var surfaceOpacity = 1.0

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
            style.attention = Color(nsColor: accent)
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
        return SidebarStyle(
            background: Color(nsColor: background),
            selection: Color(nsColor: ink.withAlphaComponent(isDark ? 0.08 : 0.07)),
            primary: Color(nsColor: ink.withAlphaComponent(isDark ? 0.86 : 0.85)),
            secondary: Color(nsColor: ink.withAlphaComponent(isDark ? 0.55 : 0.55)),
            tertiary: Color(nsColor: ink.withAlphaComponent(isDark ? 0.38 : 0.4)),
            attention: Color(hue: 0.11, saturation: isDark ? 0.42 : 0.55, brightness: isDark ? 0.86 : 0.62),
            failure: Color(hue: 0.0, saturation: isDark ? 0.38 : 0.5, brightness: isDark ? 0.82 : 0.6),
            isDark: isDark,
        )
    }
}

/// Projects and their sessions: the periphery, where status lives.
struct SidebarView: View {
    static let width: CGFloat = 280
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

    /// Ties a session's row across projects, so a row that changes project glides there.
    @Namespace private var rows

    private var selectedSessionID: Session.ID? {
        manager.workspace.selectedLayout?.focusedSessionID
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Room for the window's traffic lights.
            Color.clear.frame(height: 38)

            ScrollView {
                // Not lazy: a row moving between projects needs both ends laid out to glide.
                VStack(alignment: .leading, spacing: 14) {
                    // Scratch sessions on top, then projects the user made, then directory groups.
                    ForEach(manager.workspace.orderedProjects) { project in
                        projectSection(project)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 12)
            }
            .scrollIndicators(.never)

            footer
        }
        .frame(width: Self.width)
        .frame(maxHeight: .infinity)
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
        return VStack(alignment: .leading, spacing: 2) {
            Button {
                manager.toggleCollapsed(project.id)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8, weight: .semibold))
                        .rotationEffect(.degrees(project.isCollapsed ? -90 : 0))
                        .frame(width: 10)
                    GroupMark(kind: project.kind, style: style)
                    groupName(project)
                    Spacer(minLength: 4)
                    if project.isCollapsed {
                        Text(summary(sessions))
                            .font(.system(size: 11))
                            .foregroundStyle(style.tertiary)
                    } else if project.kind == .directory, project.path != WorkspacePath.standardize(NSHomeDirectory()) {
                        // Where the folder is, so two groups with the same name can be told apart.
                        Text(WorkspacePath.displayName(for: (project.path as NSString).deletingLastPathComponent))
                            .font(.system(size: 11))
                            .foregroundStyle(style.tertiary)
                            .lineLimit(1)
                            .truncationMode(.head)
                    }
                }
                .foregroundStyle(style.secondary)
                .padding(.horizontal, 6)
                .frame(height: 22)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            // A scratch group's folder is Calm's business; the others show theirs.
            .help(project.kind == .scratch ? "" : project.path)
            .contextMenu { groupMenu(project) }

            if !project.isCollapsed {
                ForEach(sessions) { session in
                    sessionView(session)
                        .overlay(alignment: .topTrailing) { closeButton(session) }
                        .onHover { hoveredSessionID = $0 ? session.id : (hoveredSessionID == session.id ? nil : hoveredSessionID) }
                        .onTapGesture { onSelect(session.id) }
                        .contextMenu { sessionMenu(session) }
                        .matchedGeometryEffect(id: session.id, in: rows)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
        }
    }

    /// A session's right-click actions (FEATURES.md → F12): the agent-backed ones appear only
    /// where its agent has the command.
    @ViewBuilder
    private func sessionMenu(_ session: Session) -> some View {
        Button("Rename…") { beginRename(session) }
        if MainWindowController.resumeCommand(for: session) != nil, let kind = session.resumableConversation?.kind {
            Button("Resume \(kind.displayName) Conversation") { actions.resume(session.id) }
        }
        if MainWindowController.forkCommand(for: session) != nil {
            Button("Fork into New Split") { actions.fork(session.id, .split) }
            Button("Fork into New Tab") { actions.fork(session.id, .tab) }
        }
        Divider()
        if session.isScratch {
            Button("Keep as Project…") { actions.keepScratch(session.id) }
        } else {
            let projects = manager.workspace.orderedProjects.filter { $0.kind == .project && $0.id != session.projectID }
            if !projects.isEmpty {
                Menu("Move to Project") {
                    ForEach(projects) { project in
                        Button(project.name) { actions.move(session.id, project.id) }
                    }
                }
            }
            if session.isPinned, manager.workspace.project(session.projectID)?.kind == .project {
                Button("Let It Follow Its Folder") { actions.followFolder(session.id) }
            }
        }
        Divider()
        Button("Close Session") { onClose(session.id) }
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
    }

    @ViewBuilder
    private func groupName(_ project: Project) -> some View {
        if project.kind == .directory {
            // A folder's own name, as it is on disk.
            Text(project.name)
                .font(.system(size: 12))
                .lineLimit(1)
        } else {
            Text(project.name.uppercased())
                .font(.system(size: 11, weight: .medium))
                .tracking(0.6)
                .lineLimit(1)
        }
    }

    /// A scratch session is closed when it's done: its row offers that, quietly, on hover or
    /// while selected.
    @ViewBuilder
    private func closeButton(_ session: Session) -> some View {
        if session.isScratch, editing.renamingSessionID != session.id,
           hoveredSessionID == session.id || selectedSessionID == session.id {
            Button { onClose(session.id) } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(style.secondary)
                    .frame(width: 18, height: 18)
                    .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(style.selection))
            }
            .buttonStyle(.plain)
            .help("Close Scratch Session")
            .accessibilityLabel("Close scratch session")
            .padding(.top, 6)
            .padding(.trailing, 6)
        }
    }

    private func beginRename(_ session: Session) {
        draftName = session.customName ?? session.title(agentTitle: session.agent?.tail?.title)
        editing.renamingSessionID = session.id
        nameFieldFocused = true
    }

    /// The inline name field that stands in for a session's card while it's renamed: return keeps
    /// the name, esc keeps the old one, and an empty name gives the session back its own title.
    private func nameField(_ session: Session) -> some View {
        TextField("Name", text: $draftName, prompt: Text(session.title(agentTitle: session.agent?.tail?.title)))
            .textFieldStyle(.plain)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(style.primary)
            .focused($nameFieldFocused)
            .onSubmit { actions.rename(session.id, draftName) }
            .onExitCommand { editing.renamingSessionID = nil }
            .onChange(of: nameFieldFocused) { _, focused in
                if !focused, editing.renamingSessionID == session.id {
                    actions.rename(session.id, draftName)
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 30)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(style.selection))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(style.tertiary.opacity(0.4)))
            .onAppear { nameFieldFocused = true }
    }

    /// Agent sessions get a card; plain shells stay one compact line (UIUX.md → Session cards).
    @ViewBuilder
    private func sessionView(_ session: Session) -> some View {
        if editing.renamingSessionID == session.id {
            nameField(session)
        } else if let agent = session.agent?.kind {
            SessionCard(session: session, agent: agent, isSelected: session.id == selectedSessionID, style: style)
        } else {
            SessionRow(session: session, isSelected: session.id == selectedSessionID, style: style)
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

    private var footer: some View {
        HStack(spacing: 4) {
            Button(action: onNewProject) {
                Label("New Project", systemImage: "plus")
                    .font(.system(size: 12))
            }
            .buttonStyle(.plain)
            .foregroundStyle(style.secondary)
            Spacer()
            Button(action: actions.newScratchSession) {
                Image(systemName: "square.dashed")
                    .font(.system(size: 12))
            }
            .buttonStyle(.plain)
            .foregroundStyle(style.secondary)
            .help("New Scratch Session (⌘⇧N)")
            .accessibilityLabel("New scratch session")
            Button(action: onNewSession) {
                Image(systemName: "square.and.pencil")
                    .font(.system(size: 12))
            }
            .buttonStyle(.plain)
            .foregroundStyle(style.secondary)
            .help("New Session (⌘T)")
            .padding(.leading, 8)
        }
        .padding(.horizontal, 16)
        .frame(height: 40)
    }
}

/// The sidebar's session actions, handled by the window controller.
struct SidebarActions {
    let rename: (Session.ID, String?) -> Void
    let resume: (Session.ID) -> Void
    let fork: (Session.ID, MainWindowController.ForkDestination) -> Void
    let newScratchSession: () -> Void
    let newSessionIn: (Project) -> Void
    let addProjects: ([URL]) -> Void
    let makeProject: (Project.ID) -> Void
    let move: (Session.ID, Project.ID) -> Void
    let followFolder: (Session.ID) -> Void
    let keepScratch: (Session.ID) -> Void
}

/// A group's kind at a glance (UIUX.md → Layout): a project the user made, a folder, scratch.
struct GroupMark: View {
    let kind: Project.Kind
    let style: SidebarStyle

    var body: some View {
        switch kind {
        case .project:
            Image(systemName: "square.stack")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(style.attention)
                .accessibilityLabel("Project")
        case .directory:
            Image(systemName: "folder")
                .font(.system(size: 9))
                .accessibilityLabel("Folder")
        case .scratch:
            Image(systemName: "square.dashed")
                .font(.system(size: 9))
                .accessibilityLabel("Scratch")
        }
    }
}

/// A compact session row. Rich cards (state, progress, recap, worktree) arrive in Milestone 3.
struct SessionRow: View {
    let session: Session
    let isSelected: Bool
    let style: SidebarStyle

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: "chevron.right")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(style.tertiary)
                .frame(width: 18, height: 18)
                .background(RoundedRectangle(cornerRadius: 5).strokeBorder(style.tertiary.opacity(0.5)))
            Text(session.displayTitle)
                .font(.system(size: 13, weight: isSelected ? .medium : .regular))
                .foregroundStyle(isSelected ? style.primary : style.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 4)
            if session.state != .idle {
                StateMark(state: session.state, style: style)
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 30)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(session.state == .needsYou ? style.attention.opacity(0.19) : isSelected ? style.selection : .clear),
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

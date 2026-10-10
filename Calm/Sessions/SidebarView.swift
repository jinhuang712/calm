import CalmAgents
import CalmModel
import SwiftUI

/// Colors for the sidebar, derived from the focused terminal's background so the chrome
/// always matches the theme (UIUX.md → Color).
struct SidebarStyle: Equatable {
    var background: Color
    var selection: Color
    /// The ring around the selected row. A state is a color and the selection is a ring and a
    /// lighter surface, so the two never blur: a done card's slightly stronger sage alone read as
    /// "more done", not "selected".
    var selectionEdge: Color
    /// Laid under the selected card's own fill, so it comes out lighter than the cards around it
    /// in either theme (a darker card in light mode turned the tints muddy).
    var selectionLift: Color
    /// The ring's width in points, inside the row's edge so choosing a row moves nothing.
    static let selectionRingWidth: CGFloat = 1.5
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
        // Pure white or black, not the theme's text color: that is a step dimmer, and the ring
        // would come out no stronger than the plain one.
        style.selectionEdge = Color(nsColor: (isDark ? NSColor.white : NSColor.black).withAlphaComponent(0.85))
        style.selectionLift = Color(nsColor: NSColor.white.withAlphaComponent(isDark ? 0.16 : 0.5))
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
            selectionEdge: Color(nsColor: ink.withAlphaComponent(isDark ? 0.6 : 0.55)),
            selectionLift: Color(nsColor: NSColor.white.withAlphaComponent(isDark ? 0.1 : 0.35)),
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
    /// Observed, so the notice in the strip appears when a check finds a newer release.
    private let updates = UpdateChecker.shared
    /// The footer's setting, passed in like `style`: `manager.settings` isn't observed, so a read
    /// in the body would go stale when the setting changes.
    let showsFooter: Bool
    /// Settings → Appearance → Session cards. Passed in rather than read from `manager.settings`
    /// in the body: the settings aren't observed, so when saving one rebuilt the sidebar with
    /// nothing else changed, SwiftUI kept the old cards until something it watches moved.
    let cardSize: CalmSettings.SessionCardSize
    /// Shrink to fit: `cardSize` is the largest the cards get, not the only size.
    let fitsCards: Bool
    /// ⌘N's agent, the footer's first row, and the others its ⌄ offers.
    let startAgents: StartAgents
    let onSelect: (Session.ID) -> Void
    let onClose: (Session.ID) -> Void
    let onNewSession: () -> Void
    let onNewProject: () -> Void
    let editing: SidebarEditing
    /// Observed: the footer's Files row reads Hide Files while the column is on screen.
    let files: FilesModel
    let actions: SidebarActions
    /// A project dragged by its header (SidebarView+Reorder). The window's, so self-tests reach it.
    let projectDrag: ProjectDragModel
    @State private var draftName = ""
    @FocusState private var nameFieldFocused: Bool
    @State private var hoveredSessionID: Session.ID?
    @State private var hoveringFooter = false
    /// What the footer's handle chose, until the saved setting catches up (or forever in a peek,
    /// which isn't rebuilt when the setting is saved).
    @State private var footerChoice: Bool?

    private var footerShown: Bool {
        footerChoice ?? showsFooter
    }

    @State private var fitting = SidebarCardFit()

    /// Ties a session's row across projects, so a row that changes project glides there.
    @Namespace private var rows

    /// The size the cards are drawn at, below `cardSize` while shrinking to fit.
    private var shownCardSize: CalmSettings.SessionCardSize {
        fitting.size(largest: cardSize, fitting: fitsCards)
    }

    private func refit() {
        fitting.refit(manager: manager, renaming: editing.renamingSessionID, largest: cardSize, fitting: fitsCards)
    }

    private var selectedSessionID: Session.ID? {
        manager.workspace.selectedLayout?.focusedSessionID
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Room for the window's traffic lights. The titlebar's safe area is ignored below, so
            // this is the only gap; counting both left a hole above the search field.
            // As tall as the window's title strip, so the search field and the terminal start level.
            Color.clear.frame(height: CalmWindow.titleStripHeight)
                .overlay(alignment: .trailing) {
                    // The update notice (and, in the dev build, its tag after it) at the strip's
                    // trailing edge; the tag brings its own inset.
                    HStack(spacing: 12.scaled) {
                        if let offer = updates.offer {
                            UpdateNotice(release: offer, style: style)
                        }
                        if BuildVariant.isDev {
                            DevTag(isDark: style.isDark)
                        }
                    }
                    .padding(.trailing, BuildVariant.isDev ? 0 : 20.scaled)
                }
            searchField
                .padding(.horizontal, 14.scaled)
                .padding(.bottom, 18.scaled)
                .overlay(alignment: .bottom) {
                    // In the gap under the field, so nothing moves when it goes.
                    if !manager.confirming.isEmpty {
                        restoringLine
                            .transition(.opacity)
                    }
                }
                .animation(Motion.isReduced ? nil : .easeInOut(duration: 0.45), value: manager.confirming.isEmpty)

            ScrollView {
                // Not lazy: a row moving between projects needs both ends laid out to glide.
                VStack(alignment: .leading, spacing: Self.groupSpacing) {
                    // Scratch sessions on top, then projects the user made, then directory groups.
                    ForEach(manager.workspace.orderedProjects) { project in
                        projectSection(project)
                            .modifier(ReorderableSection(id: project.id, model: projectDrag, style: style))
                    }
                }
                .coordinateSpace(.named(Self.listSpace))
                .padding(.horizontal, 12.scaled)
                // No room of its own at the foot: the footer's handle strip, or the strip along the
                // bottom edge when it's hidden, is the gap.
                // A new card size eases every card to its height.
                .animation(Motion.isReduced ? nil : .easeInOut(duration: 0.25), value: shownCardSize)
            }
            .scrollIndicators(.never)
            .coordinateSpace(.named(Self.viewportSpace))
            .scrollPosition(Bindable(projectDrag).scrollPosition)
            .onScrollGeometryChange(for: SidebarCardFit.Geometry.self, of: SidebarCardFit.Geometry.init) { _, geometry in
                fitting.measured(geometry, manager: manager, renaming: editing.renamingSessionID, largest: cardSize, fitting: fitsCards)
            }
            .onScrollGeometryChange(for: ProjectDragModel.Scroll.self) { geometry in
                ProjectDragModel.Scroll(
                    offset: geometry.contentOffset.y, visible: geometry.containerSize.height, content: geometry.contentSize.height,
                )
            } action: { _, scroll in
                projectDrag.scrolled(scroll)
            }
            .onChange(of: cardSize) { refit() }
            .onChange(of: fitsCards) { refit() }

            if footerShown {
                footer
            } else {
                hiddenFooter
            }
        }
        .animation(Motion.isReduced ? nil : .easeInOut(duration: 0.25), value: footerShown)
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
        .onDrop(of: [Self.sessionType], isTargeted: nil, perform: dropSession)
        .environment(\.colorScheme, style.isDark ? .dark : .light)
    }

    // MARK: Sections

    private func projectSection(_ project: Project) -> some View {
        let sessions = manager.workspace.sessions(in: project.id)
        let summary = GroupSummary(sessions.map(\.state))
        return VStack(alignment: .leading, spacing: 6.scaled) {
            SidebarGroupHeader(
                project: project, summary: summary, isHome: editing.homeProjectID == project.id, style: style,
                agent: startAgents.chosen, actions: actions,
                toggleCollapsed: { manager.toggleCollapsed(project.id) },
                shuffleMark: { manager.shuffleMark(project.id) },
                drag: headerDrag(for: project),
            )

            if !project.isCollapsed {
                ForEach(sessions) { session in
                    sessionView(session)
                        .onHover { hoveredSessionID = $0 ? session.id : (hoveredSessionID == session.id ? nil : hoveredSessionID) }
                        .onTapGesture { onSelect(session.id) }
                        .dragSession(session.id, enabled: editing.renamingSessionID != session.id)
                        .onRightClick { point in actions.showMenu(session.id, point) }
                        .matchedGeometryEffect(id: session.id, in: rows)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
        }
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
                size: shownCardSize, isHovered: hoveredSessionID == session.id,
                isConfirming: manager.confirming.contains(session.id),
                inView: manager.workspace.sessionsInView.contains(session.id),
                restart: manager.restarts[session.id],
                live: manager.liveLine(for: session.id),
            )
        } else {
            SessionRow(
                session: session, isSelected: session.id == selectedSessionID, style: style,
                isHovered: hoveredSessionID == session.id,
                inView: manager.workspace.sessionsInView.contains(session.id),
            )
        }
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

    /// Shown only while saved rows are checked against their agents and that takes a moment
    /// (UIUX.md → Restoring). Quiet and still; the cards' own placeholders breathe.
    private var restoringLine: some View {
        Text("Restoring sessions…")
            .calmFont(size: 12)
            .foregroundStyle(style.tertiary)
            .padding(.leading, 26.scaled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, 1)
            .accessibilityLabel("Restoring sessions")
    }

    /// The three ways to start something and the files column, one row each with its shortcut, so
    /// the corner reads at a glance and every target is a full row. The Files row is how a new
    /// user learns the column (and ⌘\) exists.
    private var footer: some View {
        VStack(spacing: 0) {
            // Above the line, so the handle never covers a row. Empty until the pointer is over the
            // footer, so nothing moves when it shows.
            footerHandle(symbol: "chevron.down", help: "Hide shortcuts", shows: false)
            Rectangle().fill(style.tertiary.opacity(0.14)).frame(height: 1)
            VStack(spacing: 2.scaled) {
                if let agent = startAgents.chosen {
                    AgentFooterRow(agent: agent, agents: startAgents, style: style, actions: actions)
                }
                footerRow("New Session", symbol: "square.and.pencil", keys: ["⌘", "T"], action: onNewSession)
                footerRow("New Scratch Session", symbol: "square.dashed", keys: ["⌘", "⇧", "N"], action: actions.newScratchSession)
                footerRow("New Project…", symbol: "plus", keys: ["⌘", "O"], action: onNewProject)
                footerRow(
                    files.isShown ? "Hide Files" : "Show Files",
                    symbol: "folder",
                    keys: ["⌘", "\\"],
                    on: files.isShown,
                    action: actions.toggleFiles,
                )
            }
            .padding(.horizontal, 12.scaled)
            .padding(.top, 10.scaled)
            .padding(.bottom, 14.scaled)
        }
        .onHover { hoveringFooter = $0 }
        .transition(.opacity)
    }

    /// With the footer hidden, the same corner brings it back: a strip along the bottom edge that
    /// shows the handle under the pointer. The shortcuts still work; the menus have the actions.
    private var hiddenFooter: some View {
        footerHandle(symbol: "chevron.up", help: "Show shortcuts", shows: true)
            .padding(.bottom, 6.scaled)
            .onHover { hoveringFooter = $0 }
            .transition(.opacity)
    }

    /// A strip the width of the sidebar, holding one quiet glyph that appears under the pointer.
    private func footerHandle(symbol: String, help: String, shows: Bool) -> some View {
        FooterHandle(style: style, symbol: symbol, help: help) {
            footerChoice = shows
            hoveringFooter = false
            actions.showFooter(shows)
        }
        .opacity(hoveringFooter ? 1 : 0)
        .allowsHitTesting(hoveringFooter)
        .animation(Motion.isReduced ? nil : .easeOut(duration: 0.15), value: hoveringFooter)
        .frame(maxWidth: .infinity)
        .frame(height: 16.scaled)
    }

    /// `on` is a row that stands for something showing now (the files column): its tile and words
    /// stay lit, as the selected card stays lifted.
    private func footerRow(_ title: String, symbol: String, keys: [String], on: Bool = false, action: @escaping () -> Void) -> some View {
        FooterButton(style: style, help: "\(title) (\(keys.joined()))", action: action) {
            HStack(spacing: 11.scaled) {
                Image(systemName: symbol)
                    .calmFont(size: 14)
                    .frame(width: 28.scaled, height: 28.scaled)
                    .background(RoundedRectangle(cornerRadius: 8.scaled, style: .continuous).fill(style.primary.opacity(on ? 0.11 : 0.055)))
                Text(title)
                    .calmFont(size: 14)
                    .foregroundStyle(on ? AnyShapeStyle(style.primary) : AnyShapeStyle(.foreground))
                Spacer(minLength: 4)
                KeyCaps(keys: keys, style: style)
            }
            .padding(.horizontal, 8.scaled)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// A group's kind at a glance (UIUX.md → Layout): a project the user made, a folder, scratch.
struct GroupMark: View {
    let project: Project
    let style: SidebarStyle
    /// Clicking a project's mark swaps it for another (an easter egg, FEATURES.md → F2).
    var shuffle: () -> Void = {}
    /// The mark's side at the standard interface size: 20 in the sidebar, larger in the title strip.
    /// The folder and scratch glyphs grow with it.
    var side: CGFloat = 20

    var body: some View {
        switch project.kind {
        case .project:
            let identicon = Identicon(name: project.name, seed: project.markSeed)
            IdenticonTile(identicon: identicon, style: style, side: side)
                // A new view per mark, so the old one crossfades into the new.
                .id(identicon)
                .transition(.opacity)
                // Wins over the header's button, so the click doesn't also collapse the group.
                .highPriorityGesture(TapGesture().onEnded(shuffle))
                .accessibilityLabel("Project")
        case .directory:
            Image(systemName: "folder")
                .calmFont(size: 12 * side / 20)
                .accessibilityLabel("Folder")
        case .scratch:
            Image(systemName: "square.dashed")
                .calmFont(size: 12 * side / 20)
                .accessibilityLabel("Scratch")
        }
    }
}

/// A folded group's line (UIUX.md → Session cards): the cards' own state marks, a mark per
/// session up to three, then one mark and the number in the state's color. Never cut: the
/// group's name gives way instead, since the marks are what a folded group is for.
struct GroupSummaryView: View {
    let summary: GroupSummary
    let style: SidebarStyle

    var body: some View {
        HStack(spacing: 9.scaled) {
            ForEach(summary.runs, id: \.state) { run in
                HStack(spacing: 3.scaled) {
                    ForEach(0 ..< run.marks, id: \.self) { _ in
                        StateMark(state: run.state, style: style, compact: true)
                    }
                    if run.showsCount {
                        Text("\(run.count)")
                            .calmFont(size: 12, weight: .medium)
                            .monospacedDigit()
                            .foregroundStyle(color(run.state))
                            .padding(.leading, 2.scaled)
                    }
                }
                .transition(.opacity)
            }
        }
        .fixedSize()
        .layoutPriority(1)
        // A card's state change crossfades in 0.25 s; the line follows it the same way.
        .animation(.easeInOut(duration: 0.25), value: summary)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(summary.words)
    }

    private func color(_ state: SessionState) -> Color {
        switch state {
        case .needsYou: style.attention
        case .failed: style.failure
        case .done: style.done
        case .working: style.working
        case .idle: style.tertiary
        }
    }
}

extension GroupSummary {
    /// "3 working, 2 idle": the line in words, for VoiceOver and the header's tooltip.
    var words: String {
        guard !tally.isEmpty else { return "No sessions" }
        return tally.map { "\($0.count) \($0.state.label.lowercased())" }.joined(separator: ", ")
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
        let (pixels, tile) = Self.colors(of: identicon, style: style)
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

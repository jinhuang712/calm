import AppKit
import CalmAgents
import CalmModel
import CalmSearch
import SwiftUI

/// The welcome page (UIUX.md → Welcome page): Calm's mark, then either search with a list of recent
/// sessions and one of projects, or, with nothing to list, the three ways to start.
struct WelcomeView: View {
    struct Actions {
        let newSession: () -> Void
        let newScratchSession: () -> Void
        let newProject: () -> Void
        let newSessionIn: (Project) -> Void
        let open: (SearchPanelModel.Item) -> Void
    }

    /// Where the page stands: over the whole window (no session open), or in the main area beside
    /// the sidebar (sessions open, none chosen), where the sidebar's footer already has the three
    /// ways to start.
    enum Placement {
        case window
        case mainArea
    }

    @Bindable var model: WelcomeModel
    let style: SidebarStyle
    /// The terminal's background: the page stands where the sessions would.
    let background: Color
    let actions: Actions
    var placement = Placement.window

    @FocusState private var fieldFocused: Bool
    @State private var caret: TextSelection?

    /// The tallest a list gets before it scrolls: six rows.
    private static let listHeight: CGFloat = 334

    var body: some View {
        GeometryReader { proxy in
            let stacked = proxy.size.width < 760.scaled
            ZStack(alignment: .bottom) {
                switch (model.content, placement) {
                case (.actions, .window):
                    ViewThatFits(in: .vertical) {
                        actionsPage
                        ScrollView { actionsPage.padding(.vertical, 24.scaled) }
                    }
                case (.actions, .mainArea):
                    // Nothing to list yet, and the ways to start are in the sidebar: the mark alone.
                    WelcomeMark(clock: model.clock, isDark: style.isDark, side: 60)
                        .padding(.bottom, 60.scaled)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                case (.lists, _):
                    listsPage(width: proxy.size.width, stacked: stacked)
                    if placement == .window {
                        HintLine(style: style, actions: actions)
                            .padding(.bottom, 34.scaled)
                    }
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .onChange(of: stacked, initial: true) { _, value in model.stacked = value }
        }
        // Under the title bar too, so only the traffic lights show above it.
        .background(background.ignoresSafeArea())
        .environment(\.colorScheme, style.isDark ? .dark : .light)
        .onAppear { fieldFocused = true }
        .onChange(of: model.focusRequests) { fieldFocused = true }
        .onChange(of: model.walk, initial: true) { model.sync() }
        .onKeyPress(.downArrow) { move(1) }
        .onKeyPress(.upArrow) { move(-1) }
        .onKeyPress(.rightArrow) { cross(to: .projects) }
        .onKeyPress(.leftArrow) { cross(to: .sessions) }
        .onKeyPress(.escape) { clearQuery() }
    }

    // MARK: Keys

    private func move(_ delta: Int) -> KeyPress.Result {
        guard model.showsSearch else { return .ignored }
        model.step(delta)
        return .handled
    }

    /// ← and → change column. Inside the field they still move the caret, until it is at the text's
    /// edge or the user has started moving through the rows.
    private func cross(to column: WelcomeModel.Column) -> KeyPress.Result {
        guard model.showsBothColumns, !model.stacked else { return .ignored }
        let from: WelcomeModel.Column = column == .projects ? .sessions : .projects
        guard model.selected == nil || model.selected?.column == from else { return .ignored }
        if fieldFocused, !model.navigated, !caretAtEdge(toward: column) {
            return .ignored
        }
        model.switchColumn(to: column)
        return .handled
    }

    private func caretAtEdge(toward column: WelcomeModel.Column) -> Bool {
        if model.query.isEmpty {
            return true
        }
        guard case let .selection(range)? = caret?.indices, range.isEmpty else { return false }
        return column == .projects ? range.upperBound == model.query.endIndex : range.lowerBound == model.query.startIndex
    }

    private func clearQuery() -> KeyPress.Result {
        guard !model.query.isEmpty else { return .ignored }
        model.query = ""
        return .handled
    }

    // MARK: The three ways to start

    private var actionsPage: some View {
        VStack(spacing: 34.scaled) {
            VStack(spacing: 24.scaled) {
                WelcomeMark(clock: model.clock, isDark: style.isDark, side: 76)
                if model.firstUse {
                    VStack(spacing: 10.scaled) {
                        Text("Welcome to Calm")
                            .calmFont(size: 34, weight: .medium)
                            .tracking(-0.3)
                            .foregroundStyle(style.primary)
                        Text("A terminal that keeps you calm while your agents work.")
                            .calmFont(size: 15)
                            .foregroundStyle(style.secondary)
                            .multilineTextAlignment(.center)
                    }
                }
            }
            VStack(spacing: 2.scaled) {
                WelcomeActionRow(
                    title: "Start a session", symbol: "square.and.pencil", keys: "⌘T", isMain: true,
                    style: style, action: actions.newSession,
                )
                WelcomeActionRow(
                    title: "Try a scratch session", symbol: "square.dashed", keys: "⌘⇧N", isMain: false,
                    style: style, action: actions.newScratchSession,
                )
                WelcomeActionRow(
                    title: "Open a project", symbol: "plus", keys: "⌘O", isMain: false,
                    style: style, action: actions.newProject,
                )
            }
        }
        // As tall as the title bar, so the block sits centered in the window, not under it.
        .padding(.bottom, 60.scaled)
        .padding(.horizontal, 24.scaled)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Search and lists

    private func listsPage(width: CGFloat, stacked: Bool) -> some View {
        let wide = model.showsBothColumns && !stacked
        let contentWidth = min((wide ? 880 : 520).scaled, width - 48.scaled)
        // Beside the sidebar the mark is a size down: the sidebar already says whose window it is.
        let small = stacked || placement == .mainArea
        return VStack(spacing: 0) {
            WelcomeMark(clock: model.clock, isDark: style.isDark, side: small ? 48 : 60)
            searchField(stacked: stacked)
                .padding(.top, (small ? 26 : 34).scaled)
            columns(stacked: stacked)
                .padding(.top, (stacked ? 22 : 30).scaled)
        }
        .frame(width: contentWidth)
        // Over the window: the title strip's height and a little more, so the mark stands level with
        // the search panel's top edge, and room below for the hint line. The main area already
        // starts under the strip, and has no hint line.
        .padding(.top, placement == .window ? CalmWindow.titleStripHeight + 8.scaled : 64.scaled)
        .padding(.bottom, (placement == .window ? 84 : 32).scaled)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var placeholder: String {
        switch (model.showsSessions, model.showsProjects) {
        case (true, true): "Search sessions and projects"
        case (false, true): "Search projects"
        default: "Search sessions"
        }
    }

    private func searchField(stacked: Bool) -> some View {
        let shape = RoundedRectangle(cornerRadius: (stacked ? 13 : 14).scaled, style: .continuous)
        return HStack(spacing: 12.scaled) {
            Image(systemName: "magnifyingglass")
                .calmFont(size: 15)
                .foregroundStyle(style.tertiary)
            TextField("", text: $model.query, selection: $caret, prompt: Text(placeholder).foregroundStyle(style.secondary))
                .textFieldStyle(.plain)
                .calmFont(size: stacked ? 14 : 15)
                .focused($fieldFocused)
                .onSubmit { model.activate(actions) }
                .accessibilityLabel(placeholder)
            if model.query.isEmpty {
                KeyCaps(keys: ["⌘", "K"], style: style)
            } else {
                Button {
                    model.query = ""
                } label: {
                    Image(systemName: "xmark")
                        .calmFont(size: 9, weight: .semibold)
                        .foregroundStyle(style.secondary)
                        .frame(width: 24.scaled, height: 24.scaled)
                        .background(Circle().fill(style.primary.opacity(0.08)))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.leading, 16.scaled)
        .padding(.trailing, 12.scaled)
        .frame(height: (stacked ? 42 : 46).scaled)
        .background(shape.fill(style.primary.opacity(0.05)))
        .overlay(shape.strokeBorder(fieldFocused ? style.accent.opacity(0.45) : style.primary.opacity(0.07)))
        .overlay(shape.inset(by: -2.scaled).strokeBorder(style.accent.opacity(fieldFocused ? 0.14 : 0), lineWidth: 3.scaled))
    }

    @ViewBuilder
    private func columns(stacked: Bool) -> some View {
        if stacked {
            ResultScroller(selected: model.selected) {
                VStack(alignment: .leading, spacing: 22.scaled) {
                    if model.showsSessions {
                        section(.sessions, scrolls: false)
                    }
                    if model.showsProjects {
                        section(.projects, scrolls: false)
                    }
                }
            }
        } else {
            HStack(alignment: .top, spacing: 40.scaled) {
                if model.showsSessions {
                    section(.sessions, scrolls: true)
                }
                if model.showsProjects {
                    section(.projects, scrolls: true)
                }
            }
        }
    }

    private func section(_ column: WelcomeModel.Column, scrolls: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8.scaled) {
            header(column)
            if scrolls {
                ResultScroller(selected: model.selected) { rows(column) }
                    .frame(maxHeight: Self.listHeight.scaled)
            } else {
                rows(column)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func header(_ column: WelcomeModel.Column) -> some View {
        let searching = !model.terms.isEmpty
        let title = column == .projects ? "Projects" : searching ? "Sessions" : "Recent sessions"
        let count = column == .projects ? model.shownProjects.count : model.sessions.count
        return HStack {
            Text(title.uppercased())
            Spacer(minLength: 4)
            if searching {
                Text("\(count)").monospacedDigit()
            }
        }
        .calmFont(size: 12, weight: .semibold)
        .tracking(0.7)
        .foregroundStyle(style.tertiary)
        .padding(.horizontal, 12.scaled)
        .frame(height: 18.scaled)
        .accessibilityAddTraits(.isHeader)
    }

    @ViewBuilder
    private func rows(_ column: WelcomeModel.Column) -> some View {
        let searching = !model.terms.isEmpty
        LazyVStack(spacing: 2.scaled) {
            switch column {
            case .sessions:
                ForEach(model.sessions) { item in
                    WelcomeSessionRow(item: item, searching: searching, isSelected: model.selected == .session(item.id), style: style) {
                        model.selected = .session(item.id)
                        actions.open(item)
                    }
                    .id(WelcomeModel.Target.session(item.id))
                }
                if searching, model.sessions.isEmpty {
                    noMatch("sessions")
                }
            case .projects:
                ForEach(model.shownProjects) { project in
                    WelcomeProjectRow(
                        project: project,
                        terms: model.terms,
                        isSelected: model.selected == .project(project.id),
                        style: style,
                    ) {
                        model.selected = .project(project.id)
                        actions.newSessionIn(project)
                    }
                    .id(WelcomeModel.Target.project(project.id))
                }
                if searching, model.shownProjects.isEmpty {
                    noMatch("projects")
                }
            }
        }
    }

    private func noMatch(_ what: String) -> some View {
        Text("No \(what) match")
            .calmFont(size: 12.5)
            .foregroundStyle(style.secondary)
            .padding(.horizontal, 12.scaled)
            .frame(maxWidth: .infinity, minHeight: 54.scaled, alignment: .leading)
    }
}

// MARK: - Lists

/// A scrolling list that scrolls to the selected row and fades out at the bottom while there is more.
private struct ResultScroller<Content: View>: View {
    let selected: WelcomeModel.Target?
    @ViewBuilder let content: Content
    @State private var moreBelow = false

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                content
            }
            .scrollIndicators(.never)
            .onScrollGeometryChange(for: Bool.self) { geometry in
                geometry.contentSize.height - geometry.contentOffset.y - geometry.containerSize.height > 2
            } action: { _, more in
                moreBelow = more
            }
            .mask {
                LinearGradient(
                    stops: [
                        .init(color: .black, location: 0),
                        .init(color: .black, location: moreBelow ? 0.72 : 1),
                        .init(color: moreBelow ? .clear : .black, location: 1),
                    ],
                    startPoint: .top, endPoint: .bottom,
                )
            }
            .animation(Motion.isReduced ? nil : .easeOut(duration: 0.2), value: moreBelow)
            .onChange(of: selected) {
                if let selected {
                    proxy.scrollTo(selected)
                }
            }
        }
    }
}

/// The fill behind a row: the selected one, and the one under the pointer.
private func rowFill(_ style: SidebarStyle, selected: Bool, hovering: Bool) -> Color {
    selected ? style.selection : hovering ? style.primary.opacity(0.04) : .clear
}

/// `text` with the words the user typed marked: bold, in the primary color.
private func marked(_ text: String, terms: [String], style: SidebarStyle, underlined: Bool = false) -> AttributedString {
    var output = AttributedString(text)
    for range in ProjectSearch.ranges(of: terms, in: text) {
        guard let lower = AttributedString.Index(range.lowerBound, within: output),
              let upper = AttributedString.Index(range.upperBound, within: output) else { continue }
        output[lower ..< upper].inlinePresentationIntent = .stronglyEmphasized
        output[lower ..< upper].foregroundColor = style.primary
        if underlined {
            output[lower ..< upper].underlineStyle = .single
            output[lower ..< upper].underlineColor = NSColor(style.accent.opacity(0.7))
        }
    }
    return output
}

/// A past session: the agent's mark, its title, and where and when. While searching, the line under
/// the title is the matching text, as in ⌘K.
private struct WelcomeSessionRow: View {
    let item: SearchPanelModel.Item
    let searching: Bool
    let isSelected: Bool
    let style: SidebarStyle
    let action: () -> Void
    @State private var hovering = false

    private var result: SearchResult {
        item.result
    }

    private var detail: String {
        let project = result.directory.map { WorkspacePath.displayName(for: $0) } ?? result.agent.displayName
        return "\(project) · \(SearchPanelView.when(result.lastActive, now: Date()))"
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12.scaled) {
                AgentLogo(agent: result.agent, size: 28, style: style)
                VStack(alignment: .leading, spacing: 3.scaled) {
                    if searching {
                        HStack(alignment: .firstTextBaseline, spacing: 10.scaled) {
                            title
                            Spacer(minLength: 8)
                            Text(detail)
                                .calmFont(size: 11.5)
                                .foregroundStyle(style.secondary)
                                .lineLimit(1)
                                .layoutPriority(1)
                        }
                        Text(SearchPanelView.highlighted(result.snippet))
                            .calmFont(size: 12)
                            .foregroundStyle(style.secondary)
                            .lineLimit(1)
                    } else {
                        title
                        Text(detail)
                            .calmFont(size: 12)
                            .foregroundStyle(style.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
                KeyCaps(keys: ["↵"], style: style).opacity(isSelected ? 1 : 0)
            }
            .padding(.horizontal, 12.scaled)
            .frame(maxWidth: .infinity, minHeight: 54.scaled, maxHeight: 54.scaled, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 10.scaled, style: .continuous).fill(rowFill(
                style,
                selected: isSelected,
                hovering: hovering,
            )))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(item.openSession == nil ? "Resume in a new session" : "Go to this session")
        .accessibilityElement(children: .combine)
    }

    private var title: some View {
        Text(result.title)
            .calmFont(size: 13.5, weight: .medium)
            .foregroundStyle(style.primary)
            .lineLimit(1)
    }
}

/// A project the user made: its pixel mark, its name and its folder.
private struct WelcomeProjectRow: View {
    let project: Project
    let terms: [String]
    let isSelected: Bool
    let style: SidebarStyle
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12.scaled) {
                IdenticonTile(identicon: Identicon(name: project.name, seed: project.markSeed), style: style, side: 30)
                VStack(alignment: .leading, spacing: 3.scaled) {
                    Text(marked(project.name, terms: terms, style: style, underlined: true))
                        .calmFont(size: 13.5, weight: .medium)
                        .foregroundStyle(style.primary)
                        .lineLimit(1)
                    Text(marked(ProjectSearch.shownPath(of: project), terms: terms, style: style))
                        .calmFont(size: 12)
                        .foregroundStyle(style.secondary)
                        .lineLimit(1)
                        .truncationMode(.head)
                }
                Spacer(minLength: 0)
                KeyCaps(keys: ["↵"], style: style).opacity(isSelected ? 1 : 0)
            }
            .padding(.horizontal, 12.scaled)
            .frame(maxWidth: .infinity, minHeight: 54.scaled, maxHeight: 54.scaled, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 10.scaled, style: .continuous).fill(rowFill(
                style,
                selected: isSelected,
                hovering: hovering,
            )))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(project.path)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - The ways to start

/// The bottom line of the page: the three ways to start, shortcut first. Each is a button with a
/// faint fill of its own, so it reads as something to press without the weight of a toolbar.
private struct HintLine: View {
    let style: SidebarStyle
    let actions: WelcomeView.Actions

    var body: some View {
        HStack(spacing: 8.scaled) {
            HintButton(keys: "⌘T", title: "New session", help: "New Session (⌘T)", style: style, action: actions.newSession)
            HintButton(keys: "⌘⇧N", title: "Scratch", help: "New Scratch Session (⌘⇧N)", style: style, action: actions.newScratchSession)
            HintButton(keys: "⌘O", title: "New project…", help: "New Project (⌘O)", style: style, action: actions.newProject)
        }
    }
}

private struct HintButton: View {
    let keys: String
    let title: String
    let help: String
    let style: SidebarStyle
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
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
            .padding(.horizontal, 16.scaled)
            .padding(.vertical, 9.scaled)
            .background(RoundedRectangle(cornerRadius: 9.scaled, style: .continuous).fill(style.primary.opacity(hovering ? 0.11 : 0.055)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.15), value: hovering)
        .help(help)
        .accessibilityLabel(title)
    }
}

/// One of the three ways to start on the first-run page, drawn like the list rows and the
/// sidebar's footer. The first is the selected row: the one to press.
private struct WelcomeActionRow: View {
    let title: String
    let symbol: String
    let keys: String
    let isMain: Bool
    let style: SidebarStyle
    let action: () -> Void
    @State private var hovering = false

    private var fill: Color {
        isMain ? (hovering ? style.primary.opacity(0.11) : style.selection) : (hovering ? style.primary.opacity(0.06) : .clear)
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12.scaled) {
                Image(systemName: symbol)
                    .calmFont(size: 14)
                    .foregroundStyle(style.secondary)
                    .frame(width: 30.scaled, height: 30.scaled)
                    .background(RoundedRectangle(cornerRadius: 9.scaled, style: .continuous).fill(style.primary.opacity(0.06)))
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
            .padding(.trailing, 16.scaled)
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

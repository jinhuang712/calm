import AppKit
import CalmModel
import SwiftUI

/// What the window shows with no session open (FEATURES.md → F2). It covers the whole window,
/// sidebar included, so it carries what the sidebar would: search over past sessions and over the
/// projects the user made, a list of each, and the three ways to start. On Calm's very first
/// launch there is nothing to list, so it welcomes instead. Calm never opens a session nobody
/// asked for.
@MainActor
final class WelcomePage {
    private weak var container: NSView?
    private var host: NSHostingView<WelcomeView>?
    private(set) var model: WelcomeModel?

    init(container: NSView) {
        self.container = container
    }

    var isShowing: Bool {
        host != nil
    }

    func show(firstUse: Bool, projects: [Project], style: SidebarStyle, background: NSColor, actions: WelcomeView.Actions) {
        // One model per showing: the search starts fresh, and refreshes the index, each time.
        let model = self.model ?? WelcomeModel(firstUse: firstUse)
        self.model = model
        model.projects = projects
        let view = WelcomeView(model: model, style: style, background: Color(nsColor: background), actions: actions)
        if let host {
            host.rootView = view
            return
        }
        guard let container else { return }
        let host = NSHostingView(rootView: view)
        host.frame = container.bounds
        host.autoresizingMask = [.width, .height]
        container.addSubview(host, positioned: .above, relativeTo: nil)
        self.host = host
        Motion.fadeIn(host, duration: 0.2)
        // So typing goes to the search field at once.
        host.window?.makeFirstResponder(host)
    }

    func hide() {
        guard let host else { return }
        self.host = nil
        model = nil
        Motion.fadeOutAndRemove(host, duration: 0.14)
    }

    /// ⌘K on this page: its own search field is right there, so it takes the focus. False when
    /// the page has none (the first launch, or nothing to search yet).
    func focusSearch() -> Bool {
        guard let host, let model, model.showsSearch else { return false }
        model.focusRequests += 1
        host.window?.makeFirstResponder(host)
        return true
    }
}

/// What the page is showing and which row the keys are on (UIUX.md → Welcome page).
@MainActor
@Observable
final class WelcomeModel {
    enum Column {
        case sessions
        case projects
    }

    /// A row, by what it stands for, so a selection survives the lists changing under it.
    enum Target: Hashable {
        case session(String)
        case project(Project.ID)
        /// The last row of the projects: New project…, what ⌘O does.
        case newProject

        var column: Column {
            switch self {
            case .session: .sessions
            case .project, .newProject: .projects
            }
        }
    }

    let firstUse: Bool
    /// The search over past sessions; the page adds the projects.
    let search: SearchPanelModel
    let clock = WelcomeMarkClock()
    var projects: [Project] = []
    var selected: Target?
    /// The user has started moving through the rows with the arrow keys: ← and → then change
    /// column even inside the field, until they type again.
    var navigated = false
    /// Set by the page: the lists stack in a window too narrow for two columns.
    var stacked = false
    /// Bumped for ⌘K, which puts the caret back in the field.
    var focusRequests = 0

    init(firstUse: Bool) {
        self.firstUse = firstUse
        search = SearchPanelModel(currentProject: nil)
    }

    var query: String {
        get { search.query }
        set {
            search.query = newValue
            navigated = false
        }
    }

    var terms: [String] {
        ProjectSearch.terms(in: query)
    }

    var content: WelcomeContent {
        .choose(firstUse: firstUse, hasSessions: search.hasHistory, hasProjects: !projects.isEmpty)
    }

    var showsSearch: Bool {
        if case .lists = content {
            true
        } else {
            false
        }
    }

    var showsSessions: Bool {
        if case .lists(sessions: true, projects: _) = content {
            true
        } else {
            false
        }
    }

    var showsProjects: Bool {
        if case .lists(sessions: _, projects: true) = content {
            true
        } else {
            false
        }
    }

    var showsBothColumns: Bool {
        showsSessions && showsProjects
    }

    /// The few most recent sessions when nothing is typed (fewer in a small window, so the
    /// projects stay in view), leaving out the ones open in the sidebar, which already shows them;
    /// everything that matches when something is typed, open or not, as in ⌘K.
    var sessions: [SearchPanelModel.Item] {
        guard terms.isEmpty else { return search.items }
        // Read here, not taken from the items, so a session closed while the page is up comes back.
        let open = SessionManager.shared.workspace.sessions
        let closed = search.items.filter { item in
            !open.contains { $0.runs(transcriptPath: item.result.transcriptPath, agentSessionID: item.result.agentSessionID) }
        }
        return Array(closed.prefix(stacked ? 3 : 6))
    }

    /// Nothing typed, and every recent session is open in the sidebar (only beside it: with the
    /// welcome page up none is open).
    var recentAllOpen: Bool {
        terms.isEmpty && search.hasHistory == true && sessions.isEmpty
    }

    var shownProjects: [Project] {
        terms.isEmpty ? projects : projects.filter { ProjectSearch.matches($0, terms: terms) }
    }

    // MARK: Moving through the rows

    func targets(in column: Column) -> [Target] {
        switch column {
        case .sessions: showsSessions ? sessions.map { .session($0.id) } : []
        // New project… stays at the end while searching too: a project that isn't there is one to make.
        case .projects: showsProjects ? shownProjects.map { .project($0.id) } + [.newProject] : []
        }
    }

    /// Every row, in the order the keys walk them.
    var walk: [Target] {
        targets(in: .sessions) + targets(in: .projects)
    }

    func selectFirst() {
        selected = walk.first
    }

    /// After the rows changed: while the user hasn't moved, the selection is the top hit;
    /// afterwards it stays on its row for as long as that is there.
    func sync() {
        if !navigated || selected.map({ !walk.contains($0) }) ?? true {
            selectFirst()
        }
    }

    func step(_ delta: Int) {
        navigated = true
        guard let current = selected else {
            selectFirst()
            return
        }
        // Two columns are walked one at a time; stacked ones as one list.
        let rows = stacked ? walk : targets(in: current.column)
        guard let index = rows.firstIndex(of: current) else {
            selectFirst()
            return
        }
        selected = rows[max(0, min(rows.count - 1, index + delta))]
    }

    func switchColumn(to column: Column) {
        navigated = true
        let rows = targets(in: column)
        guard !rows.isEmpty else { return }
        let index = selected.flatMap { targets(in: $0.column).firstIndex(of: $0) } ?? 0
        selected = rows[min(index, rows.count - 1)]
    }

    func activate(_ actions: WelcomeView.Actions) {
        switch selected {
        case let .session(id)?:
            if let item = sessions.first(where: { $0.id == id }) {
                actions.open(item)
            }
        case let .project(id)?:
            if let project = projects.first(where: { $0.id == id }) {
                actions.newSessionIn(project)
            }
        case .newProject?:
            actions.newProject()
        case nil:
            break
        }
    }
}

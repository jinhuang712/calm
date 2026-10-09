import AppKit
import CalmModel
import CalmSearch
import SwiftUI

/// A project's home in the main area (UIUX.md → Project home): what opening a project shows, and
/// a click on its name in the sidebar. The project, the ways to start a session in it, and the
/// sessions that ran there before. It starts nothing itself: Calm never opens a session nobody
/// asked for, and nothing on it is chosen until the user chooses.
@MainActor
final class ProjectHomePage {
    private weak var mainArea: NSView?
    private var host: NSHostingView<ProjectHomeView>?
    private(set) var model: ProjectHomeModel?

    init(mainArea: NSView) {
        self.mainArea = mainArea
    }

    var isShowing: Bool {
        host != nil
    }

    func show(project: Project, style: SidebarStyle, background: NSColor, actions: ProjectHomeView.Actions) {
        // A new model for another project: its list and branch are its own.
        let model = (self.model?.project.id == project.id ? self.model : nil) ?? ProjectHomeModel(project: project)
        if let previous = self.model, previous !== model {
            // The view sees the same model property change: a count carried on still moves when
            // `focus()` bumps it, so the keys come to the page for the new project too.
            model.focusRequests = previous.focusRequests
        }
        model.project = project
        self.model = model
        let view = ProjectHomeView(model: model, style: style, background: Color(nsColor: background), actions: actions)
        if let host {
            host.rootView = view
            return
        }
        guard let mainArea else { return }
        let host = NSHostingView(rootView: view)
        host.frame = mainArea.bounds
        host.autoresizingMask = [.width, .height]
        mainArea.addSubview(host, positioned: .above, relativeTo: nil)
        self.host = host
        Motion.fadeIn(host, duration: 0.2)
        // No terminal is on screen: the arrow keys and ↵ go to the page.
        host.window?.makeFirstResponder(host)
    }

    func hide() {
        guard let host else { return }
        self.host = nil
        model = nil
        Motion.fadeOutAndRemove(host, duration: 0.14)
    }

    /// The keys come back to the page, as after Settings or the search panel closes over it.
    func focus() {
        guard let host, let model else { return }
        host.window?.makeFirstResponder(host)
        model.focusRequests += 1
    }
}

/// The project a home shows, the sessions that ran there, and which one the arrow keys are on.
@MainActor
@Observable
final class ProjectHomeModel {
    var project: Project
    /// Every past session in its folder the index gave, newest first.
    private var results: [SearchResult] = []
    /// The branch checked out in its folder, nil outside a git repository.
    private(set) var branch: String?
    /// The row the arrow keys are on; none until they're used, so nothing looks chosen for the user.
    var selected: Int?
    var focusRequests = 0

    /// The most rows the list shows: what was done lately, not the project's whole history (⌘K
    /// searches all of it).
    static let rowLimit = 6

    init(project: Project) {
        self.project = project
        load()
    }

    private func load() {
        let path = project.path
        // More than it shows, since the ones open in the sidebar are left out.
        let limit = Self.rowLimit * 3
        Task { [weak self] in
            let (results, branch) = await Task.detached(priority: .userInitiated) {
                let results = SearchService.recent(inside: path, limit: limit)
                let branch = GitCommand.run(["branch", "--show-current"], in: path)?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                return (results, branch.flatMap { $0.isEmpty ? nil : $0 })
            }.value
            guard let self else { return }
            self.results = results
            self.branch = branch
        }
    }

    /// Its past sessions, newest first, leaving out the ones open in the sidebar beside it. Read
    /// here, not when loaded, so a session closed while the home is up comes back to the list.
    var sessions: [SearchPanelModel.Item] {
        let open = SessionManager.shared.workspace.sessions
        return Array(results.lazy
            .filter { result in
                !open.contains { $0.runs(transcriptPath: result.transcriptPath, agentSessionID: result.agentSessionID) }
            }
            .map { SearchPanelModel.Item(result: $0, openSession: nil) }
            .prefix(Self.rowLimit))
    }

    func step(_ delta: Int) {
        selected = Self.step(from: selected, by: delta, count: sessions.count)
    }

    /// The first arrow press lands on the first row, whichever way it points; after that the
    /// arrows move one row, stopping at the ends.
    nonisolated static func step(from current: Int?, by delta: Int, count: Int) -> Int? {
        guard count > 0 else { return nil }
        guard let current else { return 0 }
        return max(0, min(count - 1, current + delta))
    }

    var selectedItem: SearchPanelModel.Item? {
        selected.flatMap { sessions.indices.contains($0) ? sessions[$0] : nil }
    }
}

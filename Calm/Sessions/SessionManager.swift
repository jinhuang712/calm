import AppKit
import CalmModel
import GhosttyKit
import Observation
import SwiftUI

/// Owns the workspace (projects, sessions, layouts), keeps it saved, and creates the
/// terminal pane for each session on demand.
@MainActor
@Observable
final class SessionManager {
    static let shared: SessionManager = {
        // Self-tests and development can point at a throwaway state file.
        if let path = ProcessInfo.processInfo.environment["CALM_STATE_FILE"], !path.isEmpty {
            return SessionManager(store: WorkspaceStore(fileURL: URL(filePath: path)))
        }
        return SessionManager()
    }()

    private(set) var workspace: Workspace
    @ObservationIgnored private let store: WorkspaceStore
    @ObservationIgnored private(set) var panes: [Session.ID: TerminalSurfaceView] = [:]
    @ObservationIgnored private var saveTask: Task<Void, Never>?

    /// Turned off for the rest of the run if persistent shells fail to start.
    @ObservationIgnored var persistenceEnabled = true

    /// Sessions from most to least recently focused, for the session switcher. Not saved.
    @ObservationIgnored private var recentSessionIDs: [Session.ID] = []

    /// Calm's own settings (`~/.config/calm/config.toml`); re-read with Reload Configuration.
    @ObservationIgnored var settings = CalmSettings.load()

    /// Whether sessions move between projects when their folder changes (config: `auto-grouping`).
    var autoGrouping: Bool {
        settings.autoGrouping
    }

    init(store: WorkspaceStore = .standard) {
        self.store = store
        workspace = store.load()
    }

    // MARK: Lifecycle

    /// Prepares the saved workspace at launch; starts one session in the home folder if there is none.
    func restore() {
        removeOrphanedShells()
        if workspace.sessions.isEmpty {
            newSession(in: FileManager.default.homeDirectoryForCurrentUser.path)
        }
        // Layouts may reference sessions whose data went missing; drop those leaves.
        for layout in workspace.layouts {
            let valid = layout.tree.leaves.filter { workspace.session($0) != nil }
            if valid.count != layout.tree.leaves.count {
                var tree: SplitTree<Session.ID>? = layout.tree
                for id in layout.tree.leaves where !valid.contains(id) {
                    tree = tree?.removing(id)
                }
                if let tree {
                    workspace.updateTree(layout.id, tree)
                }
            }
        }
        rememberFocus()
        scheduleSave()
    }

    /// Ends Calm's own persistent shells that no saved session refers to (e.g. after a crash).
    /// Only Calm's zmx directory is touched, never other apps' sessions.
    private func removeOrphanedShells() {
        guard PersistentShell.isAvailable else { return }
        let known = Set(workspace.sessions.map(\.persistentName))
        for name in PersistentShell.liveSessions() where name.hasPrefix("calm-") && !known.contains(name) {
            PersistentShell.kill(name: name)
        }
    }

    /// Detaches every pane (zmx keeps the shells) and writes the final state.
    func prepareForQuit() {
        saveNow()
        for pane in panes.values {
            pane.teardown()
        }
        panes.removeAll()
    }

    // MARK: Panes

    /// The pane for a session, creating it (and attaching its persistent shell) if needed.
    func pane(for sessionID: Session.ID, host: TerminalSurfaceHost?) -> TerminalSurfaceView? {
        if let existing = panes[sessionID] {
            existing.host = host
            return existing
        }
        guard let session = workspace.session(sessionID) else { return nil }
        var options = TerminalSurfaceOptions()
        options.workingDirectory = session.workingDirectory
        options.context = GHOSTTY_SURFACE_CONTEXT_SPLIT
        if persistenceEnabled, let command = PersistentShell.attachCommand(name: session.persistentName) {
            options.command = command
            let process = ProcessInfo.processInfo.environment
            options.environment = PersistentShell.environment.merging(ShellIntegration.environment(
                shell: process["SHELL"],
                mode: TerminalEngine.shared.config?.string("shell-integration"),
                resourcesDirectory: process["GHOSTTY_RESOURCES_DIR"],
                inherited: process,
            )) { current, _ in current }
        }
        let pane = TerminalSurfaceView(id: session.id, options: options)
        pane.host = host
        panes[session.id] = pane
        return pane
    }

    // MARK: Sessions

    @discardableResult
    func newSession(in directory: String) -> Session {
        let session = workspace.newSession(in: directory, gitRoot: GitRoot.find)
        rememberFocus()
        scheduleSave()
        return session
    }

    @discardableResult
    func splitSession(_ existing: Session.ID, direction: SplitTree<Session.ID>.Direction, in directory: String) -> Session? {
        let session = workspace.splitSession(existing, direction: direction, in: directory, gitRoot: GitRoot.find)
        rememberFocus()
        scheduleSave()
        return session
    }

    /// Ends a session: its pane, its persistent shell, and its place in the workspace.
    func closeSession(_ id: Session.ID) {
        if let session = workspace.session(id) {
            PersistentShell.kill(name: session.persistentName)
        }
        panes[id]?.teardown()
        panes[id] = nil
        workspace.removeSession(id)
        recentSessionIDs.removeAll { $0 == id }
        scheduleSave()
    }

    func select(_ id: Session.ID) {
        workspace.select(id)
        rememberFocus()
        scheduleSave()
    }

    func updateTree(_ layoutID: PaneLayout.ID, _ tree: SplitTree<Session.ID>) {
        workspace.updateTree(layoutID, tree)
        scheduleSave()
    }

    func setFocused(_ sessionID: Session.ID) {
        guard let layout = workspace.layout(containing: sessionID), layout.focusedSessionID != sessionID else { return }
        workspace.select(sessionID)
        rememberFocus()
        scheduleSave()
    }

    func titleChanged(_ id: Session.ID, _ title: String) {
        guard workspace.session(id)?.title != title else { return }
        workspace.setTitle(id, title)
        scheduleSave()
    }

    /// The shell reported a new folder; the session may move to another project.
    func workingDirectoryChanged(_ id: Session.ID, _ directory: String) {
        guard let session = workspace.session(id), session.workingDirectory != WorkspacePath.standardize(directory) else { return }
        if autoGrouping {
            Motion.animate {
                workspace.updateWorkingDirectory(id, to: directory, gitRoot: GitRoot.find)
            }
        } else {
            var copy = workspace
            copy.setPinned(id, true)
            copy.updateWorkingDirectory(id, to: directory, gitRoot: GitRoot.find)
            copy.setPinned(id, session.isPinned)
            workspace = copy
        }
        scheduleSave()
    }

    func togglePinned(_ id: Session.ID) {
        guard let session = workspace.session(id) else { return }
        workspace.setPinned(id, !session.isPinned)
        scheduleSave()
    }

    // MARK: Projects

    func addProject(path: String) {
        Motion.animate {
            _ = workspace.addProject(path: path, gitRoot: GitRoot.find)
        }
        scheduleSave()
    }

    func toggleCollapsed(_ projectID: Project.ID) {
        guard let project = workspace.project(projectID) else { return }
        Motion.animate(.easeInOut(duration: 0.18)) {
            workspace.setCollapsed(projectID, !project.isCollapsed)
        }
        scheduleSave()
    }

    /// Sessions from most to least recently focused; ones not visited this run follow in sidebar order.
    var recentSessions: [Session] {
        let visited = recentSessionIDs.compactMap { workspace.session($0) }
        let seen = Set(visited.map(\.id))
        return visited + orderedSessions.filter { !seen.contains($0.id) }
    }

    private func rememberFocus() {
        guard let id = workspace.selectedLayout?.focusedSessionID else { return }
        recentSessionIDs.removeAll { $0 == id }
        recentSessionIDs.insert(id, at: 0)
    }

    /// Sessions in sidebar order, for ⌘1…9.
    var orderedSessions: [Session] {
        workspace.projects.flatMap { workspace.sessions(in: $0.id) }
    }

    // MARK: Saving

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            self?.saveNow()
        }
    }

    func saveNow() {
        saveTask?.cancel()
        do {
            try store.save(workspace)
        } catch {
            FileHandle.standardError.write(Data("calm: could not save state: \(error)\n".utf8))
        }
    }
}

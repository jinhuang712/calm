import AppKit
import CalmAgents
import CalmModel
import Observation
import OSLog
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

    private static let log = Logger(subsystem: "com.jinhuang.calm", category: "sessions")

    private(set) var workspace: Workspace
    @ObservationIgnored private let store: WorkspaceStore
    @ObservationIgnored private(set) var panes: [Session.ID: TerminalSurfaceView] = [:]
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    /// The last few sessions closed, for ⌘⇧T. Kept in memory only.
    @ObservationIgnored private var recentlyClosed = ClosedSessions()

    /// Turned off for the rest of the run if persistent shells fail to start.
    @ObservationIgnored var persistenceEnabled = true

    /// Calm's own settings (`~/.config/calm/config.toml`); re-read with Reload Configuration.
    @ObservationIgnored var settings = CalmSettings.load()

    /// Whether sessions move between projects when their folder changes (config: `auto-grouping`).
    var autoGrouping: Bool {
        settings.autoGrouping
    }

    /// No workspace was ever saved: Calm's very first launch (the welcome page shows).
    @ObservationIgnored let isFirstUse: Bool

    init(store: WorkspaceStore = .standard) {
        self.store = store
        isFirstUse = !FileManager.default.fileExists(atPath: store.fileURL.path)
        workspace = store.load()
    }

    // MARK: Lifecycle

    /// Prepares the saved workspace at launch, so Calm starts where the user left off.
    func restore() {
        removeOrphanedShells()
        for session in workspace.sessions where session.agent != nil {
            // Saved by an earlier launch; the probe finds agents that are still running.
            workspace.endAgentRun(session.id)
        }
        // Sessions filed under older rules find their groups (FEATURES.md → F2).
        if autoGrouping {
            workspace.refileAll(gitRoot: GitRoot.find)
        }
        // With nothing saved, the welcome page shows instead of a session nobody asked for.
        // Self-tests start with a session unless they test the welcome page.
        #if DEBUG
            if workspace.sessions.isEmpty, ProcessInfo.processInfo.environment["CALM_START_WITH_SESSION"] == "1" {
                newSession(in: FileManager.default.homeDirectoryForCurrentUser.path)
            }
        #endif
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
        var options = TerminalSurfaceOptions.session
        options.workingDirectory = session.workingDirectory
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
        options.environment.merge(AgentIntegrations.environment(settings: settings)) { current, _ in current }
        let pane = TerminalSurfaceView(id: session.id, options: options)
        pane.host = host
        if let fontSize = workspace.fontSize {
            pane.setFontSize(fontSize)
        }
        panes[session.id] = pane
        return pane
    }

    /// One text size for every session (FEATURES.md → F1): a pane that changed size takes the
    /// others with it, and the size is saved for the next launch.
    func paneFontSizeDidChange(_ pane: TerminalSurfaceView) {
        // Panes the sync below resizes report back the size just saved, so this stops there.
        guard panes[pane.id] === pane, let points = pane.fontSize,
              workspace.noteFontSize(points, configured: TerminalEngine.shared.config?.float("font-size"))
        else { return }
        for other in panes.values where other !== pane {
            other.setFontSize(workspace.fontSize)
        }
        scheduleSave()
    }

    // MARK: Sessions

    @discardableResult
    func newSession(in directory: String, placement: Workspace.Placement = .directory) -> Session {
        let session = workspace.newSession(in: directory, placement: placement, gitRoot: GitRoot.find)
        scheduleSave()
        return session
    }

    @discardableResult
    func splitSession(
        _ existing: Session.ID, direction: SplitTree<Session.ID>.Direction, in directory: String,
        placement: Workspace.Placement = .directory,
    ) -> Session? {
        let session = workspace.splitSession(existing, direction: direction, in: directory, placement: placement, gitRoot: GitRoot.find)
        scheduleSave()
        return session
    }

    /// A scratch session (⌘⇧N) in a new hidden folder of its own, on top of the sidebar.
    func newScratchSession() -> Session? {
        do {
            let folder = try ScratchFolders.make()
            return newSession(in: folder.path, placement: .scratch)
        } catch {
            Self.log.error("could not make a scratch folder: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    /// Ends a session: its pane, its persistent shell, and its place in the workspace. A scratch
    /// session's folder goes too, once no other session is in it (the window asks first when it
    /// has files).
    func closeSession(_ id: Session.ID) {
        if let session = workspace.session(id) {
            if let closed = ClosedSession(session, in: workspace) {
                recentlyClosed.push(closed)
            }
            PersistentShell.kill(name: session.persistentName)
            if let folder = session.scratchFolder, !workspace.sessions.contains(where: { $0.id != id && $0.scratchFolder == folder }) {
                ScratchFolders.discard(folder)
            }
        }
        panes[id]?.teardown()
        panes[id] = nil
        workspace.removeSession(id)
        scheduleSave()
    }

    var canReopenClosedSession: Bool {
        !recentlyClosed.isEmpty
    }

    /// ⌘⇧T: opens the session closed last again, with the conversation to resume if an agent was
    /// running in it. Its folder may be gone by now; the project's folder, then home, stand in.
    func reopenClosedSession() -> (session: Session, conversation: AgentConversation?)? {
        guard let closed = recentlyClosed.pop() else { return nil }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let projectFolder = closed.projectID.flatMap { workspace.project($0)?.path }
        let directory = [closed.workingDirectory, projectFolder].compactMap(\.self).first { path in
            var isDirectory: ObjCBool = false
            return FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) && isDirectory.boolValue
        } ?? home
        let session = workspace.reopen(closed, in: directory, gitRoot: GitRoot.find)
        scheduleSave()
        return (session, closed.conversation)
    }

    func select(_ id: Session.ID) {
        workspace.select(id)
        AttentionCenter.shared.sessionVisited(id)
        scheduleSave()
    }

    /// Calm lost focus: the session on screen has been seen, so a finished one settles.
    func settleOnScreen() {
        guard let id = workspace.selectedLayout?.focusedSessionID, let state = workspace.session(id)?.state,
              state.afterVisit() != state else { return }
        Motion.animate(.easeInOut(duration: 0.25)) {
            workspace.settle(id)
        }
        scheduleSave()
    }

    func updateTree(_ layoutID: PaneLayout.ID, _ tree: SplitTree<Session.ID>) {
        workspace.updateTree(layoutID, tree)
        scheduleSave()
    }

    func setFocused(_ sessionID: Session.ID) {
        guard let layout = workspace.layout(containing: sessionID), layout.focusedSessionID != sessionID else { return }
        workspace.select(sessionID)
        AttentionCenter.shared.sessionVisited(sessionID)
        scheduleSave()
    }

    func titleChanged(_ id: Session.ID, _ title: String) {
        // Compared without an agent's spinner glyph, so a turning spinner doesn't save the state each frame.
        let title = Session.shellTitle(title)
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

    // MARK: Attention

    /// The session the user is looking at: the focused one, while Calm is the active app.
    var lookingAtSessionID: Session.ID? {
        guard Headless.isOn || NSApp.isActive && NSApp.keyWindow === TerminalWindowManager.shared.mainController?.window else {
            return nil
        }
        return workspace.selectedLayout?.focusedSessionID
    }

    /// Applies a status report (from a hook or a terminal signal) and passes on what it means
    /// for notifications.
    func report(_ id: Session.ID, _ report: StatusReport) {
        let previous = workspace.session(id)?.state
        var effect = AttentionEffect.none
        Motion.animate(.easeInOut(duration: 0.25)) {
            effect = workspace.report(id, report, focusedSessionID: lookingAtSessionID)
        }
        AttentionCenter.shared.apply(effect, for: id)
        // Opted in (Agents panel): a turn finishing or failing where you aren't looking notifies too.
        if settings.notifyStates == .all, let state = workspace.session(id)?.state, state != previous,
           state == .done || state == .failed, id != lookingAtSessionID {
            AttentionCenter.shared.notify(report.message ?? state.label, for: id)
        }
        scheduleSave()
    }

    /// A program in the session signalled something (DESIGNS.md → Attention → fallback signals).
    /// Reports go in with source `terminal`, so an agent's hooks still outrank them.
    func terminalSignal(_ id: Session.ID, _ signal: TerminalSignal) {
        guard let session = workspace.session(id) else { return }
        switch signal.outcome(currentState: session.state, hasAgent: session.agent != nil) {
        case let .report(state, message):
            report(id, StatusReport(state: state, message: message, source: .terminal))
        case let .notify(message):
            if id != lookingAtSessionID {
                AttentionCenter.shared.notify(message, for: id)
            }
        case .ignore:
            break
        }
    }

    /// A new reading of an agent's transcript. An interruption counts only if the transcript was
    /// written after the latest report (a new prompt's hook can arrive before its transcript line).
    func transcriptChanged(_ id: Session.ID, _ tail: TranscriptTail, modified: Date) {
        guard let session = workspace.session(id), session.agent?.tail != tail else { return }
        var tail = tail
        if tail.interrupted, let reported = session.lastReport?.date, reported >= modified {
            tail.interrupted = false
        }
        Motion.animate(.easeInOut(duration: 0.25)) {
            workspace.updateTranscriptTail(id, tail)
        }
        scheduleSave()
    }

    func noteAgentSession(_ id: Session.ID, kind: AgentKind, agentSessionID: String?, transcriptPath: String?) {
        workspace.noteAgentSession(id, kind: kind, agentSessionID: agentSessionID, transcriptPath: transcriptPath)
        scheduleSave()
    }

    /// The session's foreground job changed; an agent may have started or exited.
    func foregroundChanged(_ id: Session.ID, to process: ProcessSnapshot?) {
        guard let session = workspace.session(id) else { return }
        if let process, let kind = Agents.detect(process) {
            Self.log.info("agent \(kind.rawValue, privacy: .public) started in \(id, privacy: .public) (pid \(process.processID))")
            Motion.animate(.easeInOut(duration: 0.25)) {
                workspace.startAgentRun(id, AgentRun(kind: kind, processID: process.processID))
            }
        } else if let agent = session.agent {
            Self.log.info("agent \(agent.kind.rawValue, privacy: .public) ended in \(id, privacy: .public)")
            Motion.animate(.easeInOut(duration: 0.25)) {
                workspace.endAgentRun(id)
            }
        } else {
            return
        }
        scheduleSave()
    }

    /// Names a session (FEATURES.md → F12); an empty name gives it back its own title.
    func rename(_ id: Session.ID, to name: String?) {
        workspace.rename(id, to: name)
        scheduleSave()
    }

    #if DEBUG
        /// Self-tests: what a click on the mark of the project called `name` does.
        func shuffleMarkForTesting(named name: String) -> Bool {
            guard let project = workspace.projects.first(where: { $0.kind == .project && $0.name == name }) else { return false }
            shuffleMark(project.id)
            return true
        }

        /// Self-tests: a conversation that ended in `id`, without starting an agent.
        func setLastConversationForTesting(_ id: Session.ID, _ conversation: AgentConversation) {
            guard let index = workspace.sessions.firstIndex(where: { $0.id == id }) else { return }
            workspace.sessions[index].lastConversation = conversation
        }
    #endif

    // MARK: Projects

    @discardableResult
    func addProject(path: String) -> Project {
        var project: Project?
        Motion.animate {
            project = workspace.addProject(path: path, gitRoot: GitRoot.find)
        }
        scheduleSave()
        // Motion.animate runs its body at once, animated or not; the fallback only satisfies the type.
        return project ?? workspace.addProject(path: path, gitRoot: GitRoot.find)
    }

    /// A directory group becomes a project (FEATURES.md → F2).
    func makeProject(_ projectID: Project.ID) {
        Motion.animate { workspace.makeProject(projectID) }
        scheduleSave()
    }

    /// A project the user made goes back to being folders (FEATURES.md → F2).
    func removeProject(_ projectID: Project.ID) {
        Motion.animate { workspace.removeProject(projectID, gitRoot: GitRoot.find) }
        scheduleSave()
    }

    func move(_ id: Session.ID, to projectID: Project.ID) {
        Motion.animate { workspace.move(id, to: projectID) }
        scheduleSave()
    }

    func followFolder(_ id: Session.ID) {
        Motion.animate { workspace.followFolder(id, gitRoot: GitRoot.find) }
        scheduleSave()
    }

    /// A scratch session's folder, moved to `path` already, becomes a project there.
    func keepScratchAsProject(_ id: Session.ID, at path: String) {
        Motion.animate { workspace.keepScratchAsProject(id, at: path, gitRoot: GitRoot.find) }
        scheduleSave()
    }

    func toggleCollapsed(_ projectID: Project.ID) {
        guard let project = workspace.project(projectID) else { return }
        Motion.animate(.easeInOut(duration: 0.18)) {
            workspace.setCollapsed(projectID, !project.isCollapsed)
        }
        scheduleSave()
    }

    /// The easter egg: a project's mark, clicked, becomes another, kept across launches.
    func shuffleMark(_ projectID: Project.ID) {
        Motion.animate(.easeInOut(duration: 0.2)) {
            workspace.setMarkSeed(projectID, .random(in: .min ... .max))
        }
        scheduleSave()
    }

    /// Sessions in sidebar order, for ⌘1…9 and the ⌃Tab switcher.
    var orderedSessions: [Session] {
        workspace.orderedProjects.flatMap { workspace.sessions(in: $0.id) }
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

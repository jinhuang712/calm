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

    private(set) var workspace: Workspace {
        didSet { tellPanesWhoWorks() }
    }

    @ObservationIgnored private let store: WorkspaceStore
    @ObservationIgnored private(set) var panes: [Session.ID: TerminalSurfaceView] = [:]
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    /// The last few sessions closed, for ⌘⇧T. Kept in memory only.
    @ObservationIgnored private var recentlyClosed = ClosedSessions()
    /// Each session's working line, apart from the workspace so a tool call redraws one card
    /// (`LiveLineBox`, `liveLine(for:)`). Not observed itself: each card observes its own box.
    @ObservationIgnored var liveLines: [Session.ID: LiveLineBox] = [:]

    /// Turned off for the rest of the run if persistent shells fail to start.
    @ObservationIgnored var persistenceEnabled = true

    /// Calm's own settings (`~/.config/calm/config.toml`); re-read with Reload Configuration.
    @ObservationIgnored var settings = CalmSettings.load() {
        didSet {
            InterfaceScale.shared.update(from: settings)
        }
    }

    /// Whether sessions move between projects when their folder changes (config: `sidebar.auto-grouping`).
    var autoGrouping: Bool {
        settings.autoGrouping
    }

    /// No workspace was ever saved: Calm's very first launch (the welcome page shows).
    @ObservationIgnored let isFirstUse: Bool

    /// When the saved workspace was written: at a launch, how long Calm was away.
    @ObservationIgnored let stateSavedAt: Date?

    /// Sessions whose rows show as loading: their saved agent run is being checked against the
    /// running agent and the check is taking a moment (DESIGNS.md → Launch). Empty almost
    /// always, since the check is over before the window opens. Not saved.
    private(set) var confirming: Set<Session.ID> = []
    @ObservationIgnored private var confirmingSince: ContinuousClock.Instant?

    /// Agents being restarted, or waiting for their turn to end to be (FEATURES.md → F12,
    /// `SessionManager+Restart`). Not saved: a relaunch forgets a restart that hadn't begun.
    var restarts: [Session.ID: RestartPhase] = [:]
    /// Sessions whose agent runs an older version than the one installed (the title strip's
    /// update hint), from `checkAgentVersions`. Not saved.
    var agentUpdates: [Session.ID: AgentUpdate] = [:]
    /// What each running agent runs, for the session menu's header; from the same checks. Not saved.
    var runningVersions: [Session.ID: String] = [:]
    /// A version check is out, off the main thread.
    @ObservationIgnored var checkingVersions = false

    /// Once shown, the loading state stays at least this long, so a check that ends just after
    /// the window opens doesn't flash.
    nonisolated static let minimumLoading = Duration.milliseconds(450)

    init(store: WorkspaceStore = .standard) {
        self.store = store
        isFirstUse = !FileManager.default.fileExists(atPath: store.fileURL.path)
        stateSavedAt = (try? FileManager.default.attributesOfItem(atPath: store.fileURL.path))?[.modificationDate] as? Date
        workspace = store.load()
    }

    // MARK: Lifecycle

    /// Prepares the saved workspace at launch, so Calm starts where the user left off.
    ///
    /// A saved agent run is kept, with its state and what its card shows: the launch pass
    /// (`SessionProbe.settleSavedRuns`) checks it against the running agent before the window
    /// opens, so the sidebar comes back as it was left.
    func restore() {
        removeOrphanedShells()
        Trace.note("orphaned shells checked")
        for session in workspace.sessions {
            Trace.note("restore \(Trace.id(session.id)): \(Trace.describe(session)) (saved)")
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

    // MARK: Launch pass

    /// How much of the loading state is left once it has been shown for `shown`.
    nonisolated static func remainingLoading(shown: Duration) -> Duration {
        max(.zero, minimumLoading - shown)
    }

    /// The launch pass is taking longer than the window can wait: these rows show as loading.
    func beginConfirming(_ ids: Set<Session.ID>) {
        confirming = ids
        confirmingSince = .now
    }

    /// Ends the loading state with what the pass found, no sooner than `minimumLoading` after it
    /// began. The answer is applied with it, so a row doesn't change height under its placeholder.
    func finishConfirming(_ answer: LaunchPass.Answer?) {
        let wait = Self.remainingLoading(shown: confirmingSince.map { $0.duration(to: .now) } ?? .zero)
        guard wait > .zero else {
            settleSavedRuns(answer, animated: true)
            return
        }
        Task { [self] in
            try? await Task.sleep(for: wait)
            settleSavedRuns(answer, animated: true)
        }
    }

    /// Settles every saved agent run against what the launch pass found. With no answer (nothing
    /// in time, or no persistent shells to have kept the agents alive) every run is over, as a
    /// launch always made it.
    func settleSavedRuns(_ answer: LaunchPass.Answer?, animated: Bool = false) {
        let settle = { [self] in
            for session in workspace.sessions where session.agent != nil {
                let found = answer?.outcomes[session.id] ?? .gone
                let shellGone = answer?.shellIsGone(session.persistentName) ?? false
                workspace.settleSavedRun(session.id, found: found, shellGone: shellGone, savedAt: stateSavedAt)
                Trace.settled(session.id, found: found, before: session, after: workspace.session(session.id))
            }
            confirming = []
            confirmingSince = nil
        }
        if animated {
            Motion.animate(.easeInOut(duration: 0.45), settle)
        } else {
            settle()
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

    /// The pane for a session, creating it (and attaching its persistent shell) if needed. `size`
    /// is the pane's size in the layout, when known, so its shell starts at that size.
    func pane(for sessionID: Session.ID, host: TerminalSurfaceHost?, size: NSSize? = nil) -> TerminalSurfaceView? {
        if let existing = panes[sessionID] {
            existing.host = host
            return existing
        }
        guard let session = workspace.session(sessionID) else { return nil }
        var options = TerminalSurfaceOptions.session
        options.size = size
        // Starts at the saved text size too, rather than setting it once the shell runs, which
        // resized the terminal of a program that had just read it. libghostty counts this size
        // as the user's, so a config reload keeps it (engine patch 0013).
        options.fontSize = workspace.fontSize ?? 0
        options.workingDirectory = session.workingDirectory
        if persistenceEnabled, let command = PersistentShell.attachCommand(name: session.persistentName) {
            options.command = command
            let process = ProcessInfo.processInfo.environment
            options.environment = PersistentShell.environment.merging(ShellIntegration.environment(
                shell: process["SHELL"],
                mode: TerminalEngine.shared.config?.string("shell-integration"),
                resourcesDirectory: process["GHOSTTY_RESOURCES_DIR"],
                inherited: process,
                calmZsh: ShellIntegration.preparedZshDirectory,
            )) { current, _ in current }
        }
        options.environment.merge(AgentIntegrations.environment(settings: settings)) { current, _ in current }
        let pane = TerminalSurfaceView(id: session.id, options: options)
        Trace.note("pane \(Trace.id(sessionID)): attaching at \(pane.gridSize)")
        pane.host = host
        pane.setSessionWorking(session.state == .working)
        panes[session.id] = pane
        resumeIfShellWasLost(session.id)
        return pane
    }

    /// A hidden pane reads a full-screen program's screen only while its session works, for
    /// find's whole session (TerminalSurfaceView+Keep).
    private func tellPanesWhoWorks() {
        for (id, pane) in panes {
            pane.setSessionWorking(workspace.session(id)?.state == .working)
        }
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

    // MARK: Window

    /// Whether the window was left filling the screen, so the next launch fills it again.
    var windowWasFilled: Bool {
        workspace.windowFilled == true
    }

    /// Called as the window settles into, or out of, filling the screen.
    func windowFillDidChange(_ filled: Bool) {
        if workspace.noteWindowFilled(filled) {
            scheduleSave()
        }
    }

    /// Whether the window was left in full screen, so the next launch enters it again.
    var windowWasFullScreen: Bool {
        workspace.windowFullScreen == true
    }

    /// Called as the window settles into, or out of, full screen.
    func windowFullScreenDidChange(_ fullScreen: Bool) {
        if workspace.noteWindowFullScreen(fullScreen) {
            scheduleSave()
        }
    }

    // MARK: Sessions

    @discardableResult
    func newSession(in directory: String, placement: Workspace.Placement = .directory, selecting: Bool = true) -> Session {
        let session = workspace.newSession(in: directory, placement: placement, gitRoot: GitRoot.find, selecting: selecting)
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

    /// Puts an existing session beside another, in that one's layout (the model does the work;
    /// this keeps it saved and tells attention the session is now the one in front).
    @discardableResult
    func joinSession(_ id: Session.ID, beside target: Session.ID, direction: SplitTree<Session.ID>.Direction) -> Bool {
        guard workspace.join(id, beside: target, direction: direction) else { return false }
        AttentionCenter.shared.sessionVisited(id)
        scheduleSave()
        return true
    }

    /// A pane leaves its split and is a session of its own; nothing ends.
    @discardableResult
    func takeOutSession(_ id: Session.ID) -> Bool {
        guard workspace.takeOut(id) else { return false }
        scheduleSave()
        return true
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
            // That ended the agent before it could clean up after itself: an empty worktree it
            // made for this session goes too (`claude -w`).
            WorktreeCleanup.afterClose(session, open: workspace.sessions)
            if let folder = session.scratchFolder, !workspace.sessions.contains(where: { $0.id != id && $0.scratchFolder == folder }) {
                ScratchFolders.discard(folder)
            }
        }
        panes[id]?.teardown()
        panes[id] = nil
        restarts[id] = nil
        agentUpdates[id] = nil
        runningVersions[id] = nil
        liveLines[id] = nil
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
        show(id)
        AttentionCenter.shared.sessionVisited(id)
        scheduleSave()
    }

    /// Selects `id`. A collapsed group holding it opens the way a click on its header opens it;
    /// otherwise the change is left as it was (the selection ring doesn't need the slide).
    private func show(_ id: Session.ID) {
        if workspace.isInCollapsedGroup(id) {
            Motion.animate(.easeInOut(duration: 0.18)) { workspace.select(id) }
        } else {
            workspace.select(id)
        }
    }

    /// The focused session and its state, for `LeavingCalm`.
    var onScreen: LeavingCalm.OnScreen? {
        guard let id = workspace.selectedLayout?.focusedSessionID, let state = workspace.session(id)?.state else {
            return nil
        }
        return LeavingCalm.OnScreen(sessionID: id, state: state)
    }

    /// The user left Calm (`LeavingCalm`): the session they saw there has been read, so a
    /// finished one settles.
    func settle(left: LeavingCalm.OnScreen) {
        guard left.state.afterVisit() != left.state else { return }
        Motion.animate(.easeInOut(duration: 0.25)) {
            workspace.settle(left.sessionID)
        }
        scheduleSave()
    }

    func updateTree(_ layoutID: PaneLayout.ID, _ tree: SplitTree<Session.ID>) {
        workspace.updateTree(layoutID, tree)
        scheduleSave()
    }

    func setFocused(_ sessionID: Session.ID) {
        guard let layout = workspace.layout(containing: sessionID), layout.focusedSessionID != sessionID else { return }
        show(sessionID)
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

    /// Applies `change` to a copy of the workspace and writes it back only if it changed. Any write
    /// to `workspace`, even a mutating call that leaves it as it was, has every view that reads it
    /// render again: 13 to 20 million instructions for the sidebar, measured with one card and with
    /// ten. Agents' hooks mostly repeat themselves (each tool call reports *working* twice, and
    /// names its session and transcript again), and the model already ignores a repeat.
    @discardableResult
    func changeWorkspace(animation: Animation? = nil, _ change: (inout Workspace) -> Void) -> Bool {
        var copy = workspace
        change(&copy)
        guard copy != workspace else { return false }
        if let animation {
            Motion.animate(animation) { workspace = copy }
        } else {
            workspace = copy
        }
        return true
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
        Trace.transcriptRead(id, tail, before: session.state, after: workspace.session(id)?.state)
        // An agent with no hook or extension can't say it is working or has finished; its transcript
        // does (`TranscriptTail.stateChange`). Reported as a terminal-grade guess, so a real hook
        // still outranks it.
        if let current = workspace.session(id),
           let state = tail.stateChange(from: current.state, after: current.lastReport, transcriptWritten: modified) {
            report(id, StatusReport(state: state, message: state == .done ? tail.lastMessage : nil, source: .terminal))
        }
        scheduleSave()
    }

    /// The session's foreground job changed; an agent may have started or exited.
    func foregroundChanged(_ id: Session.ID, to process: ProcessSnapshot?) {
        guard let session = workspace.session(id) else { return }
        if let process, let kind = Agents.detect(process) {
            Self.log.info("agent \(kind.rawValue, privacy: .public) started in \(id, privacy: .public) (pid \(process.processID))")
            var run = AgentRun(kind: kind, processID: process.processID)
            // Back from a restart: the same conversation, so the card keeps its title and recap
            // instead of starting blank until the hooks speak.
            if restarts[id] == .restarting, let previous = session.agent, previous.kind == kind {
                run.agentSessionID = previous.agentSessionID
                run.transcriptPath = previous.transcriptPath
                run.tail = previous.tail
            }
            Motion.animate(.easeInOut(duration: 0.25)) {
                workspace.startAgentRun(id, run)
            }
            Trace.probed(id, "\(kind.rawValue) started (pid \(process.processID))", before: session, after: workspace.session(id))
            // A restart is over once the agent is back; a new process is checked afresh.
            if restarts[id] == .restarting {
                restarts[id] = nil
            }
            agentUpdates[id] = nil
            runningVersions[id] = nil
        } else if let agent = session.agent, restarts[id] == .restarting {
            // Quitting to be started again: the card stays as it is for the second that takes,
            // rather than turning into a shell row and back (`finishRestart` ends the run if the
            // agent never comes back).
            Trace.probed(id, "\(agent.kind.rawValue) quit to restart", before: session, after: session)
            return
        } else if let agent = session.agent {
            Self.log.info("agent \(agent.kind.rawValue, privacy: .public) ended in \(id, privacy: .public)")
            Motion.animate(.easeInOut(duration: 0.25)) {
                workspace.endAgentRun(id)
            }
            // The agent exited by itself: nothing is left to restart. (One being restarted exits
            // on purpose, and its command follows.)
            if restarts[id] == .afterTurn {
                restarts[id] = nil
            }
            agentUpdates[id] = nil
            runningVersions[id] = nil
            Trace.probed(id, "\(agent.kind.rawValue) ended", before: session, after: workspace.session(id))
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

    /// Folds or unfolds every group in the sidebar.
    func setAllCollapsed(_ collapsed: Bool) {
        Motion.animate(.easeInOut(duration: 0.18)) {
            workspace.setAllCollapsed(collapsed)
        }
        scheduleSave()
    }

    /// Chooses no session: the main area shows what waits, or search (`NoSessionPage`).
    func deselect() {
        Motion.animate(.easeInOut(duration: 0.25)) {
            workspace.deselect()
        }
        scheduleSave()
    }

    /// Settles every finished session the user hasn't opened, and withdraws their notifications.
    func markDoneSeen() {
        let current = workspace.selectedLayout?.focusedSessionID
        var seen: [Session.ID] = []
        Motion.animate(.easeInOut(duration: 0.25)) {
            seen = workspace.markDoneSeen(except: current)
        }
        seen.forEach { AttentionCenter.shared.sessionSeen($0) }
        scheduleSave()
    }

    /// Gives every pane of the layout a session of its own in the sidebar (`Workspace.unsplit`).
    @discardableResult
    func unsplit(_ layoutID: PaneLayout.ID) -> [PaneLayout] {
        let apart = workspace.unsplit(layoutID)
        if !apart.isEmpty {
            scheduleSave()
        }
        return apart
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

    func scheduleSave() {
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

/// Here for the workspace's private setter; the rest of restarting is in SessionManager+Restart.
extension SessionManager {
    /// A restart that didn't bring the agent back: its run ends as if it had exited, so the card
    /// doesn't go on showing an agent that isn't there.
    func endRestart(_ id: Session.ID) {
        restarts[id] = nil
        guard let agent = workspace.session(id)?.agent, ProcessInspector.snapshot(of: agent.processID) == nil else { return }
        Motion.animate(.easeInOut(duration: 0.25)) {
            workspace.endAgentRun(id)
        }
        Trace.note("restart \(Trace.id(id)): the agent didn't come back")
        scheduleSave()
    }
}

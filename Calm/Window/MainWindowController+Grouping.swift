import AppKit
import CalmModel

/// Session grouping in the window (FEATURES.md → F2): scratch sessions, projects the user made,
/// and the welcome page when nothing is open.
extension MainWindowController {
    // MARK: Scratch sessions

    /// ⌘⇧N: a scratch session in a new hidden folder, on top of the sidebar, running the agent ⌘N
    /// starts (FEATURES.md → New agent sessions), or a plain shell when there is none.
    func newScratchSession() {
        hideSettings()
        guard let session = manager.newScratchSession() else { return }
        showSelectedLayout(animated: true)
        AgentIntegrations.trustScratchFolders()
        if let agent = newSessionAgent {
            startAgent(agent, in: session)
        }
    }

    /// Closing a scratch session whose folder has files asks what to do with them first:
    /// the folder is hidden, so keeping it as it is would strand them.
    func requestCloseScratch(_ session: Session, then close: @escaping () -> Void) {
        guard let folder = session.scratchFolder, let window, !ScratchFolders.contents(of: folder).isEmpty,
              !manager.workspace.sessions.contains(where: { $0.id != session.id && $0.scratchFolder == folder })
        else {
            close()
            return
        }
        let count = ScratchFolders.contents(of: folder).count
        let alert = NSAlert()
        alert.messageText = "Close “\(session.title(agentTitle: session.agent?.tail?.title))”?"
        let files = count == 1 ? "a file" : "\(count) files"
        alert.informativeText = "It made \(files). Move them to the Trash with it, or keep them as a project."
        alert.addButton(withTitle: "Move to Trash")
        alert.addButton(withTitle: "Keep as Project…")
        alert.addButton(withTitle: "Cancel")
        if Headless.isOn {
            FileHandle.standardError.write(Data("calm-selftest: would ask about \(count) scratch files\n".utf8))
            return
        }
        alert.beginSheetModal(for: window) { [weak self] response in
            MainActor.assumeIsolated {
                switch response {
                case .alertFirstButtonReturn: close()
                case .alertSecondButtonReturn: self?.keepScratchAsProject(session.id)
                default: break
                }
            }
        }
    }

    /// "Keep as Project…": the scratch folder moves where the user picks and becomes a project.
    func keepScratchAsProject(_ id: Session.ID) {
        guard let session = manager.workspace.session(id), let folder = session.scratchFolder, let window else { return }
        let panel = NSSavePanel()
        panel.title = "Keep as Project"
        panel.prompt = "Keep"
        panel.nameFieldLabel = "Project:"
        panel.nameFieldStringValue = session.customName ?? session.agent?.tail?.title ?? "Untitled Project"
        panel.canCreateDirectories = true
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            MainActor.assumeIsolated {
                self?.moveScratchFolder(of: id, from: folder, to: url)
            }
        }
    }

    func moveScratchFolder(of id: Session.ID, from folder: String, to url: URL) {
        do {
            try FileManager.default.moveItem(at: URL(filePath: folder, directoryHint: .isDirectory), to: url)
        } catch {
            NSAlert(error: error).runModal()
            return
        }
        // The shell stays in its folder (moved with it); only its old path is gone.
        manager.keepScratchAsProject(id, at: url.path)
    }

    // MARK: Projects

    /// Projects for `urls`, and the last one's home (FEATURES.md → F2): what to start there is the
    /// user's to choose, so no session opens by itself.
    func addProjects(_ urls: [URL]) {
        let projects = urls.map { manager.addProject(path: $0.path) }
        if let project = projects.last {
            showProjectHome(project.id)
        }
    }

    /// Remove Project. Its home goes with it, since there is no project left to show.
    func removeProject(_ id: Project.ID) {
        manager.removeProject(id)
        if homeProjectID == id {
            leaveProjectHome()
        }
    }

    func chooseNewProject() {
        guard let window else { return }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        panel.prompt = "Add Project"
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK else { return }
            MainActor.assumeIsolated {
                self?.addProjects(panel.urls)
            }
        }
    }

    /// A new session in a project the user made, which it stays in; or in a directory group's folder.
    @discardableResult
    func newSession(in project: Project) -> Session {
        hideSettings()
        let session = manager.newSession(in: project.path, placement: project.kind == .project ? .project(project.id) : .directory)
        showSelectedLayout(animated: true)
        return session
    }

    /// A session in `project` running `kind`, ⌘N's agent unless given (a group header's agent mark,
    /// a project home's start line), or a plain shell when no agent is installed.
    func newAgentSession(in project: Project, kind: AgentKind? = nil) {
        let session = newSession(in: project)
        if let agent = kind ?? newSessionAgent {
            startAgent(agent, in: session)
        }
    }

    // MARK: Project home

    /// The project whose home the main area shows (UIUX.md → Project home), nil otherwise.
    var homeProjectID: Project.ID? {
        sidebarEditing.homeProjectID
    }

    /// The project whose home is up, while it still exists.
    var homeProject: Project? {
        homeProjectID.flatMap { manager.workspace.project($0) }
    }

    /// Esc on a home: it goes, and the main area shows what it would with no session chosen (with
    /// none open, the welcome page).
    func leaveProjectHome() {
        guard homeProjectID != nil else { return }
        sidebarEditing.homeProjectID = nil
        showSelectedLayout(animated: false)
    }

    func updateProjectHome() {
        guard manager.workspace.selectedLayout == nil, let project = homeProject else {
            projectHomePage.hide()
            return
        }
        let background = TerminalEngine.shared.config?.backgroundColor ?? NSColor(white: 0.15, alpha: 1)
        projectHomePage.show(project: project, style: sidebarStyle, background: background, actions: projectHomeActions(project))
    }

    private func projectHomeActions(_ project: Project) -> ProjectHomeView.Actions {
        ProjectHomeView.Actions(
            agents: startAgents,
            newAgentSession: { [weak self] kind in self?.newAgentSession(in: project, kind: kind) },
            chooseNewSessionAgent: { [weak self] in self?.showSettings(.agents) },
            newShell: { [weak self] in self?.newSession(in: project) },
            open: { [weak self] item in self?.openSearchResult(item) },
            leave: { [weak self] in self?.leaveProjectHome() },
        )
    }

    /// The placement and folder a session opened from `id` (⌘T, a split) gets: a project
    /// session's project; a scratch session's folder is never shared (home instead).
    func placementAndFolder(from id: Session.ID?, pane: TerminalSurfaceView?) -> (Workspace.Placement, String) {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let session = id.flatMap { manager.workspace.session($0) }
        if session?.isScratch == true {
            return (.directory, home)
        }
        let folder = pane?.workingDirectory ?? session?.workingDirectory ?? home
        return (manager.workspace.inheritedPlacement(from: id), folder)
    }

    // MARK: Welcome

    /// Shows the welcome page while no session is open, and takes it away once one is.
    func updateWelcomePage() {
        // A project's home stands beside the sidebar even with no session open.
        guard manager.workspace.sessions.isEmpty, homeProject == nil else {
            welcomePage.hide()
            return
        }
        let background = TerminalEngine.shared.config?.backgroundColor ?? NSColor(white: 0.15, alpha: 1)
        welcomePage.show(
            firstUse: manager.isFirstUse, projects: manager.workspace.madeProjects,
            style: sidebarStyle, background: background, actions: welcomeActions,
        )
    }

    /// The pages that stand in for a session: the welcome page with none open, the main area's page
    /// with none chosen.
    func updatePages() {
        updateWelcomePage()
        updateProjectHome()
        updateNoSessionPage()
    }

    /// Sessions are open but none is chosen, and no project's home is up: the main area shows what
    /// waits, or search.
    func updateNoSessionPage() {
        guard manager.workspace.selectedLayout == nil, !manager.workspace.sessions.isEmpty, homeProject == nil else {
            noSessionPage.hide()
            return
        }
        let background = TerminalEngine.shared.config?.backgroundColor ?? NSColor(white: 0.15, alpha: 1)
        // Read here and passed in: the settings aren't observed, and folding the footer or hiding
        // the sidebar comes back through here (applyAppearance, toggleSidebar).
        let footerShown = manager.settings.sidebarFooter && (sidebarWidth?.constant ?? 0) > 0
        noSessionPage.show(
            manager: manager, style: sidebarStyle, background: background, sidebarFooterShown: footerShown,
            actions: NoSessionView.Actions(open: { [weak self] id in self?.select(id) }, welcome: welcomeActions),
        )
    }

    /// Back from something laid over the window (Settings, search, the command palette): the keys go
    /// to the session on screen, or with none chosen to the main area's page.
    func refocus() {
        if let focusedPane {
            window?.makeFirstResponder(focusedPane)
        } else if projectHomePage.isShowing {
            projectHomePage.focus()
        } else {
            noSessionPage.focus()
        }
    }

    /// ⌘1…9: the session at that place in the sidebar, counting from the top.
    func selectSession(atPosition index: Int) -> Bool {
        let sessions = manager.orderedSessions
        guard sessions.indices.contains(index) else { return false }
        select(sessions[index].id)
        return true
    }

    /// ⌘K. The welcome page, and the main area's lists, have a search field of their own, so there
    /// the caret goes to it instead of a second search opening over it.
    func searchSessions() {
        if !welcomePage.focusSearch(), !noSessionPage.focusSearch() {
            toggleSearch()
        }
    }

    var welcomeActions: WelcomeView.Actions {
        WelcomeView.Actions(
            agents: startAgents,
            newAgentSession: { [weak self] kind in self?.newAgentSession(kind) },
            chooseNewSessionAgent: { [weak self] in self?.showSettings(.agents) },
            newSession: { [weak self] in self?.newSession() },
            newScratchSession: { [weak self] in self?.newScratchSession() },
            newProject: { [weak self] in self?.chooseNewProject() },
            openProject: { [weak self] project in self?.showProjectHome(project.id) },
            open: { [weak self] item in self?.openSearchResult(item) },
        )
    }
}

import AppKit
import CalmModel

/// Session grouping in the window (FEATURES.md → F2): scratch sessions, projects the user made,
/// and the welcome page when nothing is open.
extension MainWindowController {
    // MARK: Scratch sessions

    /// ⌘⇧N: a scratch session in a new hidden folder, on top of the sidebar.
    func newScratchSession() {
        guard manager.newScratchSession() != nil else { return }
        showSelectedLayout(animated: true)
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

    /// Projects for `urls`, and a session in the last one, which stays in it (FEATURES.md → F2).
    func addProjects(_ urls: [URL]) {
        let projects = urls.map { manager.addProject(path: $0.path) }
        if let project = projects.last, manager.workspace.sessions(in: project.id).isEmpty {
            newSession(in: project)
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
    func newSession(in project: Project) {
        manager.newSession(in: project.path, placement: project.kind == .project ? .project(project.id) : .directory)
        showSelectedLayout(animated: true)
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
        guard manager.workspace.sessions.isEmpty else {
            welcomePage.hide()
            return
        }
        let background = TerminalEngine.shared.config?.backgroundColor ?? NSColor(white: 0.15, alpha: 1)
        welcomePage.show(
            firstUse: manager.isFirstUse, style: sidebarStyle, background: background,
            actions: WelcomeView.Actions(
                newSession: { [weak self] in self?.newSession() },
                newScratchSession: { [weak self] in self?.newScratchSession() },
                newProject: { [weak self] in self?.chooseNewProject() },
                setUpAgents: { SettingsWindowController.shared.show(.agents) },
            ),
        )
    }
}

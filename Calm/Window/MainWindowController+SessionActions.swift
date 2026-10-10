import AppKit
import CalmAgents
import CalmModel

/// Session actions (FEATURES.md → F12): rename a session, resume the conversation that ended in
/// it, fork a conversation into a new split or tab, each with the agent's own command.
extension MainWindowController {
    enum ForkDestination {
        case split, tab
    }

    /// The command that resumes the conversation that ended in `session`, if its agent has one.
    static func resumeCommand(for session: Session) -> String? {
        session.resumableConversation.flatMap(resumeCommand)
    }

    /// With the options its agent was started with.
    static func resumeCommand(for conversation: AgentConversation) -> String? {
        Agents.adapter(for: conversation.kind)?.resumeCommand(for: conversation)
    }

    /// The command that forks `session`'s conversation (running or ended), if its agent can.
    static func forkCommand(for session: Session) -> String? {
        guard let conversation = session.conversation else { return nil }
        return Agents.adapter(for: conversation.kind)?.forkCommand(for: conversation)
    }

    /// The sidebar as it should look now. Everything it draws from that SwiftUI doesn't observe
    /// (the colors, the footer, the card size) goes in as a value, so a rebuilt sidebar redraws.
    func makeSidebar(style: SidebarStyle) -> SidebarView {
        SidebarView(
            manager: manager,
            style: style,
            showsFooter: manager.settings.sidebarFooter,
            cardSize: manager.settings.sessionCardSize,
            fitsCards: manager.settings.sessionCardsFit,
            startAgents: startAgents,
            onSelect: { [weak self] id in self?.select(id) },
            onClose: { [weak self] id in self?.requestCloseSession(id) },
            onNewSession: { [weak self] in self?.newSession() },
            onNewProject: { [weak self] in self?.chooseNewProject() },
            editing: sidebarEditing,
            files: filesColumn.model,
            actions: sessionActions,
        )
    }

    /// What the sidebar's cards and the title's ⋯ button both do.
    var sessionActions: SidebarActions {
        SidebarActions(
            rename: { [weak self] id, name in self?.rename(id, to: name) },
            resume: { [weak self] id in self?.resumeConversation(in: id) },
            fork: { [weak self] id, destination in self?.forkConversation(of: id, into: destination) },
            newScratchSession: { [weak self] in self?.newScratchSession() },
            newAgentSession: { [weak self] kind in self?.newAgentSession(kind) },
            chooseNewSessionAgent: { [weak self] in self?.showSettings(.agents) },
            showFooter: { [weak self] shown in self?.setSidebarFooter(shown) },
            search: { [weak self] in self?.toggleSearch() },
            toggleFiles: { [weak self] in self?.toggleFiles() },
            newSessionIn: { [weak self] project in self?.newSession(in: project) },
            addProjects: { [weak self] urls in self?.addProjects(urls) },
            makeProject: { [weak self] id in self?.manager.makeProject(id) },
            removeProject: { [weak self] id in self?.removeProject(id) },
            move: { [weak self] id, project in self?.manager.move(id, to: project) },
            followFolder: { [weak self] id in self?.manager.followFolder(id) },
            keepScratch: { [weak self] id in self?.keepScratchAsProject(id) },
            copy: { [weak self] id, copy in self?.copy(copy, of: id) },
            openFolder: { [weak self] id in self?.openFolder(of: id) },
            takeOut: { [weak self] id in self?.takeOutPane(id) },
            restart: { [weak self] id in self?.restartAgent(in: id) },
            cancelRestart: { [weak self] id in self?.manager.cancelRestart(id) },
            showMenu: { [weak self] id, point in self?.showSessionMenu(id, atWindowPoint: point) },
            showProjectHome: { [weak self] id in self?.showProjectHome(id) },
            newAgentSessionIn: { [weak self] project in self?.newAgentSession(in: project) },
        )
    }

    /// Hides or shows the sidebar's footer from its hover handle. Saved in config.toml (showing it
    /// removes the key) and applied in every window; Settings has no row for it.
    func setSidebarFooter(_ shown: Bool) {
        do {
            manager.settings = try CalmSettings.save("sidebar.footer", shown ? nil : "false")
        } catch {
            FileHandle.standardError.write(Data("calm: could not save sidebar.footer: \(error)\n".utf8))
            return
        }
        TerminalWindowManager.shared.controllers.forEach { $0.applyAppearance() }
    }

    /// Starts renaming `id` in place on its card. A hidden sidebar comes back first, since the
    /// name is edited there.
    func beginRename(_ id: Session.ID) {
        if sidebarWidth?.constant == 0 {
            toggleSidebar()
        }
        sidebarEditing.renamingSessionID = id
    }

    /// Puts what `copy` names for `id` on the pasteboard, with a quiet note by the pointer.
    func copy(_ copy: SessionCopy, of id: Session.ID) {
        guard let session = manager.workspace.session(id), let text = copy.text(for: session) else { return }
        put(text, note: copy.copiedNote)
    }

    /// Text on the pasteboard, with a quiet note by the pointer.
    func put(_ text: String, note: String) {
        let pasteboard = NSPasteboard.calm
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        if Headless.isOn {
            FileHandle.standardError.write(Data("calm-selftest: copied (\(note)): \(text.debugDescription)\n".utf8))
        }
        showNote(note)
    }

    /// A quiet note by the pointer, which fades by itself.
    func showNote(_ note: String) {
        let pointer = window.map { container.convert($0.mouseLocationOutsideOfEventStream, from: nil) }
        CopyToast.show(note, at: pointer ?? NSPoint(x: container.bounds.midX, y: container.bounds.midY), in: container)
    }

    /// Opens the session's folder in Finder, showing what is in it (like `open .`). Headless
    /// self-tests log it instead of opening a window.
    func openFolder(of id: Session.ID) {
        guard let session = manager.workspace.session(id), !session.isScratch else { return }
        if Headless.isOn {
            FileHandle.standardError.write(Data("calm-selftest: would open folder \(session.workingDirectory)\n".utf8))
            return
        }
        NSWorkspace.shared.open(URL(filePath: session.workingDirectory))
    }

    func rename(_ id: Session.ID, to name: String?) {
        manager.rename(id, to: name)
        sidebarEditing.renamingSessionID = nil
    }

    /// Resumes the conversation that ended in `id`, in the same shell.
    func resumeConversation(in id: Session.ID) {
        guard let session = manager.workspace.session(id), let command = Self.resumeCommand(for: session) else { return }
        // Before `select`, whose new pane would resume it too (after a restart of the Mac).
        manager.forgetResumeWhenOpened(id)
        select(id)
        runAgentCommand(command, in: manager.panes[id])
    }

    /// Restarts the agent in `id` on its conversation (⌘P, or the title strip's update hint): now,
    /// or after its turn when it is busy.
    func restartAgent(in id: Session.ID) {
        if !manager.requestRestart(id) {
            showNote("Can't restart \(manager.workspace.session(id)?.agent?.kind.displayName ?? "the agent") here")
        }
    }

    /// ⌘⇧T: opens the session closed last again, and resumes the conversation of the agent that was
    /// running in it. The shell is a new one: closing ended the old.
    func reopenClosedSession() {
        guard let (session, conversation) = manager.reopenClosedSession() else { return }
        hideSettings()
        showSelectedLayout(animated: true)
        if let command = conversation.flatMap(Self.resumeCommand) {
            runAgentCommand(command, in: manager.panes[session.id])
        }
    }

    /// Forks `id`'s conversation into a new split beside it or a new tab, in the same folder.
    func forkConversation(of id: Session.ID, into destination: ForkDestination) {
        guard let session = manager.workspace.session(id), let command = Self.forkCommand(for: session) else { return }
        select(id)
        let pane: TerminalSurfaceView?
        switch destination {
        case .split:
            pane = manager.panes[id].flatMap { split($0, direction: .right) }
        case .tab:
            let forked = manager.newSession(in: session.workingDirectory)
            showSelectedLayout(animated: true)
            pane = manager.panes[forked.id]
        }
        runAgentCommand(command, in: pane)
    }

    /// `calm fork` (CLI.md): `command`, the agent's fork command, in a new session of its own, in
    /// `id`'s project and in `folder` or `id`'s own. It's brought to the front, unless `background`:
    /// then it waits in the sidebar, its pane made now at the terminal area's size, so the agent
    /// starts at once and at the size it will be shown at (a pane made later starts at a
    /// placeholder size, which garbled a full-screen program before).
    func forkForCLI(of id: Session.ID, command: String, in folder: String?, background: Bool) -> Session {
        let (placement, directory) = placementAndFolder(from: id, pane: manager.panes[id])
        let forked = manager.newSession(in: folder ?? directory, placement: placement, selecting: !background)
        let pane: TerminalSurfaceView?
        if background {
            pane = manager.pane(for: forked.id, host: self, size: mainArea.bounds.size)
        } else {
            hideSettings()
            showSelectedLayout(animated: true)
            pane = manager.panes[forked.id]
        }
        runAgentCommand(command, in: pane)
        return forked
    }

    /// Types an agent's command into a pane. Headless self-tests log it instead: it would start
    /// the user's real agent, on their account.
    func runAgentCommand(_ command: String, in pane: TerminalSurfaceView?) {
        guard let pane else { return }
        if Headless.isOn {
            FileHandle.standardError.write(Data("calm-selftest: would run in \(pane.id): \(command)\n".utf8))
            return
        }
        pane.run(command)
    }
}

/// What the sidebar shows that the workspace doesn't hold: which session's name is being edited
/// (UIUX.md → Session cards), and the project whose home is in the main area, whose header is
/// drawn selected (UIUX.md → Project home).
@MainActor
@Observable
final class SidebarEditing {
    var renamingSessionID: Session.ID?
    var homeProjectID: Project.ID?
}

import AppKit
import CalmAgents
import CalmModel
import SwiftUI

/// The main window: the session sidebar beside the terminal area. The terminal area keeps
/// one workspace view per layout and shows the selected one.
@MainActor
final class MainWindowController: NSWindowController, NSWindowDelegate, TerminalSurfaceHost {
    let manager: SessionManager
    let container = NSView()
    let mainArea = NSView()
    private var sidebarHost: NSHostingView<SidebarView>?
    private var workspaces: [PaneLayout.ID: TerminalWorkspaceView] = [:]
    private var paletteHost: NSView?
    private var searchHost: NSView?
    private var sidebarWidth: NSLayoutConstraint?
    private var peek: SidebarPeek?
    /// The peek's state before Settings covered the window.
    private var peekWasEnabled = false
    private lazy var switcher = SessionSwitcher(controller: self)
    private lazy var arrivalCard = ArrivalCard(container: container)
    lazy var fileViewer = FileViewer(container: container)
    lazy var filesColumn = FilesColumn { [weak self] path in self?.showFile(path) }
    let windowStyle = WindowStyle()
    let sidebarEditing = SidebarEditing()
    lazy var welcomePage = WelcomePage(container: container)
    lazy var settingsPage = SettingsPage(container: container)
    private(set) var sidebarStyle = SidebarStyle.derived(from: NSColor(white: 0.12, alpha: 1))

    static let sidebarWidth = SidebarView.width

    var focusedPane: TerminalSurfaceView? {
        guard let layout = manager.workspace.selectedLayout else { return nil }
        return manager.panes[layout.focusedSessionID]
    }

    private var selectedWorkspace: TerminalWorkspaceView? {
        manager.workspace.selectedLayout.flatMap { workspaces[$0.id] }
    }

    init(manager: SessionManager) {
        self.manager = manager
        let window = CalmWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1200, height: 760),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false,
        )
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isReleasedWhenClosed = false
        window.tabbingMode = .disallowed
        window.minSize = NSSize(width: 560, height: 320)
        window.setFrameAutosaveName("CalmMainWindow")
        super.init(window: window)
        window.delegate = self
        buildLayout()
        showSelectedLayout(animated: false)
        applyAppearance()
        switcher.install()
        NotificationCenter.default.addObserver(forName: .calmTerminalConfigDidChange, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.applyAppearance() }
        }
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("not supported")
    }

    // MARK: PaneLayout

    private func buildLayout() {
        guard let window else { return }
        // Layer-backed, so fades and slides run on Core Animation. Without layers AppKit falls
        // back to timer-driven animation, which never ran when started outside event handling
        // (e.g. `calm open`), leaving a new session's workspace at alpha 0.
        container.wantsLayer = true
        window.contentView = container
        let sidebar = NSHostingView(rootView: makeSidebar(style: sidebarStyle))
        // Sized by its width constraint alone and clipped as it slides (Motion.animateLayout).
        sidebar.sizingOptions = []
        sidebar.clipsToBounds = true
        sidebarHost = sidebar
        for view in [sidebar, mainArea] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(view)
        }
        let width = sidebar.widthAnchor.constraint(equalToConstant: Self.sidebarWidth)
        sidebarWidth = width
        let files = filesColumn.install(in: container, after: sidebar)
        NSLayoutConstraint.activate([
            sidebar.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            sidebar.topAnchor.constraint(equalTo: container.topAnchor),
            sidebar.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            width,
        ])
        windowStyle.install(mainArea: mainArea, after: files, in: container)
        container.layoutSubtreeIfNeeded()
        peek = SidebarPeek(container: container, width: Self.sidebarWidth) { [unowned self] in
            NSHostingView(rootView: makeSidebar(style: sidebarStyle))
        }
    }

    private func makeSidebar(style: SidebarStyle) -> SidebarView {
        SidebarView(
            manager: manager,
            style: style,
            onSelect: { [weak self] id in self?.select(id) },
            onClose: { [weak self] id in self?.requestCloseSession(id) },
            onNewSession: { [weak self] in self?.newSession() },
            onNewProject: { [weak self] in self?.chooseNewProject() },
            editing: sidebarEditing,
            actions: SidebarActions(
                rename: { [weak self] id, name in self?.rename(id, to: name) },
                resume: { [weak self] id in self?.resumeConversation(in: id) },
                fork: { [weak self] id, destination in self?.forkConversation(of: id, into: destination) },
                newScratchSession: { [weak self] in self?.newScratchSession() },
                search: { [weak self] in self?.toggleSearch() },
                newSessionIn: { [weak self] project in self?.newSession(in: project) },
                addProjects: { [weak self] urls in self?.addProjects(urls) },
                makeProject: { [weak self] id in self?.manager.makeProject(id) },
                move: { [weak self] id, project in self?.manager.move(id, to: project) },
                followFolder: { [weak self] id in self?.manager.followFolder(id) },
                keepScratch: { [weak self] id in self?.keepScratchAsProject(id) },
            ),
        )
    }

    func toggleSidebar() {
        guard let sidebarWidth else { return }
        let hidden = sidebarWidth.constant == 0
        peek?.isEnabled = !hidden
        Motion.animateLayout(of: container) {
            sidebarWidth.constant = hidden ? Self.sidebarWidth : 0
        }
    }

    /// Shows the selected layout's workspace, building its panes on first use, and hides the rest.
    func showSelectedLayout(animated: Bool) {
        updateWelcomePage()
        guard let layout = manager.workspace.selectedLayout else { return }
        let workspace = workspaces[layout.id] ?? makeWorkspace(for: layout)
        for (id, view) in workspaces {
            view.isHidden = id != layout.id
        }
        restorePaneVisibility()
        if animated {
            Motion.fadeIn(workspace, duration: 0.14)
        }
        if let pane = manager.panes[layout.focusedSessionID] {
            window?.makeFirstResponder(pane)
        }
        if filesColumn.isShown {
            filesColumn.model.follow(focusedProjectPath)
        }
        applyAppearance()
    }

    #if DEBUG
        func peekForTesting() {
            peek?.showForTesting()
        }

        /// Frames of the window's parts, for self-test logs.
        var layoutForTesting: String {
            let overlays = container.subviews.filter { $0 !== sidebarHost && $0 !== mainArea }.map { "\(type(of: $0)) \($0.frame)" }
            let background = focusedPane?.effectiveBackgroundColor ?? window?.backgroundColor ?? .clear
            let themed = TerminalTheme.chromeColors(matching: background) != nil
            let chrome = "terminal \(background.hexString), sidebar \(NSColor(sidebarStyle.background).hexString), "
                + "accent \(NSColor(sidebarStyle.attention).hexString), theme chrome \(themed)"
            let frames = "sidebar \(sidebarHost?.frame ?? .zero), main \(mainArea.frame), overlays \(overlays)"
            return "\(frames); \(chrome); welcome \(welcomePage.isShowing)"
        }
    #endif

    /// Only the selected layout's panes render; the rest are occluded.
    func restorePaneVisibility() {
        for (id, view) in workspaces {
            view.orderedPanes.forEach { $0.setVisible(id == manager.workspace.selectedLayoutID) }
        }
    }

    private func makeWorkspace(for layout: PaneLayout) -> TerminalWorkspaceView {
        let view = TerminalWorkspaceView()
        view.wantsLayer = true
        view.translatesAutoresizingMaskIntoConstraints = false
        mainArea.addSubview(view)
        NSLayoutConstraint.activate([
            view.leadingAnchor.constraint(equalTo: mainArea.leadingAnchor),
            view.trailingAnchor.constraint(equalTo: mainArea.trailingAnchor),
            view.topAnchor.constraint(equalTo: mainArea.topAnchor),
            view.bottomAnchor.constraint(equalTo: mainArea.bottomAnchor),
        ])
        var panes: [UUID: TerminalSurfaceView] = [:]
        for id in layout.tree.leaves {
            panes[id] = manager.pane(for: id, host: self)
        }
        view.restore(tree: layout.tree, panes: panes)
        workspaces[layout.id] = view
        return view
    }

    func showAndFocus() {
        if let window, Headless.isOn {
            Headless.present(window)
        } else {
            window?.makeKeyAndOrderFront(nil)
        }
        showSelectedLayout(animated: false)
    }

    // MARK: Sessions

    func select(_ id: Session.ID) {
        // Going to a session leaves Settings (a click on its "needs you", ⌃Tab, ⌘1…9, search).
        hideSettings()
        let previous = manager.workspace.selectedLayoutID
        let previousSession = manager.workspace.selectedLayout?.focusedSessionID
        if let previousSession, previousSession != id {
            arrivalCard.noteLeft(previousSession)
        }
        manager.select(id)
        showSelectedLayout(animated: previous != manager.workspace.selectedLayoutID)
        let sidebarShown = (sidebarWidth?.constant ?? 0) > 0
        if previousSession != id, arrivalCard.isWorthShowing(for: manager.workspace.session(id), sidebarShown: sidebarShown) {
            showArrivalCard()
        }
    }

    /// The arrival card for the focused session, if an agent runs there (⌘⇧I recalls it).
    func showArrivalCard() {
        guard let layout = manager.workspace.selectedLayout, let session = manager.workspace.session(layout.focusedSessionID),
              let pane = manager.panes[session.id]
        else { return }
        // Let the layout settle first so the card lands on the pane's final frame.
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.arrivalCard.show(for: session, over: pane, style: self.sidebarStyle)
            }
        }
    }

    func newSession(inheriting pane: TerminalSurfaceView? = nil) {
        hideSettings()
        let source = pane ?? focusedPane
        let (placement, directory) = placementAndFolder(
            from: source?.id ?? manager.workspace.selectedLayout?.focusedSessionID,
            pane: source,
        )
        manager.newSession(in: directory, placement: placement)
        showSelectedLayout(animated: true)
    }

    func selectSession(atPosition index: Int) -> Bool {
        let sessions = manager.orderedSessions
        guard sessions.indices.contains(index) else { return false }
        select(sessions[index].id)
        return true
    }

    func requestCloseSession(_ id: Session.ID) {
        let close = { [weak self] in
            guard let self else { return }
            if let pane = manager.panes[id] {
                surfaceRequestsClose(pane, needsConfirm: pane.needsConfirmQuit)
            } else {
                closeSession(id)
            }
        }
        if let session = manager.workspace.session(id), session.isScratch {
            requestCloseScratch(session, then: close)
        } else {
            close()
        }
    }

    private func closeSession(_ id: Session.ID) {
        guard let layout = manager.workspace.layout(containing: id) else { return }
        let workspace = workspaces[layout.id]
        if let pane = manager.panes[id] {
            workspace?.detach(pane)
        }
        manager.closeSession(id)
        if manager.workspace.layout(containing: layout.focusedSessionID) == nil || workspace?.orderedPanes.isEmpty == true {
            workspace?.removeFromSuperview()
            workspaces[layout.id] = nil
        }
        showSelectedLayout(animated: true)
    }

    // MARK: Appearance

    func applyAppearance() {
        guard let window else { return }
        let background = focusedPane?.effectiveBackgroundColor
            ?? TerminalEngine.shared.config?.backgroundColor
            ?? NSColor(white: 0.15, alpha: 1)
        var style = SidebarStyle.derived(from: background, theme: TerminalTheme.chromeColors(matching: background)).contrasted()
        // The title strip takes the color the terminal drew along its top, so a full-screen app with
        // its own background (OpenCode) meets it without a seam; the sidebar keeps the theme's.
        window.backgroundColor = windowStyle.apply(
            manager.settings, style: &style, terminalBackground: focusedPane?.topEdgeColor ?? background,
            mainArea: mainArea, container: container,
        )
        fileViewer.cornerRadius = windowStyle.cornerRadius
        sidebarStyle = style
        filesColumn.model.style = style
        window.appearance = NSAppearance(named: style.isDark ? .darkAqua : .aqua)
        sidebarHost?.rootView = makeSidebar(style: style)
        let strength = AccessibilitySettings.increaseContrast ? 2.5 : 1
        let divider = style.isDark ? NSColor(white: 1, alpha: 0.08 * strength) : NSColor(white: 0, alpha: 0.1 * strength)
        workspaces.values.forEach { $0.dividerColor = divider }
        // The welcome page and Settings take the chrome's colors too (they settle after they first show).
        updateWelcomePage()
        if settingsPage.isShowing {
            settingsPage.restyle(style: style, background: background, actions: settingsActions)
        }
    }

    // MARK: Command palette

    var isShowingCommandPalette: Bool {
        paletteHost != nil
    }

    func toggleCommandPalette() {
        if isShowingCommandPalette {
            hideCommandPalette()
        } else {
            showCommandPalette()
        }
    }

    private func showCommandPalette() {
        guard paletteHost == nil else { return }
        let commands = (focusedPane?.config ?? TerminalEngine.shared.config)?.commands ?? []
        let isDark = window?.appearance?.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let view = CommandPaletteView(
            commands: commands,
            isDark: isDark,
            onRun: { [weak self] command in
                self?.hideCommandPalette()
                self?.focusedPane?.perform(command.action)
            },
            onDismiss: { [weak self] in self?.hideCommandPalette() },
        )
        let host = NSHostingView(rootView: view)
        host.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(host)
        NSLayoutConstraint.activate([
            host.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            host.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            host.topAnchor.constraint(equalTo: container.topAnchor),
            host.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        paletteHost = host
        window?.makeFirstResponder(host)
    }

    // MARK: Search

    /// ⌘K: search every session (FEATURES.md → F7).
    func toggleSearch(query: String = "") {
        if searchHost != nil {
            hideSearch()
            return
        }
        let project = manager.workspace.selectedLayout
            .flatMap { manager.workspace.session($0.focusedSessionID) }
            .flatMap { manager.workspace.project($0.projectID)?.path }
        let isDark = window?.appearance?.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let view = SearchPanelView(
            model: SearchPanelModel(query: query, currentProject: project),
            isDark: isDark,
            onOpen: { [weak self] item in self?.openSearchResult(item) },
            onDismiss: { [weak self] in self?.hideSearch() },
        )
        let host = NSHostingView(rootView: view)
        host.frame = container.bounds
        host.autoresizingMask = [.width, .height]
        container.addSubview(host, positioned: .above, relativeTo: nil)
        searchHost = host
        Motion.fadeIn(host, duration: 0.12)
        window?.makeFirstResponder(host)
    }

    private func hideSearch() {
        guard let host = searchHost else { return }
        searchHost = nil
        Motion.fadeOutAndRemove(host, duration: 0.1)
        if let focusedPane {
            window?.makeFirstResponder(focusedPane)
        }
    }

    /// Goes to the session if it's open; otherwise resumes it in its folder, in a new session.
    /// A conversation whose transcript the agent deleted can't be resumed: it gets a plain new
    /// session in its folder.
    func openSearchResult(_ item: SearchPanelModel.Item) {
        hideSearch()
        if let id = item.openSession {
            select(id)
            return
        }
        let result = item.result
        let command = result.transcriptDeleted ? nil : Agents.adapter(for: result.agent)?
            .resumeCommand(agentSessionID: result.agentSessionID, transcriptPath: result.transcriptPath)
        guard command != nil || result.transcriptDeleted else { return }
        var directory = FileManager.default.homeDirectoryForCurrentUser.path
        if let folder = result.directory, FileManager.default.fileExists(atPath: folder) {
            directory = folder
        }
        hideSettings()
        let session = manager.newSession(in: directory)
        showSelectedLayout(animated: true)
        if let command {
            runAgentCommand(command, in: manager.panes[session.id])
        }
    }

    private func hideCommandPalette() {
        guard let host = paletteHost else { return }
        paletteHost = nil
        host.removeFromSuperview()
        if let focusedPane {
            window?.makeFirstResponder(focusedPane)
        }
    }

    // MARK: TerminalSurfaceHost

    func surfaceRequestsNewTab(_ view: TerminalSurfaceView) {
        newSession(inheriting: view)
    }

    func surface(_ view: TerminalSurfaceView, requestsSplit splitDirection: SplitTree<UUID>.Direction) {
        split(view, direction: splitDirection)
    }

    /// A new session split off `view`'s, in its folder; returns its pane.
    @discardableResult
    func split(_ view: TerminalSurfaceView, direction splitDirection: SplitTree<UUID>.Direction) -> TerminalSurfaceView? {
        guard let layout = manager.workspace.layout(containing: view.id), let workspace = workspaces[layout.id] else { return nil }
        let (placement, directory) = placementAndFolder(from: view.id, pane: view)
        guard let session = manager.splitSession(view.id, direction: splitDirection, in: directory, placement: placement),
              let pane = manager.pane(for: session.id, host: self)
        else { return nil }
        workspace.split(view, direction: splitDirection, with: pane)
        window?.makeFirstResponder(pane)
        return pane
    }

    func surface(_ view: TerminalSurfaceView, requestsFocus focusTarget: PaneFocusTarget) -> Bool {
        guard let workspace = selectedWorkspace else { return false }
        let target: TerminalSurfaceView? = switch focusTarget {
        case .previous: workspace.cycle(from: view, forward: false)
        case .next: workspace.cycle(from: view, forward: true)
        case let .toward(direction): workspace.neighbor(of: view, toward: direction)
        }
        guard let target else { return false }
        window?.makeFirstResponder(target)
        return true
    }

    func surface(_ view: TerminalSurfaceView, requestsResize direction: SplitTree<UUID>.Direction, byPoints amount: CGFloat) -> Bool {
        guard let layout = manager.workspace.layout(containing: view.id), let workspace = workspaces[layout.id] else { return false }
        let resized = workspace.resize(view, direction: direction, byPoints: amount)
        if resized, let tree = workspace.tree {
            manager.updateTree(layout.id, tree)
        }
        return resized
    }

    func surfaceRequestsEqualize(_ view: TerminalSurfaceView) -> Bool {
        guard let layout = manager.workspace.layout(containing: view.id), let workspace = workspaces[layout.id],
              workspace.hasSplits
        else { return false }
        workspace.equalize()
        if let tree = workspace.tree {
            manager.updateTree(layout.id, tree)
        }
        return true
    }

    func surfaceRequestsZoomToggle(_ view: TerminalSurfaceView) -> Bool {
        selectedWorkspace?.toggleZoom(view) ?? false
    }

    func surface(_: TerminalSurfaceView, requestsSession target: SessionTarget) -> Bool {
        let sessions = manager.orderedSessions
        guard sessions.count > 1, let current = focusedPane.flatMap({ pane in sessions.firstIndex { $0.id == pane.id } }),
              let index = target.index(from: current, count: sessions.count)
        else { return false }
        return selectSession(atPosition: index)
    }

    func surfaceRequestsCloseTab(_ view: TerminalSurfaceView) {
        requestCloseSession(view.id)
    }

    func surfaceRequestsCloseWindow(_: TerminalSurfaceView) {
        window?.performClose(nil)
    }

    func surfaceRequestsClose(_ view: TerminalSurfaceView, needsConfirm: Bool) {
        guard needsConfirm, let window else {
            closeSession(view.id)
            return
        }
        let alert = NSAlert()
        alert.messageText = "Close this session?"
        alert.informativeText = "A process is still running in it. Closing the session ends it."
        alert.addButton(withTitle: "Close")
        alert.addButton(withTitle: "Cancel")
        alert.beginSheetModal(for: window) { [weak self] response in
            guard response == .alertFirstButtonReturn else { return }
            MainActor.assumeIsolated { self?.closeSession(view.id) }
        }
    }

    func surfaceChildExited(_ view: TerminalSurfaceView) {
        // A shell that dies right after starting means persistence is broken (not a user
        // exit): stop using it rather than opening shell after failing shell.
        if Date().timeIntervalSince(view.createdAt) < 2, manager.persistenceEnabled {
            manager.persistenceEnabled = false
            FileHandle.standardError.write(Data("calm: persistent shell exited at once; using plain shells\n".utf8))
        }
        // The shell (or the zmx session holding it) ended: the session is over.
        closeSession(view.id)
    }

    func surfaceTitleDidChange(_ view: TerminalSurfaceView) {
        manager.titleChanged(view.id, view.title)
    }

    func surfaceWorkingDirectoryDidChange(_ view: TerminalSurfaceView) {
        guard let directory = view.workingDirectory else { return }
        manager.workingDirectoryChanged(view.id, directory)
    }

    func surface(_ view: TerminalSurfaceView, didSignal signal: TerminalSignal) {
        manager.terminalSignal(view.id, signal)
    }

    func surfaceDidBecomeFocused(_ view: TerminalSurfaceView) {
        manager.setFocused(view.id)
        applyAppearance()
    }

    func surfaceAppearanceDidChange(_ view: TerminalSurfaceView) {
        if view === focusedPane {
            applyAppearance()
        }
    }

    func surfaceRequestsCommandPalette(_: TerminalSurfaceView) {
        toggleCommandPalette()
    }

    // MARK: NSWindowDelegate

    func windowDidBecomeKey(_: Notification) {
        if let focusedPane, window?.firstResponder !== focusedPane, paletteHost == nil, !settingsPage.isShowing {
            window?.makeFirstResponder(focusedPane)
        }
    }

    func windowDidResignKey(_: Notification) {
        switcher.cancel()
    }

    func windowWillClose(_: Notification) {
        switcher.uninstall()
        NSApp.terminate(nil)
    }
}

// MARK: Settings

/// Settings (FEATURES.md → F14): the page that takes the whole window.
extension MainWindowController {
    /// ⌘, (FEATURES.md → F14): Settings takes the whole window; ⌘, again or esc goes back.
    func toggleSettings() {
        if settingsPage.isShowing {
            hideSettings()
        } else {
            showSettings()
        }
    }

    /// Opens Settings at `section` (else where it was left); Calm → Agents… opens Agents.
    func showSettings(_ section: SettingsPage.Section? = nil) {
        if !settingsPage.isShowing {
            // The hidden sidebar's peek would slide the sessions over the page.
            peekWasEnabled = peek?.isEnabled ?? false
            peek?.isEnabled = false
        }
        let background = focusedPane?.effectiveBackgroundColor
            ?? TerminalEngine.shared.config?.backgroundColor
            ?? NSColor(white: 0.15, alpha: 1)
        settingsPage.show(section, style: sidebarStyle, background: background, actions: settingsActions)
    }

    func hideSettings() {
        guard settingsPage.isShowing else { return }
        settingsPage.hide()
        peek?.isEnabled = peekWasEnabled
        if let focusedPane {
            window?.makeFirstResponder(focusedPane)
        }
    }

    var settingsActions: SettingsView.Actions {
        SettingsView.Actions(
            close: { [weak self] in self?.hideSettings() },
            goToSession: { [weak self] id in self?.select(id) },
            reload: { [weak self] in
                TerminalEngine.shared.reloadConfig(soft: false)
                self?.settingsPage.refresh()
                self?.applyAppearance()
            },
        )
    }
}

/// Keeps the main window and answers app-level engine requests.
@MainActor
final class TerminalWindowManager: TerminalEngineDelegate {
    static let shared = TerminalWindowManager()
    private(set) var mainController: MainWindowController?

    var focusedController: MainWindowController? {
        mainController
    }

    var controllers: [MainWindowController] {
        mainController.map { [$0] } ?? []
    }

    @discardableResult
    func openMainWindow() -> MainWindowController {
        if let mainController {
            mainController.showAndFocus()
            return mainController
        }
        let controller = MainWindowController(manager: SessionManager.shared)
        mainController = controller
        if controller.window?.frameAutosaveName.isEmpty == false, controller.window?.setFrameUsingName("CalmMainWindow") != true {
            controller.window?.center()
        }
        controller.showAndFocus()
        return controller
    }

    // MARK: TerminalEngineDelegate

    func engineRequestsNewWindow(inheriting surface: TerminalSurfaceView?) {
        // One calm window: a "new window" is a new session.
        openMainWindow().newSession(inheriting: surface)
    }

    func engineRequestsQuit() {
        NSApp.terminate(nil)
    }
}

import AppKit
import CalmAgents
import CalmModel
import SwiftUI

/// The main window: the session sidebar beside the terminal area. The terminal area keeps
/// one workspace view per layout and shows the selected one.
@MainActor
final class MainWindowController: NSWindowController, NSWindowDelegate, TerminalSurfaceHost {
    let manager: SessionManager
    private let container = NSView()
    private let mainArea = NSView()
    private var sidebarHost: NSHostingView<SidebarView>?
    private var workspaces: [PaneLayout.ID: TerminalWorkspaceView] = [:]
    private var paletteHost: NSView?
    private var agentsHost: NSView?
    private var searchHost: NSView?
    private var sidebarWidth: NSLayoutConstraint?
    private var peek: SidebarPeek?
    private lazy var switcher = SessionSwitcher(controller: self)
    private lazy var arrivalCard = ArrivalCard(container: container)
    private(set) var sidebarStyle = SidebarStyle.derived(from: NSColor(white: 0.12, alpha: 1))

    static let sidebarWidth: CGFloat = 280

    var focusedPane: TerminalSurfaceView? {
        guard let layout = manager.workspace.selectedLayout else { return nil }
        return manager.panes[layout.focusedSessionID]
    }

    private var selectedWorkspace: TerminalWorkspaceView? {
        manager.workspace.selectedLayout.flatMap { workspaces[$0.id] }
    }

    init(manager: SessionManager) {
        self.manager = manager
        let window = NSWindow(
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
        sidebarHost = sidebar
        for view in [sidebar, mainArea] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(view)
        }
        let width = sidebar.widthAnchor.constraint(equalToConstant: Self.sidebarWidth)
        sidebarWidth = width
        NSLayoutConstraint.activate([
            sidebar.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            sidebar.topAnchor.constraint(equalTo: container.topAnchor),
            sidebar.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            width,
            mainArea.leadingAnchor.constraint(equalTo: sidebar.trailingAnchor),
            mainArea.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            mainArea.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            // Leave the title bar strip above the terminal.
            mainArea.topAnchor.constraint(equalTo: container.topAnchor, constant: 30),
        ])
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
        )
    }

    func toggleSidebar() {
        guard let sidebarWidth else { return }
        let hidden = sidebarWidth.constant == 0
        peek?.isEnabled = !hidden
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Motion.duration(0.2)
            context.allowsImplicitAnimation = true
            sidebarWidth.animator().constant = hidden ? Self.sidebarWidth : 0
            container.layoutSubtreeIfNeeded()
        }
    }

    /// Shows the selected layout's workspace, building its panes on first use, and hides the rest.
    func showSelectedLayout(animated: Bool) {
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
        applyAppearance()
    }

    #if DEBUG
        func peekForTesting() {
            peek?.showForTesting()
        }

        /// Frames of the window's parts, for self-test logs.
        var layoutForTesting: String {
            let overlays = container.subviews.filter { $0 !== sidebarHost && $0 !== mainArea }.map { "\(type(of: $0)) \($0.frame)" }
            return "sidebar \(sidebarHost?.frame ?? .zero), main \(mainArea.frame), overlays \(overlays)"
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
        let previous = manager.workspace.selectedLayoutID
        let previousSession = manager.workspace.selectedLayout?.focusedSessionID
        manager.select(id)
        showSelectedLayout(animated: previous != manager.workspace.selectedLayoutID)
        if previousSession != id {
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
        let directory = (pane ?? focusedPane)?.workingDirectory
            ?? manager.workspace.selectedLayout.flatMap { manager.workspace.session($0.focusedSessionID)?.workingDirectory }
            ?? FileManager.default.homeDirectoryForCurrentUser.path
        manager.newSession(in: directory)
        showSelectedLayout(animated: true)
    }

    func selectSession(atPosition index: Int) -> Bool {
        let sessions = manager.orderedSessions
        guard sessions.indices.contains(index) else { return false }
        select(sessions[index].id)
        return true
    }

    private func requestCloseSession(_ id: Session.ID) {
        if let pane = manager.panes[id] {
            surfaceRequestsClose(pane, needsConfirm: pane.needsConfirmQuit)
        } else {
            closeSession(id)
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
        if manager.workspace.sessions.isEmpty {
            manager.newSession(in: FileManager.default.homeDirectoryForCurrentUser.path)
        }
        showSelectedLayout(animated: true)
    }

    private func chooseNewProject() {
        guard let window else { return }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        panel.prompt = "Add Project"
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK else { return }
            MainActor.assumeIsolated {
                panel.urls.forEach { self?.manager.addProject(path: $0.path) }
            }
        }
    }

    // MARK: Appearance

    func applyAppearance() {
        guard let window else { return }
        let background = focusedPane?.effectiveBackgroundColor
            ?? TerminalEngine.shared.config?.backgroundColor
            ?? NSColor(white: 0.15, alpha: 1)
        window.backgroundColor = background
        let style = SidebarStyle.derived(from: background)
        sidebarStyle = style
        window.appearance = NSAppearance(named: style.isDark ? .darkAqua : .aqua)
        sidebarHost?.rootView = makeSidebar(style: style)
        let divider = style.isDark ? NSColor(white: 1, alpha: 0.08) : NSColor(white: 0, alpha: 0.1)
        workspaces.values.forEach { $0.dividerColor = divider }
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
    func openSearchResult(_ item: SearchPanelModel.Item) {
        hideSearch()
        if let id = item.openSession {
            select(id)
            return
        }
        let result = item.result
        guard let command = Agents.adapter(for: result.agent)?
            .resumeCommand(agentSessionID: result.agentSessionID, transcriptPath: result.transcriptPath)
        else { return }
        var directory = FileManager.default.homeDirectoryForCurrentUser.path
        if let folder = result.directory, FileManager.default.fileExists(atPath: folder) {
            directory = folder
        }
        let session = manager.newSession(in: directory)
        showSelectedLayout(animated: true)
        manager.panes[session.id]?.run(command)
    }

    // MARK: Agents panel

    /// Calm → Agents…, and once at first launch.
    func showAgentsPanel() {
        guard agentsHost == nil else { return }
        let view = AgentsPanelView(model: AgentsPanelModel(), style: sidebarStyle) { [weak self] in self?.hideAgentsPanel() }
        let host = NSHostingView(rootView: view)
        host.frame = container.bounds
        host.autoresizingMask = [.width, .height]
        container.addSubview(host, positioned: .above, relativeTo: nil)
        agentsHost = host
        Motion.fadeIn(host, duration: 0.15)
        window?.makeFirstResponder(host)
    }

    private func hideAgentsPanel() {
        guard let host = agentsHost else { return }
        agentsHost = nil
        Motion.fadeOutAndRemove(host, duration: 0.12)
        if let focusedPane {
            window?.makeFirstResponder(focusedPane)
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
        guard let layout = manager.workspace.layout(containing: view.id), let workspace = workspaces[layout.id] else { return }
        let directory = view.workingDirectory ?? manager.workspace.session(view.id)?.workingDirectory
            ?? FileManager.default.homeDirectoryForCurrentUser.path
        guard let session = manager.splitSession(view.id, direction: splitDirection, in: directory),
              let pane = manager.pane(for: session.id, host: self)
        else { return }
        workspace.split(view, direction: splitDirection, with: pane)
        window?.makeFirstResponder(pane)
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
        if let focusedPane, window?.firstResponder !== focusedPane, paletteHost == nil {
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
        // First launch: say how each agent connects, once (M3.11).
        let shownKey = "CalmAgentsPanelShown"
        if !Headless.isOn, !UserDefaults.standard.bool(forKey: shownKey) {
            UserDefaults.standard.set(true, forKey: shownKey)
            controller.showAgentsPanel()
        }
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

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
    private(set) var sidebarHost: NSHostingView<SidebarView>?
    var titleHost: SessionTitleHost?
    private var workspaces: [PaneLayout.ID: TerminalWorkspaceView] = [:]
    /// ⌘P's palette while it's up (MainWindowController+Palette).
    var paletteHost: NSView?
    /// ⌘K's panel and model while it's up (MainWindowController+Search).
    var searchHost: NSView?
    var searchModel: SearchModel?
    private(set) var sidebarWidth: NSLayoutConstraint?
    private(set) var peek: SidebarPeek?
    /// The peek's state before Settings covered the window.
    private var peekWasEnabled = false
    private lazy var switcher = SessionSwitcher(controller: self)
    private lazy var arrivalCard = ArrivalCard(container: container)
    lazy var closePrompt = ClosePrompt(container: container)
    lazy var linkTag = LinkTag(container: container)
    lazy var fileViewer = FileViewer(container: container)
    lazy var filesColumn = FilesColumn { [weak self] path in self?.showFile(path) }
    let windowStyle = WindowStyle()
    let sidebarEditing = SidebarEditing()
    lazy var welcomePage = WelcomePage(container: container)
    lazy var noSessionPage = NoSessionPage(mainArea: mainArea)
    lazy var settingsPage = SettingsPage(container: container)
    private(set) var sidebarStyle = SidebarStyle.derived(from: NSColor(white: 0.12, alpha: 1))
    /// Off until the saved size is back, so restoring it isn't taken for the user leaving the
    /// filled or full-screen state that is about to be restored (see `restoreFrame`).
    var tracksWindowState = false

    /// The name AppKit saves the window's frame under.
    static let frameName = "CalmMainWindow"

    static var sidebarWidth: CGFloat {
        SidebarView.width
    }

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
        window.setFrameAutosaveName(Self.frameName)
        super.init(window: window)
        window.delegate = self
        // The saved frame, filled again if it was left filled, before anything is laid out: the
        // first panes start at their size in it, and the sidebar's first layout isn't in a
        // smaller window (in the saved windowed frame, Shrink cards to fit stepped the cards
        // down, and they didn't all come back in the filled window).
        restoreFrame()
        buildLayout()
        showSelectedLayout(animated: false)
        applyAppearance()
        switcher.install()
        NotificationCenter.default.addObserver(forName: .calmTerminalConfigDidChange, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                // Settings shows what the reloaded files now say (Calm → Reload Configuration).
                if self?.settingsPage.isShowing == true {
                    self?.settingsPage.refresh()
                }
                self?.applyAppearance()
            }
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
        installTitle()
        container.layoutSubtreeIfNeeded()
        peek = SidebarPeek(container: container, width: Self.sidebarWidth) { [unowned self] in
            NSHostingView(rootView: makeSidebar(style: sidebarStyle))
        }
    }

    func toggleSidebar() {
        guard let sidebarWidth else { return }
        let hidden = sidebarWidth.constant == 0
        peek?.isEnabled = !hidden
        Motion.animateLayout(of: container) {
            sidebarWidth.constant = hidden ? Self.sidebarWidth : 0
        }
        // With no session chosen, the page carries the ways to start while the sidebar is away.
        updateNoSessionPage()
    }

    /// Shows the selected layout's workspace, building its panes on first use, and hides the rest.
    func showSelectedLayout(animated: Bool) {
        closePrompt.dismiss()
        updatePages()
        // A new, reopened or closed-into session isn't the one a file was opened over.
        closeViewer(unlessOver: manager.workspace.selectedLayout?.focusedSessionID)
        guard let layout = manager.workspace.selectedLayout else {
            showNoSession()
            return
        }
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
            filesColumn.model.follow(focusedProjectPath, isScratch: focusedSession?.isScratch == true)
        }
        applyAppearance()
    }

    /// No session is selected: with none open the welcome page covers the window, and when the
    /// one on screen was closed the main area shows what waits for a look, or search, for the user
    /// to choose from, rather than Calm choosing for them (`NoSessionPage`). No pane takes the keyboard.
    private func showNoSession() {
        workspaces.values.forEach { $0.isHidden = true }
        restorePaneVisibility()
        if filesColumn.isShown {
            filesColumn.model.follow(nil)
        }
        applyAppearance()
    }

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
        // Laid out before its panes exist, so each starts at its size: a program reattached
        // through zmx (Claude Code after a restart) otherwise first got a placeholder's 41×13,
        // then the real size, and its screen came back with most of its footer blank.
        window?.contentView?.layoutSubtreeIfNeeded()
        view.restore(tree: layout.tree) { manager.pane(for: $0, host: self, size: $1) }
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
        // Going to a session leaves Settings (a click on its "needs you", ⌃Tab, ⌘1…9, search),
        // and a file open over the one you were in.
        hideSettings()
        closeViewer()
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

    /// Chooses no session, so the main area shows what waits for a look, or search (`NoSessionPage`),
    /// as when the session in front is closed. Nothing closes; every session keeps running.
    func goToWelcomePage() {
        guard let left = manager.workspace.selectedLayout?.focusedSessionID else { return }
        hideSettings()
        closeViewer()
        arrivalCard.noteLeft(left)
        manager.deselect()
        showSelectedLayout(animated: true)
    }

    /// Gives every pane of the split on screen a session of its own in the sidebar. Nothing
    /// closes: each pane keeps its shell and moves to a workspace view of its own.
    func unsplit() {
        guard let layout = manager.workspace.selectedLayout, layout.tree.leaves.count > 1 else { return }
        let old = workspaces[layout.id]
        let apart = manager.unsplit(layout.id)
        // Each new layout gets its view at once, which moves its pane over. A pane in no view
        // would sit loose until its session was chosen. The view of the layout that held them
        // all goes last, empty.
        for layout in apart {
            workspaces[layout.id] = nil
            _ = makeWorkspace(for: layout)
        }
        old?.removeFromSuperview()
        showSelectedLayout(animated: false)
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

    func requestCloseSession(_ id: Session.ID) {
        let close = { [weak self] in
            guard let self else { return }
            confirmClose(id, processRunning: manager.panes[id]?.needsConfirmQuit ?? false)
        }
        if let session = manager.workspace.session(id), session.isScratch {
            requestCloseScratch(session, then: close)
        } else {
            close()
        }
    }

    private func closeSession(_ id: Session.ID) {
        guard let layout = manager.workspace.layout(containing: id) else { return }
        closePrompt.dismiss()
        let workspace = workspaces[layout.id]
        if let pane = manager.panes[id] {
            workspace?.detach(pane)
        }
        let shown = manager.workspace.selectedLayoutID
        manager.closeSession(id)
        // The workspace goes with its layout. (`layout` is the copy from before the close, whose
        // focused session is the one just closed when it was the focused pane: asking about it
        // rebuilt the whole workspace after every such close, and nothing could animate.)
        if !manager.workspace.layouts.contains(where: { $0.id == layout.id }) || workspace?.orderedPanes.isEmpty == true {
            workspace?.removeFromSuperview()
            workspaces[layout.id] = nil
        }
        // Closing a pane of the split on screen leaves its layout in place, and the panes fold
        // and grow themselves; fading the whole area in would blink over that.
        showSelectedLayout(animated: manager.workspace.selectedLayoutID != shown)
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
        // The interface size sets the sidebar's width (a hidden sidebar stays hidden).
        if let sidebarWidth, sidebarWidth.constant > 0, sidebarWidth.constant != Self.sidebarWidth {
            sidebarWidth.constant = Self.sidebarWidth
        }
        peek?.width = Self.sidebarWidth
        filesColumn.updateWidth()
        filesColumn.model.style = style
        window.appearance = NSAppearance(named: style.isDark ? .darkAqua : .aqua)
        sidebarHost?.rootView = makeSidebar(style: style)
        titleHost?.rootView = makeTitle(style: style)
        let strength = AccessibilitySettings.increaseContrast ? 2.5 : 1
        let divider = style.isDark ? NSColor(white: 1, alpha: 0.08 * strength) : NSColor(white: 0, alpha: 0.1 * strength)
        workspaces.values.forEach { $0.dividerColor = divider }
        updateDim()
        // The welcome page, the main area's page and Settings take the chrome's colors too (they
        // settle after they first show).
        updatePages()
        if settingsPage.isShowing {
            settingsPage.restyle(style: style, background: background, actions: settingsActions)
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

    /// ⌘W (Close Session, or the user's own close_surface binding).
    func surfaceRequestsClose(_ view: TerminalSurfaceView, needsConfirm: Bool) {
        // A confirmation already up takes the key; another ⌘W doesn't stack a second one. (On the
        // pane's question it takes the question back: ClosePrompt sees the key first, this covers
        // a close that arrives another way.)
        traceFocus("close requested", view)
        guard window?.attachedSheet == nil, !closePrompt.isShowing else { return closePrompt.dismiss() }
        // ⌘W closes what's in front first: Settings, search or a file, never the session behind it.
        if settingsPage.isShowing {
            hideSettings()
        } else if searchHost != nil {
            hideSearch()
        } else if fileViewer.isShowing {
            fileViewer.close()
        } else {
            confirmClose(view.id, processRunning: needsConfirm)
        }
    }

    /// Closes a session, asking first while something runs in it. libghostty can't see an
    /// agent inside a persistent shell (zmx is the pane's process), so a running agent always asks.
    private func confirmClose(_ id: Session.ID, processRunning: Bool) {
        let agent = manager.workspace.session(id)?.agent?.kind
        guard processRunning || agent != nil, let window else {
            closeSession(id)
            return
        }
        // In a split the question sits on the pane it is about: a sheet on the window says what
        // would end, not which pane it is (UIUX.md → Split panes).
        if let workspace = selectedWorkspace, let pane = workspace.askablePane(id) {
            closePrompt.ask(about: pane, in: workspace, agent: agent, style: sidebarStyle) { [weak self] in
                self?.closeSession(id)
            }
            return
        }
        let alert = NSAlert()
        alert.messageText = "Close this session?"
        alert.informativeText = agent.map { "\($0.displayName) is running in it. Closing the session ends it." }
            ?? "A process is still running in it. Closing the session ends it."
        alert.addButton(withTitle: "Close")
        alert.addButton(withTitle: "Cancel")
        alert.beginSheetModal(for: window) { [weak self] response in
            guard response == .alertFirstButtonReturn else { return }
            MainActor.assumeIsolated { self?.closeSession(id) }
        }
    }

    func surfaceChildExited(_ view: TerminalSurfaceView) {
        // A session Calm already closed (its pane is gone or replaced) isn't a shell that failed.
        guard manager.panes[view.id] === view else { return }
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
        // The question is about a pane, so focus arriving anywhere ends it. A click that focuses
        // a pane is consumed by that pane's own monitor, which the question never hears: it used
        // to stay up over the old pane, with its ⌘W swallowed, so the new pane couldn't be closed.
        closePrompt.dismiss()
        traceFocus("focus arrived", view)
        manager.setFocused(view.id)
        applyAppearance()
    }

    func surfaceAppearanceDidChange(_ view: TerminalSurfaceView) {
        if view === focusedPane {
            applyAppearance()
        } else {
            // A receding pane's veil is the color it has behind its text.
            updateDim()
        }
    }

    /// Tells each workspace which pane its layout's focus is on, so the others recede, and has
    /// the veils take the panes' current colors.
    func updateDim() {
        for (id, workspace) in workspaces {
            workspace.setFocused(manager.workspace.layouts.first { $0.id == id }?.focusedSessionID)
            workspace.refreshVeils(animated: true)
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
        refocus()
    }

    var settingsActions: SettingsView.Actions {
        SettingsView.Actions(
            close: { [weak self] in self?.hideSettings() },
        )
    }
}

import AppKit
import CalmModel
import GhosttyKit

/// One window (or native tab) holding a workspace of split panes.
@MainActor
final class TerminalWindowController: NSWindowController, NSWindowDelegate, TerminalSurfaceHost {
    let workspace = TerminalWorkspaceView()
    private(set) weak var focusedPane: TerminalSurfaceView?
    var onClose: ((TerminalWindowController) -> Void)?

    init(options: TerminalSurfaceOptions) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1000, height: 660),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false,
        )
        window.title = "Calm"
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.tabbingMode = .preferred
        window.tabbingIdentifier = "calm.terminal"
        window.minSize = NSSize(width: 360, height: 220)
        super.init(window: window)
        window.delegate = self
        window.contentView = workspace

        let pane = makePane(options)
        workspace.setRoot(pane)
        focusedPane = pane
        applyAppearance()

        NotificationCenter.default.addObserver(
            forName: .calmTerminalConfigDidChange, object: nil, queue: .main,
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.applyAppearance() }
        }
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("not supported")
    }

    private func makePane(_ options: TerminalSurfaceOptions) -> TerminalSurfaceView {
        let pane = TerminalSurfaceView(options: options)
        pane.host = self
        return pane
    }

    func showAndFocus() {
        window?.makeKeyAndOrderFront(nil)
        if let focusedPane {
            focus(focusedPane)
        }
    }

    func focus(_ pane: TerminalSurfaceView) {
        focusedPane = pane
        window?.makeFirstResponder(pane)
        updateTitle()
    }

    // MARK: Command palette

    func toggleCommandPalette() {}

    // MARK: Appearance

    private func applyAppearance() {
        guard let window else { return }
        let background = focusedPane?.effectiveBackgroundColor
            ?? TerminalEngine.shared.config?.backgroundColor
            ?? NSColor(white: 0.15, alpha: 1)
        window.backgroundColor = background
        window.isOpaque = true
        let isDark = (background.usingColorSpace(.sRGB)?.brightnessComponent ?? 0) < 0.5
        window.appearance = NSAppearance(named: isDark ? .darkAqua : .aqua)
        workspace.dividerColor = isDark ? NSColor(white: 1, alpha: 0.08) : NSColor(white: 0, alpha: 0.1)
    }

    private func updateTitle() {
        let title = focusedPane?.title ?? ""
        window?.title = title.isEmpty ? "Calm" : title
        window?.subtitle = ""
    }

    // MARK: TerminalSurfaceHost

    func surfaceRequestsNewTab(_ view: TerminalSurfaceView) {
        let controller = TerminalWindowManager.shared.makeController(
            options: .inheriting(from: view, context: GHOSTTY_SURFACE_CONTEXT_TAB),
        )
        if let window, let newWindow = controller.window {
            window.addTabbedWindow(newWindow, ordered: .above)
        }
        controller.showAndFocus()
    }

    func surface(_ view: TerminalSurfaceView, requestsSplit direction: ghostty_action_split_direction_e) {
        let newPane = makePane(.inheriting(from: view, context: GHOSTTY_SURFACE_CONTEXT_SPLIT))
        let splitDirection: SplitTree<UUID>.Direction = switch direction {
        case GHOSTTY_SPLIT_DIRECTION_LEFT: .left
        case GHOSTTY_SPLIT_DIRECTION_UP: .up
        case GHOSTTY_SPLIT_DIRECTION_DOWN: .down
        default: .right
        }
        workspace.split(view, direction: splitDirection, with: newPane)
        focus(newPane)
    }

    func surface(_ view: TerminalSurfaceView, requestsFocus direction: ghostty_action_goto_split_e) -> Bool {
        let target: TerminalSurfaceView? = switch direction {
        case GHOSTTY_GOTO_SPLIT_PREVIOUS: workspace.cycle(from: view, forward: false)
        case GHOSTTY_GOTO_SPLIT_NEXT: workspace.cycle(from: view, forward: true)
        case GHOSTTY_GOTO_SPLIT_LEFT: workspace.neighbor(of: view, toward: .left)
        case GHOSTTY_GOTO_SPLIT_RIGHT: workspace.neighbor(of: view, toward: .right)
        case GHOSTTY_GOTO_SPLIT_UP: workspace.neighbor(of: view, toward: .up)
        case GHOSTTY_GOTO_SPLIT_DOWN: workspace.neighbor(of: view, toward: .down)
        default: nil
        }
        guard let target else { return false }
        focus(target)
        return true
    }

    func surface(_ view: TerminalSurfaceView, requestsResize resize: ghostty_action_resize_split_s) -> Bool {
        let direction: SplitTree<UUID>.Direction = switch resize.direction {
        case GHOSTTY_RESIZE_SPLIT_LEFT: .left
        case GHOSTTY_RESIZE_SPLIT_UP: .up
        case GHOSTTY_RESIZE_SPLIT_DOWN: .down
        default: .right
        }
        return workspace.resize(view, direction: direction, byPoints: CGFloat(resize.amount))
    }

    func surfaceRequestsEqualize(_: TerminalSurfaceView) -> Bool {
        guard workspace.hasSplits else { return false }
        workspace.equalize()
        return true
    }

    func surfaceRequestsZoomToggle(_ view: TerminalSurfaceView) -> Bool {
        workspace.toggleZoom(view)
    }

    func surface(_: TerminalSurfaceView, requestsTab tab: ghostty_action_goto_tab_e) -> Bool {
        guard let window, let tabs = window.tabbedWindows, tabs.count > 1,
              let current = tabs.firstIndex(of: window)
        else { return false }
        let index: Int = switch tab {
        case GHOSTTY_GOTO_TAB_PREVIOUS: (current - 1 + tabs.count) % tabs.count
        case GHOSTTY_GOTO_TAB_NEXT: (current + 1) % tabs.count
        case GHOSTTY_GOTO_TAB_LAST: tabs.count - 1
        default: min(max(Int(tab.rawValue), 0), tabs.count - 1)
        }
        tabs[index].makeKeyAndOrderFront(nil)
        return true
    }

    func surfaceRequestsCloseTab(_: TerminalSurfaceView) {
        window?.performClose(nil)
    }

    func surfaceRequestsCloseWindow(_: TerminalSurfaceView) {
        let windows = window?.tabbedWindows ?? [window].compactMap(\.self)
        windows.forEach { $0.performClose(nil) }
    }

    func surfaceRequestsClose(_ view: TerminalSurfaceView, needsConfirm: Bool) {
        guard needsConfirm else {
            closePane(view)
            return
        }
        confirm(
            message: "Close this terminal?",
            detail: "A process is still running in it.",
            action: "Close",
        ) { [weak self] confirmed in
            if confirmed {
                self?.closePane(view)
            }
        }
    }

    func surfaceTitleDidChange(_ view: TerminalSurfaceView) {
        if view === focusedPane {
            updateTitle()
        }
    }

    func surfaceDidBecomeFocused(_ view: TerminalSurfaceView) {
        focusedPane = view
        updateTitle()
        applyAppearance()
    }

    func surfaceAppearanceDidChange(_ view: TerminalSurfaceView) {
        if view === focusedPane {
            applyAppearance()
        }
    }

    // MARK: Closing

    private func closePane(_ pane: TerminalSurfaceView) {
        let fallback = workspace.cycle(from: pane, forward: false)
        if workspace.remove(pane) {
            if let fallback {
                focus(fallback)
            }
        } else {
            window?.close()
        }
    }

    func windowShouldClose(_: NSWindow) -> Bool {
        let busy = workspace.orderedPanes.contains(where: \.needsConfirmQuit)
        guard busy else { return true }
        confirm(
            message: "Close this window?",
            detail: "Processes are still running in it.",
            action: "Close",
        ) { [weak self] confirmed in
            guard confirmed, let self else { return }
            self.workspace.orderedPanes.forEach { $0.teardown() }
            self.window?.close()
        }
        return false
    }

    func windowWillClose(_: Notification) {
        workspace.orderedPanes.forEach { $0.teardown() }
        onClose?(self)
    }

    func windowDidBecomeKey(_: Notification) {
        if let focusedPane, window?.firstResponder !== focusedPane {
            window?.makeFirstResponder(focusedPane)
        }
    }

    private func confirm(message: String, detail: String, action: String, completion: @escaping (Bool) -> Void) {
        guard let window else { return completion(true) }
        let alert = NSAlert()
        alert.messageText = message
        alert.informativeText = detail
        alert.addButton(withTitle: action)
        alert.addButton(withTitle: "Cancel")
        alert.beginSheetModal(for: window) { response in
            completion(response == .alertFirstButtonReturn)
        }
    }
}

/// Keeps every terminal window alive and answers app-level engine requests.
@MainActor
final class TerminalWindowManager: TerminalEngineDelegate {
    static let shared = TerminalWindowManager()
    private(set) var controllers: [TerminalWindowController] = []

    func makeController(options: TerminalSurfaceOptions) -> TerminalWindowController {
        let controller = TerminalWindowController(options: options)
        controller.onClose = { [weak self] closed in
            self?.controllers.removeAll { $0 === closed }
        }
        controllers.append(controller)
        return controller
    }

    @discardableResult
    func openWindow(inheriting surface: TerminalSurfaceView? = nil) -> TerminalWindowController {
        let controller = makeController(options: .inheriting(from: surface, context: GHOSTTY_SURFACE_CONTEXT_WINDOW))
        if let reference = NSApp.keyWindow {
            controller.window?.cascadeTopLeft(from: NSPoint(x: reference.frame.minX, y: reference.frame.maxY))
        } else {
            controller.window?.center()
        }
        controller.showAndFocus()
        return controller
    }

    var focusedController: TerminalWindowController? {
        controllers.first { $0.window === NSApp.keyWindow } ?? controllers.last
    }

    // MARK: TerminalEngineDelegate

    func engineRequestsNewWindow(inheriting surface: TerminalSurfaceView?) {
        openWindow(inheriting: surface)
    }

    func engineRequestsQuit() {
        NSApp.terminate(nil)
    }
}

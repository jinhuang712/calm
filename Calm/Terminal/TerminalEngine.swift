import AppKit
import GhosttyKit

/// Receives app-level requests from the engine (new windows, quitting).
@MainActor
protocol TerminalEngineDelegate: AnyObject {
    func engineRequestsNewWindow(inheriting surface: TerminalSurfaceView?)
    func engineRequestsQuit()
}

/// Owns libghostty's app object and routes its callbacks.
///
/// Every call into libghostty happens on the main actor, so every callback
/// (except `wakeup`, which may come from any thread) also runs on main.
@MainActor
final class TerminalEngine {
    static let shared = TerminalEngine()

    private(set) var app: ghostty_app_t?
    private(set) var config: TerminalConfig?
    weak var delegate: TerminalEngineDelegate?

    private var observers: [NSObjectProtocol] = []
    private var appearanceObservation: NSKeyValueObservation?

    private init() {}

    // MARK: Lifecycle

    /// Creates the libghostty app. Call once, after `GhosttyRuntime.initializeProcess()`.
    func start() {
        guard app == nil, GhosttyRuntime.isReady else { return }
        let config = TerminalConfig.load()
        self.config = config

        var runtime = ghostty_runtime_config_s(
            userdata: Unmanaged.passUnretained(self).toOpaque(),
            supports_selection_clipboard: true,
            wakeup_cb: TerminalCallbacks.wakeup,
            action_cb: TerminalCallbacks.action,
            read_clipboard_cb: TerminalCallbacks.readClipboard,
            confirm_read_clipboard_cb: TerminalCallbacks.confirmReadClipboard,
            write_clipboard_cb: TerminalCallbacks.writeClipboard,
            close_surface_cb: TerminalCallbacks.closeSurface,
        )

        guard let app = ghostty_app_new(&runtime, config.raw) else {
            FileHandle.standardError.write(Data("calm: libghostty failed to create its app object\n".utf8))
            return
        }
        self.app = app
        ghostty_app_set_focus(app, NSApp.isActive)
        observeSystem()
    }

    func tick() {
        guard let app else { return }
        ghostty_app_tick(app)
    }

    var needsConfirmQuit: Bool {
        guard let app else { return false }
        return ghostty_app_needs_confirm_quit(app)
    }

    // MARK: System observation

    private func observeSystem() {
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { TerminalEngine.shared.setAppFocus(true) }
        })
        observers.append(center.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { TerminalEngine.shared.setAppFocus(false) }
        })
        observers.append(center.addObserver(
            forName: NSTextInputContext.keyboardSelectionDidChangeNotification, object: nil, queue: .main,
        ) { _ in
            MainActor.assumeIsolated {
                if let app = TerminalEngine.shared.app {
                    ghostty_app_keyboard_changed(app)
                }
            }
        })
        appearanceObservation = NSApp.observe(\.effectiveAppearance, options: [.new, .initial]) { _, _ in
            DispatchQueue.main.async {
                MainActor.assumeIsolated { TerminalEngine.shared.syncColorScheme() }
            }
        }
    }

    private func setAppFocus(_ focused: Bool) {
        guard let app else { return }
        ghostty_app_set_focus(app, focused)
    }

    /// The color scheme matching the app's current appearance.
    var colorScheme: ghostty_color_scheme_e {
        let dark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        return dark ? GHOSTTY_COLOR_SCHEME_DARK : GHOSTTY_COLOR_SCHEME_LIGHT
    }

    /// libghostty resolves `theme = light:X,dark:Y` per surface, so every pane is told too.
    private func syncColorScheme() {
        guard let app else { return }
        let scheme = colorScheme
        ghostty_app_set_color_scheme(app, scheme)
        for controller in TerminalWindowManager.shared.controllers {
            controller.workspace.orderedPanes.forEach { $0.setColorScheme(scheme) }
        }
    }

    // MARK: Config reload

    /// Re-reads the config from disk (or re-applies it when `soft`) for the whole app.
    func reloadConfig(soft: Bool) {
        guard let app else { return }
        if soft {
            if let raw = config?.raw {
                ghostty_app_update_config(app, raw)
            }
            return
        }
        let fresh = TerminalConfig.load()
        ghostty_app_update_config(app, fresh.raw)
        config = fresh
    }

    private func reloadConfig(surface: ghostty_surface_t, soft: Bool) {
        if soft {
            if let raw = config?.raw {
                ghostty_surface_update_config(surface, raw)
            }
            return
        }
        let fresh = TerminalConfig.load()
        ghostty_surface_update_config(surface, fresh.raw)
    }

    // MARK: Actions

    /// Handles libghostty's action callback. Returning false lets keybindings fall
    /// through to the terminal and lets the core use its own fallbacks.
    fileprivate func handle(_ action: ghostty_action_s, target: ghostty_target_s) -> Bool {
        let view: TerminalSurfaceView? = target.tag == GHOSTTY_TARGET_SURFACE
            ? TerminalSurfaceView.from(ghostty_surface_userdata(target.target.surface))
            : nil
        if let handled = handleLayout(action, view: view) {
            return handled
        }
        if let handled = handleSurface(action, view: view) {
            return handled
        }

        switch action.tag {
        case GHOSTTY_ACTION_QUIT:
            delegate?.engineRequestsQuit()
        case GHOSTTY_ACTION_NEW_WINDOW:
            delegate?.engineRequestsNewWindow(inheriting: view)
        case GHOSTTY_ACTION_CLOSE_ALL_WINDOWS:
            NSApp.windows.filter(\.isVisible).forEach { $0.performClose(nil) }
        case GHOSTTY_ACTION_MOUSE_VISIBILITY:
            NSCursor.setHiddenUntilMouseMoves(action.action.mouse_visibility == GHOSTTY_MOUSE_HIDDEN)
        case GHOSTTY_ACTION_OPEN_URL:
            return openURL(action.action.open_url)
        case GHOSTTY_ACTION_RELOAD_CONFIG:
            let soft = action.action.reload_config.soft
            if target.tag == GHOSTTY_TARGET_SURFACE, let surface = target.target.surface {
                reloadConfig(surface: surface, soft: soft)
            } else {
                reloadConfig(soft: soft)
            }
        case GHOSTTY_ACTION_CONFIG_CHANGE:
            configDidChange(action.action.config_change.config, target: target, view: view)
        case GHOSTTY_ACTION_DESKTOP_NOTIFICATION, GHOSTTY_ACTION_PROGRESS_REPORT, GHOSTTY_ACTION_COMMAND_FINISHED:
            // Handled by the attention system in Milestone 3.
            return true
        default:
            return false
        }
        return true
    }

    /// Tabs, splits and windows. Returns nil for actions that aren't about layout.
    private func handleLayout(_ action: ghostty_action_s, view: TerminalSurfaceView?) -> Bool? {
        let host = view?.host
        switch action.tag {
        case GHOSTTY_ACTION_NEW_TAB:
            guard let view else {
                delegate?.engineRequestsNewWindow(inheriting: nil)
                return true
            }
            host?.surfaceRequestsNewTab(view)
            return true
        case GHOSTTY_ACTION_NEW_SPLIT:
            guard let view else { return false }
            host?.surface(view, requestsSplit: action.action.new_split)
            return true
        case GHOSTTY_ACTION_GOTO_SPLIT:
            return view.flatMap { host?.surface($0, requestsFocus: action.action.goto_split) } ?? false
        case GHOSTTY_ACTION_RESIZE_SPLIT:
            return view.flatMap { host?.surface($0, requestsResize: action.action.resize_split) } ?? false
        case GHOSTTY_ACTION_EQUALIZE_SPLITS:
            return view.flatMap { host?.surfaceRequestsEqualize($0) } ?? false
        case GHOSTTY_ACTION_TOGGLE_SPLIT_ZOOM:
            return view.flatMap { host?.surfaceRequestsZoomToggle($0) } ?? false
        case GHOSTTY_ACTION_GOTO_TAB:
            return view.flatMap { host?.surface($0, requestsTab: action.action.goto_tab) } ?? false
        case GHOSTTY_ACTION_CLOSE_TAB:
            guard let view else { return false }
            host?.surfaceRequestsCloseTab(view)
            return true
        case GHOSTTY_ACTION_CLOSE_WINDOW:
            guard let view else { return false }
            host?.surfaceRequestsCloseWindow(view)
            return true
        case GHOSTTY_ACTION_TOGGLE_FULLSCREEN:
            guard let view else { return false }
            view.window?.toggleFullScreen(nil)
            return true
        case GHOSTTY_ACTION_TOGGLE_COMMAND_PALETTE:
            guard let view else { return false }
            host?.surfaceRequestsCommandPalette(view)
            return true
        default:
            return nil
        }
    }

    /// State reported by one surface. Returns nil for other actions.
    private func handleSurface(_ action: ghostty_action_s, view: TerminalSurfaceView?) -> Bool? {
        switch action.tag {
        case GHOSTTY_ACTION_SET_TITLE:
            guard let view, let title = action.action.set_title.title else { return false }
            view.setTitle(String(cString: title))
        case GHOSTTY_ACTION_PWD:
            guard let view, let pwd = action.action.pwd.pwd else { return false }
            view.workingDirectory = String(cString: pwd)
        case GHOSTTY_ACTION_MOUSE_SHAPE:
            view?.setMouseShape(action.action.mouse_shape)
        case GHOSTTY_ACTION_CELL_SIZE:
            let size = action.action.cell_size
            view?.cellSizeDidChange(pixels: NSSize(width: Double(size.width), height: Double(size.height)))
        case GHOSTTY_ACTION_RING_BELL:
            view?.ringBell()
        case GHOSTTY_ACTION_COLOR_CHANGE:
            let change = action.action.color_change
            guard change.kind == GHOSTTY_ACTION_COLOR_KIND_BACKGROUND else { return true }
            view?.backgroundColorOverride = NSColor(
                srgbRed: CGFloat(change.r) / 255, green: CGFloat(change.g) / 255, blue: CGFloat(change.b) / 255, alpha: 1,
            )
        default:
            return nil
        }
        return true
    }

    private func configDidChange(_ raw: ghostty_config_t?, target: ghostty_target_s, view: TerminalSurfaceView?) {
        guard let raw, let copy = ghostty_config_clone(raw) else { return }
        let changed = TerminalConfig(owning: copy)
        if target.tag == GHOSTTY_TARGET_APP {
            config = changed
            NotificationCenter.default.post(name: .calmTerminalConfigDidChange, object: nil)
        } else {
            view?.configDidChange(changed)
        }
    }

    private func openURL(_ payload: ghostty_action_open_url_s) -> Bool {
        guard let pointer = payload.url, payload.len > 0 else { return false }
        let bytes = UnsafeRawBufferPointer(start: pointer, count: Int(payload.len))
        guard let string = String(bytes: bytes, encoding: .utf8) else { return false }

        let url: URL = if let parsed = URL(string: string), parsed.scheme != nil {
            parsed
        } else {
            // No scheme: a file path, possibly with ~.
            URL(filePath: (string as NSString).standardizingPath)
        }
        NSWorkspace.shared.open(url)
        // Returning true for OSC 8 links too: false would make the core retry with its own opener.
        return true
    }
}

extension Notification.Name {
    static let calmTerminalConfigDidChange = Notification.Name("calm.terminal.configDidChange")
}

/// libghostty's C callbacks. They are deliberately nonisolated: `wakeup` arrives on
/// libghostty's own threads, and a closure written inside a `@MainActor` method would
/// inherit main-actor isolation and trap there. The rest are called on main (we only call
/// libghostty from main), so they hop into the main actor with `assumeIsolated`.
enum TerminalCallbacks {
    static let wakeup: ghostty_runtime_wakeup_cb = { _ in
        DispatchQueue.main.async {
            MainActor.assumeIsolated { TerminalEngine.shared.tick() }
        }
    }

    static let action: ghostty_runtime_action_cb = { _, target, action in
        MainActor.assumeIsolated { TerminalEngine.shared.handle(action, target: target) }
    }

    static let readClipboard: ghostty_runtime_read_clipboard_cb = { userdata, location, state, mimes, count, list in
        let box = UncheckedSendable((userdata, state, mimes))
        return MainActor.assumeIsolated {
            TerminalClipboard.read(
                surfaceUserdata: box.value.0, location: location, state: box.value.1,
                mimes: box.value.2, mimeCount: count, list: list,
            )
        }
    }

    static let confirmReadClipboard: ghostty_runtime_confirm_read_clipboard_cb = { userdata, confirm, state, request in
        let box = UncheckedSendable((userdata, confirm, state))
        MainActor.assumeIsolated {
            TerminalClipboard.confirmRead(surfaceUserdata: box.value.0, confirm: box.value.1, state: box.value.2, request: request)
        }
    }

    static let writeClipboard: ghostty_runtime_write_clipboard_cb = { userdata, location, contents, count, confirm in
        let box = UncheckedSendable((userdata, contents))
        MainActor.assumeIsolated {
            TerminalClipboard.write(
                surfaceUserdata: box.value.0, location: location, contents: box.value.1, count: count, confirm: confirm,
            )
        }
    }

    static let closeSurface: ghostty_runtime_close_surface_cb = { userdata, needsConfirm in
        let box = UncheckedSendable(userdata)
        MainActor.assumeIsolated {
            TerminalSurfaceView.from(box.value)?.engineRequestsClose(needsConfirm: needsConfirm)
        }
    }
}

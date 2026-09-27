import AppKit
import GhosttyKit

/// Whoever lays out terminal panes (a window's split container) and reacts to their requests.
@MainActor
protocol TerminalSurfaceHost: AnyObject {
    func surfaceRequestsNewTab(_ view: TerminalSurfaceView)
    func surface(_ view: TerminalSurfaceView, requestsSplit direction: ghostty_action_split_direction_e)
    func surface(_ view: TerminalSurfaceView, requestsFocus direction: ghostty_action_goto_split_e) -> Bool
    func surface(_ view: TerminalSurfaceView, requestsResize resize: ghostty_action_resize_split_s) -> Bool
    func surfaceRequestsEqualize(_ view: TerminalSurfaceView) -> Bool
    func surfaceRequestsZoomToggle(_ view: TerminalSurfaceView) -> Bool
    func surface(_ view: TerminalSurfaceView, requestsTab tab: ghostty_action_goto_tab_e) -> Bool
    func surfaceRequestsCloseTab(_ view: TerminalSurfaceView)
    func surfaceRequestsCloseWindow(_ view: TerminalSurfaceView)
    func surfaceRequestsClose(_ view: TerminalSurfaceView, needsConfirm: Bool)
    func surfaceTitleDidChange(_ view: TerminalSurfaceView)
    func surfaceDidBecomeFocused(_ view: TerminalSurfaceView)
    func surfaceAppearanceDidChange(_ view: TerminalSurfaceView)
}

/// How a new surface should start.
struct TerminalSurfaceOptions {
    var workingDirectory: String?
    var command: String?
    var fontSize: Float = 0
    var context: ghostty_surface_context_e = GHOSTTY_SURFACE_CONTEXT_WINDOW
    var environment: [String: String] = [:]

    /// Starts from the parent's settings (font size, working directory), as libghostty computes them.
    @MainActor
    static func inheriting(from parent: TerminalSurfaceView?, context: ghostty_surface_context_e) -> TerminalSurfaceOptions {
        var options = TerminalSurfaceOptions(context: context)
        guard let parent, let surface = parent.surface else { return options }
        let inherited = ghostty_surface_inherited_config(surface, context)
        options.fontSize = inherited.font_size
        if let directory = inherited.working_directory {
            // libghostty allocates this and offers no way to free it; copy and leave it (tiny, per split).
            options.workingDirectory = String(cString: directory)
        }
        return options
    }
}

/// One terminal pane, backed by a libghostty surface.
///
/// libghostty turns this view into a layer-hosting view and renders into it from its own
/// thread; don't touch `wantsLayer`/`layer` and don't add subviews (put overlays in siblings).
@MainActor
final class TerminalSurfaceView: NSView {
    let id = UUID()
    private(set) var surface: ghostty_surface_t?
    weak var host: TerminalSurfaceHost?

    private(set) var title = ""
    var workingDirectory: String?
    var backgroundColorOverride: NSColor? {
        didSet { host?.surfaceAppearanceDidChange(self) }
    }

    /// Cell size in points (libghostty reports pixels).
    private(set) var cellSize: NSSize = .zero
    private var contentSize: NSSize = .zero
    private var focused = false
    private var isWindowVisible = true
    private var pendingTitle: String?
    private var titleTimer: Timer?
    private var trackingArea: NSTrackingArea?
    private var suppressNextLeftMouseUp = false
    private var eventMonitor: Any?
    private var windowObservers: [NSObjectProtocol] = []

    // Keyboard and IME state, used by the keyboard extension.
    var markedText = NSMutableAttributedString()
    var keyTextAccumulator: [String]?
    var lastPerformKeyEventTimestamp: TimeInterval?
    var pendingLeadSurrogate: UInt16?

    init(options: TerminalSurfaceOptions) {
        // A non-zero frame so the renderer's layer starts with real bounds.
        super.init(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        installEventMonitor()
        createSurface(options)
        updateTrackingAreas()
        registerForDraggedTypes([.string, .fileURL])
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("not supported")
    }

    deinit {
        MainActor.assumeIsolated {
            teardown()
        }
    }

    /// Recovers the view from libghostty userdata.
    static func from(_ userdata: UnsafeMutableRawPointer?) -> TerminalSurfaceView? {
        guard let userdata else { return nil }
        return Unmanaged<TerminalSurfaceView>.fromOpaque(userdata).takeUnretainedValue()
    }

    private func createSurface(_ options: TerminalSurfaceOptions) {
        guard let app = TerminalEngine.shared.app else { return }
        var config = ghostty_surface_config_new()
        config.platform_tag = GHOSTTY_PLATFORM_MACOS
        config.platform = ghostty_platform_u(macos: ghostty_platform_macos_s(nsview: Unmanaged.passUnretained(self).toOpaque()))
        config.userdata = Unmanaged.passUnretained(self).toOpaque()
        config.scale_factor = Double(NSScreen.main?.backingScaleFactor ?? 2)
        config.font_size = options.fontSize
        config.context = options.context

        var env = options.environment
        env["CALM_SESSION_ID"] = id.uuidString
        let keys = env.keys.sorted().map { strdup($0) }
        let values = env.keys.sorted().map { strdup(env[$0] ?? "") }
        defer {
            keys.forEach { free($0) }
            values.forEach { free($0) }
        }
        var envVars = zip(keys, values).map { ghostty_env_var_s(key: $0.map { UnsafePointer($0) }, value: $1.map { UnsafePointer($0) }) }

        let directory = options.workingDirectory.flatMap { strdup($0) }
        let command = options.command.flatMap { strdup($0) }
        defer {
            directory.map { free($0) }
            command.map { free($0) }
        }
        config.working_directory = directory.map { UnsafePointer($0) }
        config.command = command.map { UnsafePointer($0) }

        surface = envVars.withUnsafeMutableBufferPointer { buffer in
            config.env_vars = buffer.baseAddress
            config.env_var_count = buffer.count
            return ghostty_surface_new(app, &config)
        }
    }

    /// Frees the libghostty surface. Must run on main, before the view goes away.
    func teardown() {
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
        }
        eventMonitor = nil
        windowObservers.forEach { NotificationCenter.default.removeObserver($0) }
        windowObservers = []
        titleTimer?.invalidate()
        if let surface {
            self.surface = nil
            ghostty_surface_free(surface)
        }
    }

    // MARK: Engine callbacks

    func engineRequestsClose(needsConfirm: Bool) {
        host?.surfaceRequestsClose(self, needsConfirm: needsConfirm)
    }

    /// Title changes are coalesced briefly so fast updates don't flicker.
    func setTitle(_ newTitle: String) {
        pendingTitle = newTitle
        titleTimer?.invalidate()
        titleTimer = Timer.scheduledTimer(withTimeInterval: 0.075, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let pending = self.pendingTitle else { return }
                self.pendingTitle = nil
                if pending != self.title {
                    self.title = pending
                    self.host?.surfaceTitleDidChange(self)
                }
            }
        }
    }

    func cellSizeDidChange(pixels: NSSize) {
        let points = convertFromBacking(pixels)
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated { self?.cellSize = points }
        }
    }

    /// This pane's resolved config (light/dark conditional themes are resolved per surface).
    private(set) var config: TerminalConfig?

    func configDidChange(_ config: TerminalConfig) {
        self.config = config
        host?.surfaceAppearanceDidChange(self)
    }

    var effectiveBackgroundColor: NSColor? {
        backgroundColorOverride ?? config?.backgroundColor
    }

    func ringBell() {
        NSSound.beep()
    }

    func setMouseShape(_ shape: ghostty_action_mouse_shape_e) {
        let cursor: NSCursor? = switch shape {
        case GHOSTTY_MOUSE_SHAPE_DEFAULT: .arrow
        case GHOSTTY_MOUSE_SHAPE_TEXT: .iBeam
        case GHOSTTY_MOUSE_SHAPE_VERTICAL_TEXT: .iBeamCursorForVerticalLayout
        case GHOSTTY_MOUSE_SHAPE_POINTER: .pointingHand
        case GHOSTTY_MOUSE_SHAPE_GRAB: .openHand
        case GHOSTTY_MOUSE_SHAPE_GRABBING: .closedHand
        case GHOSTTY_MOUSE_SHAPE_CROSSHAIR: .crosshair
        case GHOSTTY_MOUSE_SHAPE_NOT_ALLOWED: .operationNotAllowed
        case GHOSTTY_MOUSE_SHAPE_CONTEXT_MENU: .contextualMenu
        case GHOSTTY_MOUSE_SHAPE_EW_RESIZE, GHOSTTY_MOUSE_SHAPE_COL_RESIZE: .resizeLeftRight
        case GHOSTTY_MOUSE_SHAPE_NS_RESIZE, GHOSTTY_MOUSE_SHAPE_ROW_RESIZE: .resizeUpDown
        default: nil
        }
        guard let cursor else { return }
        currentCursor = cursor
        window?.invalidateCursorRects(for: self)
    }

    private var currentCursor: NSCursor = .iBeam

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: currentCursor)
    }

    // MARK: Sizing

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        sizeDidChange(newSize)
    }

    /// Tells libghostty the new size in pixels. Uses the size given, not `frame`, which may lag during animations.
    func sizeDidChange(_ size: NSSize) {
        guard let surface, size.width > 0, size.height > 0 else { return }
        contentSize = size
        let pixels = convertToBacking(size)
        ghostty_surface_set_size(surface, UInt32(pixels.width), UInt32(pixels.height))
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        if let window {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            layer?.contentsScale = window.backingScaleFactor
            CATransaction.commit()
        }
        guard let surface else { return }
        let backing = convertToBacking(frame)
        let scaleX = frame.width > 0 ? backing.width / frame.width : 1
        let scaleY = frame.height > 0 ? backing.height / frame.height : 1
        ghostty_surface_set_content_scale(surface, scaleX, scaleY)
        sizeDidChange(contentSize == .zero ? frame.size : contentSize)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        windowObservers.forEach { NotificationCenter.default.removeObserver($0) }
        windowObservers = []
        guard let window else { return }
        let center = NotificationCenter.default
        windowObservers.append(center.addObserver(forName: NSWindow.didChangeScreenNotification, object: window, queue: .main) { _ in
            MainActor.assumeIsolated { [weak self] in self?.screenDidChange() }
        })
        windowObservers.append(center.addObserver(
            forName: NSWindow.didChangeOcclusionStateNotification, object: window, queue: .main,
        ) { _ in
            MainActor.assumeIsolated { [weak self] in self?.occlusionDidChange() }
        })
        windowObservers.append(center.addObserver(forName: NSWindow.didBecomeKeyNotification, object: window, queue: .main) { _ in
            MainActor.assumeIsolated { [weak self] in self?.syncFocus() }
        })
        windowObservers.append(center.addObserver(forName: NSWindow.didResignKeyNotification, object: window, queue: .main) { _ in
            MainActor.assumeIsolated { [weak self] in self?.syncFocus() }
        })
        viewDidChangeBackingProperties()
        screenDidChange()
    }

    private func screenDidChange() {
        guard let surface, let screen = window?.screen,
              let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
        else { return }
        ghostty_surface_set_display_id(surface, number.uint32Value)
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated { self?.viewDidChangeBackingProperties() }
        }
    }

    private func occlusionDidChange() {
        guard let surface, let window else { return }
        let visible = window.occlusionState.contains(.visible)
        guard visible != isWindowVisible else { return }
        isWindowVisible = visible
        ghostty_surface_set_occlusion(surface, visible)
    }

    // MARK: Focus

    override var acceptsFirstResponder: Bool {
        true
    }

    override func becomeFirstResponder() -> Bool {
        let accepted = super.becomeFirstResponder()
        if accepted {
            syncFocus()
            host?.surfaceDidBecomeFocused(self)
        }
        return accepted
    }

    override func resignFirstResponder() -> Bool {
        let accepted = super.resignFirstResponder()
        if accepted {
            suppressNextLeftMouseUp = false
            syncFocus()
        }
        return accepted
    }

    func syncFocus() {
        let shouldFocus = window?.isKeyWindow == true && window?.firstResponder === self
        guard let surface, shouldFocus != focused else { return }
        focused = shouldFocus
        ghostty_surface_set_focus(surface, shouldFocus)
    }

    var isFocused: Bool {
        focused
    }

    /// Clicking an unfocused pane only focuses it; the click isn't sent to the terminal.
    private func installEventMonitor() {
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .keyUp]) { [weak self] event in
            // Local monitors run on the main thread; the box only carries NSEvent across the isolation check.
            let incoming = UncheckedSendable(event)
            return MainActor.assumeIsolated { () -> UncheckedSendable<NSEvent?> in
                guard let self else { return UncheckedSendable(incoming.value) }
                let event = incoming.value
                return UncheckedSendable(event.type == .keyUp ? self.handleMonitoredKeyUp(event) : self.handleMonitoredMouseDown(event))
            }.value
        }
    }

    private func handleMonitoredMouseDown(_ event: NSEvent) -> NSEvent? {
        guard let window, event.window === window,
              let hit = window.contentView?.hitTest(event.locationInWindow), hit === self,
              window.firstResponder !== self
        else { return event }
        window.makeFirstResponder(self)
        if NSApp.isActive, window.isKeyWindow {
            suppressNextLeftMouseUp = true
            return nil
        }
        return event
    }

    /// Cmd+key key-ups never reach the responder chain; forward them while focused.
    private func handleMonitoredKeyUp(_ event: NSEvent) -> NSEvent? {
        guard focused, event.modifierFlags.contains(.command), event.window === window else { return event }
        keyUp(with: event)
        return nil
    }

    // MARK: Mouse

    override func updateTrackingAreas() {
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .mouseMoved, .inVisibleRect, .activeAlways],
            owner: self,
            userInfo: nil,
        )
        addTrackingArea(area)
        trackingArea = area
        super.updateTrackingAreas()
    }

    private func sendMousePosition(_ event: NSEvent) {
        guard let surface else { return }
        let point = convert(event.locationInWindow, from: nil)
        ghostty_surface_mouse_pos(surface, point.x, frame.height - point.y, TerminalInput.mods(event.modifierFlags))
    }

    private func sendMouseButton(_ state: ghostty_input_mouse_state_e, _ button: ghostty_input_mouse_button_e, _ event: NSEvent) -> Bool {
        guard let surface else { return false }
        return ghostty_surface_mouse_button(surface, state, button, TerminalInput.mods(event.modifierFlags))
    }

    override func mouseDown(with event: NSEvent) {
        sendMousePosition(event)
        _ = sendMouseButton(GHOSTTY_MOUSE_PRESS, GHOSTTY_MOUSE_LEFT, event)
    }

    override func mouseUp(with event: NSEvent) {
        if suppressNextLeftMouseUp {
            suppressNextLeftMouseUp = false
            return
        }
        _ = sendMouseButton(GHOSTTY_MOUSE_RELEASE, GHOSTTY_MOUSE_LEFT, event)
        if let surface {
            ghostty_surface_mouse_pressure(surface, 0, 0)
        }
    }

    override func rightMouseDown(with event: NSEvent) {
        if !sendMouseButton(GHOSTTY_MOUSE_PRESS, GHOSTTY_MOUSE_RIGHT, event) {
            super.rightMouseDown(with: event)
        }
    }

    override func rightMouseUp(with event: NSEvent) {
        if !sendMouseButton(GHOSTTY_MOUSE_RELEASE, GHOSTTY_MOUSE_RIGHT, event) {
            super.rightMouseUp(with: event)
        }
    }

    override func otherMouseDown(with event: NSEvent) {
        _ = sendMouseButton(GHOSTTY_MOUSE_PRESS, TerminalInput.mouseButton(event.buttonNumber), event)
    }

    override func otherMouseUp(with event: NSEvent) {
        _ = sendMouseButton(GHOSTTY_MOUSE_RELEASE, TerminalInput.mouseButton(event.buttonNumber), event)
    }

    override func mouseMoved(with event: NSEvent) {
        sendMousePosition(event)
    }

    override func mouseDragged(with event: NSEvent) {
        sendMousePosition(event)
    }

    override func rightMouseDragged(with event: NSEvent) {
        sendMousePosition(event)
    }

    override func otherMouseDragged(with event: NSEvent) {
        sendMousePosition(event)
    }

    override func mouseEntered(with event: NSEvent) {
        sendMousePosition(event)
    }

    override func mouseExited(with event: NSEvent) {
        guard let surface else { return }
        if NSEvent.pressedMouseButtons == 0 {
            // The cursor left the viewport.
            ghostty_surface_mouse_pos(surface, -1, -1, TerminalInput.mods(event.modifierFlags))
        } else {
            sendMousePosition(event)
        }
    }

    override func scrollWheel(with event: NSEvent) {
        guard let surface else { return }
        var deltaX = event.scrollingDeltaX
        var deltaY = event.scrollingDeltaY
        let precise = event.hasPreciseScrollingDeltas
        if precise {
            // Trackpad deltas are points; libghostty compares them against pixel cell heights.
            deltaX *= 2
            deltaY *= 2
        }
        var mods: Int32 = precise ? 1 : 0
        mods |= Int32(TerminalInput.momentum(event.momentumPhase).rawValue) << 1
        ghostty_surface_mouse_scroll(surface, deltaX, deltaY, ghostty_input_scroll_mods_t(mods))
    }

    override func pressureChange(with event: NSEvent) {
        guard let surface else { return }
        ghostty_surface_mouse_pressure(surface, UInt32(event.stage), Double(event.pressure))
    }

    // MARK: Drag and drop

    override func draggingEntered(_: NSDraggingInfo) -> NSDragOperation {
        .copy
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let surface, let text = TerminalClipboard.plainText(from: sender.draggingPasteboard) else { return false }
        text.withCString { ghostty_surface_text(surface, $0, UInt(text.utf8.count)) }
        return true
    }

    // MARK: Actions

    /// Runs a named libghostty binding action such as `copy_to_clipboard`.
    @discardableResult
    func perform(_ action: String) -> Bool {
        guard let surface else { return false }
        return action.withCString { ghostty_surface_binding_action(surface, $0, UInt(action.utf8.count)) }
    }

    @objc func copy(_: Any?) {
        perform("copy_to_clipboard")
    }

    @objc func paste(_: Any?) {
        perform("paste_from_clipboard")
    }

    @objc override func selectAll(_: Any?) {
        perform("select_all")
    }

    /// Reads text from the screen, e.g. for tests and later for search and Copy Cell.
    func readText(_ selection: ghostty_selection_s) -> String? {
        guard let surface else { return nil }
        var text = ghostty_text_s()
        guard ghostty_surface_read_text(surface, selection, &text) else { return nil }
        defer { ghostty_surface_free_text(surface, &text) }
        guard let pointer = text.text else { return nil }
        return String(bytes: UnsafeRawBufferPointer(start: pointer, count: Int(text.text_len)), encoding: .utf8)
    }

    /// The visible screen as text.
    func viewportText() -> String? {
        readText(ghostty_selection_s(
            top_left: ghostty_point_s(tag: GHOSTTY_POINT_VIEWPORT, coord: GHOSTTY_POINT_COORD_TOP_LEFT, x: 0, y: 0),
            bottom_right: ghostty_point_s(tag: GHOSTTY_POINT_VIEWPORT, coord: GHOSTTY_POINT_COORD_BOTTOM_RIGHT, x: 0, y: 0),
            rectangle: false,
        ))
    }

    var needsConfirmQuit: Bool {
        guard let surface else { return false }
        return ghostty_surface_needs_confirm_quit(surface)
    }

    func requestClose() {
        guard let surface else { return }
        ghostty_surface_request_close(surface)
    }
}

/// Carries a non-Sendable value across an isolation boundary we know is safe (same thread).
struct UncheckedSendable<Value>: @unchecked Sendable {
    let value: Value
    init(_ value: Value) {
        self.value = value
    }
}

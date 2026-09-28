import AppKit
import CalmControl
import CalmModel
import GhosttyKit

/// Whoever lays out terminal panes (a window's split container) and reacts to their requests.
@MainActor
protocol TerminalSurfaceHost: AnyObject {
    func surfaceRequestsNewTab(_ view: TerminalSurfaceView)
    func surface(_ view: TerminalSurfaceView, requestsSplit direction: SplitTree<UUID>.Direction)
    func surface(_ view: TerminalSurfaceView, requestsFocus target: PaneFocusTarget) -> Bool
    func surface(_ view: TerminalSurfaceView, requestsResize direction: SplitTree<UUID>.Direction, byPoints amount: CGFloat) -> Bool
    func surfaceRequestsEqualize(_ view: TerminalSurfaceView) -> Bool
    func surfaceRequestsZoomToggle(_ view: TerminalSurfaceView) -> Bool
    func surface(_ view: TerminalSurfaceView, requestsSession target: SessionTarget) -> Bool
    func surfaceRequestsCloseTab(_ view: TerminalSurfaceView)
    func surfaceRequestsCloseWindow(_ view: TerminalSurfaceView)
    func surfaceRequestsClose(_ view: TerminalSurfaceView, needsConfirm: Bool)
    func surfaceTitleDidChange(_ view: TerminalSurfaceView)
    func surfaceDidBecomeFocused(_ view: TerminalSurfaceView)
    func surfaceAppearanceDidChange(_ view: TerminalSurfaceView)
    func surfaceRequestsCommandPalette(_ view: TerminalSurfaceView)
    func surfaceChildExited(_ view: TerminalSurfaceView)
    func surfaceWorkingDirectoryDidChange(_ view: TerminalSurfaceView)
    /// Bell, desktop notification, progress or command finished (DESIGNS.md → Attention).
    func surface(_ view: TerminalSurfaceView, didSignal signal: TerminalSignal)
    /// A link was ⌘-clicked (a URL, or a path as the terminal matched it, maybe with `:line`).
    func surface(_ view: TerminalSurfaceView, requestsOpenLink text: String)
    /// A table cell was copied (Copy Cell); `point` is in the view's coordinates.
    func surfaceDidCopyCell(_ view: TerminalSurfaceView, at point: NSPoint)
}

/// How a new surface should start.
struct TerminalSurfaceOptions {
    /// A Calm session's pane. Every session lives in the one main window, so libghostty
    /// treats it like a split (for inherited settings).
    static var session: TerminalSurfaceOptions {
        TerminalSurfaceOptions(context: GHOSTTY_SURFACE_CONTEXT_SPLIT)
    }

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
    let id: UUID
    let createdAt = Date()
    private(set) var surface: ghostty_surface_t?
    weak var host: TerminalSurfaceHost?

    private(set) var title = ""
    /// Whether the shell reports its folder itself (OSC 7); if not, Calm looks it up.
    var reportsWorkingDirectory = false

    /// The process group in the terminal's foreground (the shell, or the job it started).
    var foregroundProcessID: Int32? {
        guard let surface else { return nil }
        let pid = ghostty_surface_foreground_pid(surface)
        return pid > 0 ? Int32(truncatingIfNeeded: pid) : nil
    }

    var workingDirectory: String? {
        didSet {
            if workingDirectory != oldValue {
                host?.surfaceWorkingDirectoryDidChange(self)
            }
        }
    }

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
    private var frameObservation: NSKeyValueObservation?
    private var isEdgeSamplePending = false

    // Keyboard and IME state, used by the keyboard extension.
    var markedText = NSMutableAttributedString()
    var keyTextAccumulator: [String]?
    var lastPerformKeyEventTimestamp: TimeInterval?
    var pendingLeadSurrogate: UInt16?

    init(id: UUID = UUID(), options: TerminalSurfaceOptions) {
        self.id = id
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
        // The status contract (DESIGNS.md → Attention): hooks run `$CALM_CLI status …`, which
        // reports for `$CALM_SESSION_ID` over `$CALM_SOCKET`.
        env["CALM_SESSION_ID"] = id.uuidString
        env["CALM_SOCKET"] = ControlProtocol.defaultSocketPath
        if let cli = Bundle.main.resourceURL?.appending(path: "bin/calm").path {
            env["CALM_CLI"] = cli
        }
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
        setColorScheme(TerminalEngine.shared.colorScheme)
        observeFrames()
    }

    /// The color along the top edge of the last frame (SurfaceEdgeColor); the title strip takes it.
    private(set) var topEdgeColor: NSColor? {
        didSet {
            if topEdgeColor != oldValue {
                host?.surfaceAppearanceDidChange(self)
            }
        }
    }

    /// libghostty hands each finished frame to the layer as its `contents` (an IOSurface), usually
    /// on main. Reading it back is cheap, but frames come at up to 120 Hz, so the edge is sampled
    /// at most every 0.1 s, always after the latest frame.
    private func observeFrames() {
        frameObservation = layer?.observe(\.contents) { [weak self] _, _ in
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.scheduleEdgeSample() }
            }
        }
    }

    private func scheduleEdgeSample() {
        guard !isEdgeSamplePending else { return }
        isEdgeSamplePending = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            MainActor.assumeIsolated { self?.sampleEdge() }
        }
    }

    private func sampleEdge() {
        isEdgeSamplePending = false
        // The CF type IOSurfaceRef is bridged to IOSurface in Swift.
        guard let contents = layer?.contents, CFGetTypeID(contents as CFTypeRef) == IOSurfaceGetTypeID() else { return }
        topEdgeColor = SurfaceEdgeColor.top(of: unsafeBitCast(contents as AnyObject, to: IOSurface.self))
    }

    private var colorScheme: ghostty_color_scheme_e?

    func setColorScheme(_ scheme: ghostty_color_scheme_e) {
        guard let surface, scheme != colorScheme else { return }
        colorScheme = scheme
        ghostty_surface_set_color_scheme(surface, scheme)
    }

    /// Frees the libghostty surface. Must run on main, before the view goes away.
    func teardown() {
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
        }
        eventMonitor = nil
        windowObservers.forEach { NotificationCenter.default.removeObserver($0) }
        windowObservers = []
        frameObservation?.invalidate()
        frameObservation = nil
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
        // From the window, not from convertToBacking(frame): a pane created before layout has a
        // zero frame, and a fallback scale of 1 stuck, rendering text at half size on Retina.
        let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        ghostty_surface_set_content_scale(surface, scale, scale)
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

    /// Types a command into the shell and presses Return, as if from the keyboard (e.g. resuming
    /// an agent session). Text sent before the prompt is ready waits in the shell's input.
    func run(_ command: String) {
        guard let surface else { return }
        command.withCString { ghostty_surface_text(surface, $0, UInt(command.utf8.count)) }
        var key = ghostty_input_key_s()
        key.action = GHOSTTY_ACTION_PRESS
        key.keycode = 36 // Return
        key.mods = GHOSTTY_MODS_NONE
        key.consumed_mods = GHOSTTY_MODS_NONE
        key.unshifted_codepoint = 13
        "\r".withCString { pointer in
            key.text = pointer
            _ = ghostty_surface_key(surface, key)
        }
        key.action = GHOSTTY_ACTION_RELEASE
        key.text = nil
        _ = ghostty_surface_key(surface, key)
    }

    /// Hidden panes (in layouts not on screen) stop rendering until shown again.
    func setVisible(_ visible: Bool) {
        guard let surface, visible != isWindowVisible else { return }
        isWindowVisible = visible
        ghostty_surface_set_occlusion(surface, visible)
    }

    private func occlusionDidChange() {
        guard let surface, let window else { return }
        // A headless self-test's window is transparent, which counts as occluded; keep rendering.
        let visible = window.occlusionState.contains(.visible) || Headless.isOn
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
        // A headless self-test's window never becomes key (it would take the user's typing).
        let shouldFocus = (window?.isKeyWindow == true || Headless.isOn) && window?.firstResponder === self
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
        // ⌥-double-click copies a table cell; outside a table it falls through as usual.
        if event.clickCount == 2, event.modifierFlags.contains(.option),
           copyTableCell(at: convert(event.locationInWindow, from: nil)) {
            suppressNextLeftMouseUp = true
            return
        }
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

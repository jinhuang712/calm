import AppKit
import CalmModel

/// The split icon (UIUX.md → Split panes): a small quiet icon in the top right corner of a pane
/// that is in a split. It says that what there is to do about splitting is here: click it for
/// the menu (Take Out of Split, Zoom, Equalize), or drag it onto the sidebar to take the pane out.
extension TerminalWorkspaceView {
    static let handleSide: CGFloat = 24
    static let handleInset: CGFloat = 8

    /// The icon's place: the top right corner of the pane.
    static func handleFrame(in pane: NSRect) -> NSRect {
        NSRect(x: pane.maxX - handleInset - handleSide, y: pane.minY + handleInset, width: handleSide, height: handleSide)
    }

    func handleView(for id: UUID) -> SplitHandleView {
        if let handle = handleViews[id] {
            return handle
        }
        let handle = SplitHandleView(paneID: id)
        handle.isDark = handleIsDark
        handle.alphaValue = 0
        handle.onClick = { [weak self] handle in self?.handleClicked(handle) }
        handle.onDragBegan = { [weak self] id in
            guard let item = self?.onHandleDrag?(id) else { return nil }
            // Its icon stays while it is held, wherever the pointer goes.
            self?.busyHandleID = id
            self?.refreshHandles(animated: false)
            return item
        }
        handle.onDragMoved = { [weak self] id, point in self?.onHandleDragMoved?(id, point) }
        handle.onDragEnded = { [weak self] id in
            self?.busyHandleID = nil
            self?.onHandleDragEnded?(id)
            self?.refreshHandles(animated: true)
        }
        handles.addSubview(handle)
        handleViews[id] = handle
        return handle
    }

    /// Shows the icon on the panes that have it (`SplitHandle.isShown`), and draws the line in each
    /// the way its split divides.
    func refreshHandles(animated: Bool) {
        let splits = hasSplits
        for (id, pane) in panes {
            let handle = handleView(for: id)
            let shown = !pane.isHidden && SplitHandle.isShown(
                hasSplits: splits, isFocused: id == focusedID, isPointedAt: id == hoveredID,
                isBusy: id == busyHandleID, isAsking: askedID != nil,
            )
            let axis = tree?.parentAxis(of: id) ?? .horizontal
            if handle.axis != axis {
                handle.axis = axis
            }
            Motion.fade(handle, to: shown ? 1 : 0, duration: animated ? Self.veilDuration : 0)
        }
    }

    private func handleClicked(_ handle: SplitHandleView) {
        busyHandleID = handle.paneID
        refreshHandles(animated: false)
        // The menu runs its own loop until it closes, so the icon stays put meanwhile.
        onHandleClick?(handle.paneID, handle)
        busyHandleID = nil
        refreshHandles(animated: true)
    }

    // MARK: Pointer

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            removeHandleMonitor()
        } else {
            installHandleMonitor()
        }
    }

    /// Which pane the pointer is on, for the icon that shows on hover. A monitor rather than a
    /// tracking area: the panes are in front and own the pointer, and they must keep getting it.
    private func installHandleMonitor() {
        guard handleMonitor == nil else { return }
        handleMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .mouseExited]) { [weak self] event in
            let incoming = UncheckedSendable(event)
            return MainActor.assumeIsolated { () -> UncheckedSendable<NSEvent?> in
                self?.pointerMoved(incoming.value)
                return UncheckedSendable(incoming.value)
            }.value
        }
    }

    func removeHandleMonitor() {
        if let handleMonitor {
            NSEvent.removeMonitor(handleMonitor)
        }
        handleMonitor = nil
    }

    private func pointerMoved(_ event: NSEvent) {
        guard let window, event.window === window, !isHiddenOrHasHiddenAncestor, hasSplits else {
            return setHovered(nil)
        }
        setHovered(paneID(at: convert(window.mouseLocationOutsideOfEventStream, from: nil)))
    }

    /// The pane under `point` (this view's coordinates), if it is on screen.
    func paneID(at point: NSPoint) -> UUID? {
        panes.first { !$0.value.isHidden && $0.value.frame.contains(point) }?.key
    }

    func setHovered(_ id: UUID?) {
        guard hoveredID != id else { return }
        hoveredID = id
        refreshHandles(animated: true)
    }
}

/// The layer that holds the icons. It takes no clicks except on an icon that shows.
@MainActor
final class HandlesView: NSView {
    override var isFlipped: Bool {
        true
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let inside = convert(point, from: superview)
        for case let handle as SplitHandleView in subviews.reversed() where handle.alphaValue > 0.05 && handle.frame.contains(inside) {
            return handle
        }
        return nil
    }
}

/// One pane's icon: a small window with a line through it, the line following the split the pane
/// is in (upright for panes side by side, flat for stacked ones). Quiet at rest, like the ⋯ in the
/// title strip; under the pointer it brightens on a soft tile.
@MainActor
final class SplitHandleView: NSView, NSDraggingSource {
    let paneID: UUID
    var isDark = true {
        didSet { needsDisplay = true }
    }

    var axis = SplitTree<UUID>.Axis.horizontal {
        didSet { needsDisplay = true }
    }

    var onClick: ((SplitHandleView) -> Void)?
    var onDragBegan: ((UUID) -> NSDraggingItem?)?
    var onDragMoved: ((UUID, NSPoint) -> Void)?
    var onDragEnded: ((UUID) -> Void)?

    /// The pointer is on the icon.
    private var isPointedAt = false {
        didSet { needsDisplay = true }
    }

    private var pressed: NSPoint?
    private var dragging = false

    init(paneID: UUID) {
        self.paneID = paneID
        super.init(frame: NSRect(x: 0, y: 0, width: TerminalWorkspaceView.handleSide, height: TerminalWorkspaceView.handleSide))
        wantsLayer = true
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("not supported")
    }

    override var isFlipped: Bool {
        true
    }

    /// What it says to someone resting the pointer on it.
    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        toolTip = "Split options · or drag to move it"
    }

    override func updateTrackingAreas() {
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .inVisibleRect, .activeAlways], owner: self))
        super.updateTrackingAreas()
    }

    override func mouseEntered(with _: NSEvent) {
        isPointedAt = true
    }

    override func mouseExited(with _: NSEvent) {
        isPointedAt = false
    }

    override func acceptsFirstMouse(for _: NSEvent?) -> Bool {
        true
    }

    // MARK: Drawing

    override func draw(_: NSRect) {
        let ink = isDark ? NSColor.white : NSColor.black
        if isPointedAt {
            ink.withAlphaComponent(0.1).setFill()
            NSBezierPath(roundedRect: bounds, xRadius: 7, yRadius: 7).fill()
        }
        // The chrome's tertiary at rest, its primary under the pointer (SidebarStyle).
        ink.withAlphaComponent(isPointedAt ? 0.86 : isDark ? 0.38 : 0.4).setStroke()
        // The icon is drawn on a 16 pt grid, centered.
        let origin = NSPoint(x: bounds.midX - 8, y: bounds.midY - 8)
        let window = NSBezierPath(
            roundedRect: NSRect(x: origin.x + 1.75, y: origin.y + 2.75, width: 12.5, height: 10.5), xRadius: 2.5, yRadius: 2.5,
        )
        window.lineWidth = 1.5
        window.stroke()
        let line = NSBezierPath()
        switch axis {
        case .horizontal:
            line.move(to: NSPoint(x: origin.x + 8, y: origin.y + 2.75))
            line.line(to: NSPoint(x: origin.x + 8, y: origin.y + 13.25))
        case .vertical:
            line.move(to: NSPoint(x: origin.x + 1.75, y: origin.y + 8))
            line.line(to: NSPoint(x: origin.x + 14.25, y: origin.y + 8))
        }
        line.lineWidth = 1.5
        line.stroke()
    }

    // MARK: Click and drag

    override func mouseDown(with event: NSEvent) {
        pressed = convert(event.locationInWindow, from: nil)
        dragging = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard let pressed, !dragging else { return }
        let point = convert(event.locationInWindow, from: nil)
        guard hypot(point.x - pressed.x, point.y - pressed.y) > 4, let item = onDragBegan?(paneID) else { return }
        dragging = true
        isPointedAt = false
        beginDraggingSession(with: [item], event: event, source: self)
    }

    override func mouseUp(with _: NSEvent) {
        defer { pressed = nil }
        guard pressed != nil, !dragging else { return }
        onClick?(self)
    }

    nonisolated func draggingSession(_: NSDraggingSession, sourceOperationMaskFor _: NSDraggingContext) -> NSDragOperation {
        .move
    }

    nonisolated func draggingSession(_: NSDraggingSession, movedTo screenPoint: NSPoint) {
        MainActor.assumeIsolated { onDragMoved?(paneID, screenPoint) }
    }

    nonisolated func draggingSession(_: NSDraggingSession, endedAt _: NSPoint, operation _: NSDragOperation) {
        MainActor.assumeIsolated {
            dragging = false
            pressed = nil
            onDragEnded?(paneID)
        }
    }
}

import AppKit

/// While the sidebar is hidden, it peeks in over the terminal when the pointer reaches the
/// window's left edge, and slides away once the pointer leaves it (UIUX.md → Motion → Sidebar).
@MainActor
final class SidebarPeek {
    private weak var container: NSView?
    private let width: CGFloat
    private let makeSidebar: () -> NSView
    private let sensor = EdgeSensor()
    private var panel: PeekPanel?
    private var hideTask: Task<Void, Never>?

    var isEnabled = false {
        didSet {
            sensor.isHidden = !isEnabled
            if !isEnabled {
                hide(animated: false)
            }
        }
    }

    init(container: NSView, width: CGFloat, makeSidebar: @escaping () -> NSView) {
        self.container = container
        self.width = width
        self.makeSidebar = makeSidebar
        sensor.isHidden = true
        sensor.onEnter = { [weak self] in self?.show() }
        sensor.frame = NSRect(x: 0, y: 0, width: 6, height: container.bounds.height)
        sensor.autoresizingMask = [.height]
        container.addSubview(sensor)
    }

    private func show() {
        hideTask?.cancel()
        guard isEnabled, panel == nil, let container else { return }
        let panel = PeekPanel(frame: NSRect(x: -width, y: 0, width: width, height: container.bounds.height))
        panel.autoresizingMask = [.height]
        panel.onEnter = { [weak self] in self?.hideTask?.cancel() }
        panel.onExit = { [weak self] in self?.scheduleHide() }
        let sidebar = makeSidebar()
        sidebar.frame = panel.bounds
        sidebar.autoresizingMask = [.width, .height]
        panel.addSubview(sidebar)
        container.addSubview(panel, positioned: .above, relativeTo: nil)
        self.panel = panel
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Motion.duration(0.2)
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().frame.origin.x = 0
        }
    }

    #if DEBUG
        /// Tracking areas need a real pointer; self-tests call this instead.
        func showForTesting() {
            show()
        }
    #endif

    private func scheduleHide() {
        hideTask?.cancel()
        hideTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            self?.hide(animated: true)
        }
    }

    func hide(animated: Bool) {
        hideTask?.cancel()
        guard let panel else { return }
        self.panel = nil
        let duration = animated ? Motion.duration(0.18) : 0
        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().frame.origin.x = -panel.frame.width
        }
        // Timed, not a completion handler: the panel must never linger over the terminal.
        Task {
            try? await Task.sleep(for: .seconds(duration))
            panel.removeFromSuperview()
        }
    }
}

/// A thin strip at the window edge that notices the pointer without taking clicks.
private final class EdgeSensor: NSView {
    var onEnter: (() -> Void)?

    override func hitTest(_: NSPoint) -> NSView? {
        nil
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInKeyWindow], owner: self))
    }

    override func mouseEntered(with _: NSEvent) {
        onEnter?()
    }
}

/// The floating sidebar, with a soft shadow on its trailing edge.
private final class PeekPanel: NSView {
    var onEnter: (() -> Void)?
    var onExit: (() -> Void)?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.shadowColor = NSColor.black.cgColor
        layer?.shadowOpacity = 0.25
        layer?.shadowRadius = 16
        layer?.shadowOffset = .zero
        layer?.masksToBounds = false
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("not supported")
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInKeyWindow], owner: self))
    }

    override func mouseEntered(with _: NSEvent) {
        onEnter?()
    }

    override func mouseExited(with _: NSEvent) {
        onExit?()
    }
}

import AppKit
import CalmModel

/// Dropping a session onto the split (UIUX.md → Split panes): a card dragged from the sidebar, or a
/// pane dragged by its icon, lands beside the pane under the pointer, on the side it is nearest.
/// A dotted outline, the one links and table cells use, shows the half the new pane would take.
extension TerminalWorkspaceView {
    static let sessionDragType = NSPasteboard.PasteboardType(SessionDrag.typeIdentifier)

    // MARK: NSDraggingDestination

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        draggingUpdated(sender)
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard let (_, drop) = incomingDrop(sender) else {
            hideLanding()
            return []
        }
        showLanding(drop)
        let mask = sender.draggingSourceOperationMask
        return mask.contains(.move) ? .move : mask.contains(.copy) ? .copy : .generic
    }

    override func draggingExited(_: NSDraggingInfo?) {
        hideLanding()
    }

    override func draggingEnded(_: NSDraggingInfo) {
        hideLanding()
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        defer { hideLanding() }
        guard let (drag, drop) = incomingDrop(sender) else { return false }
        return onSessionDrop?(drag, drop.target, drop.direction) ?? false
    }

    /// The session being dragged and where letting go would put it, if anywhere: not while a pane
    /// is zoomed (the others aren't there to land beside), not over the pane's middle, and never
    /// beside the session itself.
    private func incomingDrop(_ sender: NSDraggingInfo) -> (SessionDrag, SplitTree<UUID>.Drop)? {
        guard zoomedPane == nil, let tree, bounds.width > 0, bounds.height > 0,
              let drag = Self.sessionDrag(from: sender.draggingPasteboard) ?? ActiveSessionDrag.current
        else { return nil }
        let point = convert(sender.draggingLocation, from: nil)
        guard let drop = tree.drop(at: point.x / bounds.width, point.y / bounds.height, excluding: drag.sessionID) else { return nil }
        return (drag, drop)
    }

    private static func sessionDrag(from pasteboard: NSPasteboard) -> SessionDrag? {
        pasteboard.data(forType: sessionDragType)
            .flatMap { String(data: $0, encoding: .utf8) }
            .flatMap(SessionDrag.init(text:))
    }

    // MARK: Landing

    /// Where the dropped pane would be, in this view.
    private func landingRect(for drop: SplitTree<UUID>.Drop) -> NSRect? {
        guard let frame = tree?.frames()[drop.target] else { return nil }
        let half = SplitTree<UUID>.landingFrame(of: frame, toward: drop.direction)
        return NSRect(
            x: half.x * bounds.width,
            y: half.y * bounds.height,
            width: half.width * bounds.width,
            height: half.height * bounds.height,
        )
    }

    func showLanding(_ drop: SplitTree<UUID>.Drop) {
        guard let rect = landingRect(for: drop) else { return }
        let view = landing ?? LandingView()
        let first = landing == nil || view.alphaValue == 0
        landing = view
        view.isDark = handleIsDark
        if view.superview !== self {
            addSubview(view)
        }
        // Above the panes, their veils and the icons, wherever the last pane was added.
        if subviews.last !== view {
            addSubview(view, positioned: .above, relativeTo: nil)
        }
        if first || Motion.isReduced {
            view.frame = rect
        } else {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.12
                context.allowsImplicitAnimation = true
                view.animator().frame = rect
            }
        }
        Motion.fade(view, to: 1, duration: 0.12)
    }

    func hideLanding() {
        guard let landing, landing.alphaValue > 0 else { return }
        Motion.fade(landing, to: 0, duration: 0.12)
    }
}

/// The dotted outline round the half a dropped pane would take, and a hush of the chrome's ink
/// inside it. The dots are the links' own: round, 1.5 pt, spaced four apart.
@MainActor
final class LandingView: NSView {
    var isDark = true {
        didSet { updateColors() }
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        alphaValue = 0
        if let outline = layer as? CAShapeLayer {
            outline.lineWidth = 1.5
            outline.lineCap = .round
            outline.lineDashPattern = [0.01, 4]
        }
        updateColors()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("not supported")
    }

    override func makeBackingLayer() -> CALayer {
        CAShapeLayer()
    }

    override var isFlipped: Bool {
        true
    }

    override func layout() {
        super.layout()
        // Five points inside the half, so the outline sits in the pane and not on its edge.
        let inset = bounds.insetBy(dx: 5, dy: 5)
        (layer as? CAShapeLayer)?.path = CGPath(roundedRect: inset, cornerWidth: 9, cornerHeight: 9, transform: nil)
    }

    private func updateColors() {
        let ink = isDark ? NSColor.white : NSColor.black
        guard let outline = layer as? CAShapeLayer else { return }
        outline.strokeColor = ink.withAlphaComponent(0.6).cgColor
        outline.fillColor = ink.withAlphaComponent(0.04).cgColor
    }

    override func hitTest(_: NSPoint) -> NSView? {
        nil
    }
}

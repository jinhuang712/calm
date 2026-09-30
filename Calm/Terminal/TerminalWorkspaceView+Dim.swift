import AppKit
import CalmModel

/// In a split the pane you're in is the bright one and the others recede (UIUX.md → Split
/// panes), and a pane that closes folds toward the one that takes its room.
extension TerminalWorkspaceView {
    static let veilDuration: TimeInterval = 0.16
    static let foldDuration: TimeInterval = 0.22

    // MARK: Dim

    /// The layout's focus moved to `id`: that pane brightens and the others recede.
    func setFocused(_ id: UUID?) {
        guard focusedID != id else { return }
        focusedID = id
        refreshVeils(animated: true)
    }

    /// A close question is on `id` (or, with nil, is gone): the other panes almost disappear
    /// while it's up, so the pane it is about is the one that's left.
    func setAsked(_ id: UUID?) {
        guard askedID != id else { return }
        askedID = id
        refreshVeils(animated: true)
    }

    /// The pane `id` is being dragged out of the split and is over the sidebar, where letting go
    /// takes it out (or, with nil, it isn't): it all but goes, so the drag says what it will do.
    func setLeaving(_ id: UUID?) {
        guard leavingID != id else { return }
        leavingID = id
        refreshVeils(animated: true)
    }

    /// The pane `id` when a question can sit on it: the window is split and the pane is on screen.
    func askablePane(_ id: UUID) -> TerminalSurfaceView? {
        guard hasSplits, let pane = panes[id], !pane.isHidden else { return nil }
        return pane
    }

    func veilView(for id: UUID) -> VeilView {
        if let veil = veilViews[id] {
            return veil
        }
        let veil = VeilView()
        veil.alphaValue = 0
        veils.addSubview(veil)
        veilViews[id] = veil
        return veil
    }

    /// Sets each veil's strength and color: the terminal's own background, so a pane fades into
    /// what's behind its text (a full-screen app that paints its own, OpenCode, fades into that).
    func refreshVeils(animated: Bool) {
        let splits = hasSplits && zoomedPane == nil
        // A focus that's not among the panes (its pane just closed) leaves none of them dimmed.
        let focusIsHere = focusedID.flatMap { panes[$0] } != nil
        for (id, pane) in panes {
            let veil = veilView(for: id)
            veil.isHidden = pane.isHidden
            veil.color = pane.topEdgeColor ?? pane.effectiveBackgroundColor ?? .black
            let strength = PaneDim.veil(
                isFocused: !focusIsHere || id == focusedID, hasSplits: splits,
                isAsked: id == askedID, asking: askedID != nil, isLeaving: id == leavingID,
            )
            Motion.fade(veil, to: strength, duration: animated ? Self.veilDuration : 0)
        }
        refreshClearing(animated: animated)
        refreshHandles(animated: animated)
    }

    /// The question's clearing lies over the asked pane, in that pane's own colors, and is gone
    /// when nothing is asked.
    private func refreshClearing(animated: Bool) {
        let duration = animated ? Self.veilDuration : 0
        guard let id = askedID, let veil = veilViews[id] else {
            if let clearing {
                Motion.fade(clearing, to: 0, duration: duration)
            }
            return
        }
        let clearing = clearing ?? ClearingView()
        self.clearing = clearing
        // Added last each time: a pane made since would otherwise put its veil over it.
        veils.addSubview(clearing)
        clearing.frame = veil.frame
        clearing.color = veil.color
        Motion.fade(clearing, to: 1, duration: duration)
    }

    // MARK: Fold

    /// A pane that closes doesn't just vanish: it folds toward the pane that takes its room, so
    /// the eye follows where it went. Its surface is freed right after, so a still copy of its
    /// last frame (the IOSurface libghostty handed its layer) does the folding, above the panes
    /// that grow into the gap. Nothing for a lone pane, a hidden or zoomed one, or Reduce Motion.
    func foldAway(_ pane: TerminalSurfaceView, in tree: SplitTree<UUID>) {
        guard !Motion.isReduced, zoomedPane == nil, !pane.isHidden, tree.leaves.count > 1, veils.superview === self,
              let contents = pane.layer?.contents, let unit = tree.collapsedFrame(of: pane.id)
        else { return }
        let from = pane.frame
        let to = NSRect(
            x: unit.x * bounds.width, y: unit.y * bounds.height,
            width: unit.width * bounds.width, height: unit.height * bounds.height,
        )
        let ghost = GhostView(frame: to, picture: contents, scale: pane.layer?.contentsScale ?? 2)
        guard let layer = ghost.layer else { return }
        addSubview(ghost, positioned: .below, relativeTo: veils)

        let duration = Self.foldDuration
        let position = CABasicAnimation(keyPath: "position")
        position.fromValue = NSPoint(x: from.midX, y: from.midY)
        let size = CABasicAnimation(keyPath: "bounds.size")
        size.fromValue = from.size
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 1
        fade.toValue = 0
        let group = CAAnimationGroup()
        group.animations = [position, size, fade]
        group.duration = duration
        group.timingFunction = CAMediaTimingFunction(name: .easeIn)
        // Final values are the sliver and nothing; the view is gone by the time they'd show.
        ghost.alphaValue = 0
        layer.add(group, forKey: "calm.fold")
        Task {
            try? await Task.sleep(for: .seconds(duration + 0.05))
            ghost.removeFromSuperview()
        }
    }
}

/// A still picture of a pane's last frame, for the fold. Layer-backed, with the picture set in
/// `updateLayer`: that is how AppKit is told to leave a layer's contents alone (it paints them
/// itself otherwise, and a picture assigned from outside vanishes).
@MainActor
final class GhostView: NSView {
    private let picture: Any
    private let scale: CGFloat

    init(frame: NSRect, picture: Any, scale: CGFloat) {
        self.picture = picture
        self.scale = scale
        super.init(frame: frame)
        wantsLayer = true
        showPicture()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("not supported")
    }

    override var wantsUpdateLayer: Bool {
        true
    }

    override func updateLayer() {
        showPicture()
    }

    private func showPicture() {
        guard let layer else { return }
        layer.contents = picture
        layer.contentsScale = scale
        // The picture keeps its size and place while the frame narrows around it.
        layer.contentsGravity = .topLeft
        layer.masksToBounds = true
    }

    override func hitTest(_: NSPoint) -> NSView? {
        nil
    }
}

/// The layer that holds the veils. It takes no clicks: a click on a receding pane focuses it.
@MainActor
final class VeilsView: NSView {
    override var isFlipped: Bool {
        true
    }

    override func hitTest(_: NSPoint) -> NSView? {
        nil
    }
}

/// The clearing (PaneDim.clearing): the asked pane's background thickening toward its middle, so
/// the question's words stand on a calm ground instead of on the terminal text.
@MainActor
final class ClearingView: NSView {
    var color = NSColor.black {
        didSet { updateColors() }
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        alphaValue = 0
        if let gradient = layer as? CAGradientLayer {
            gradient.type = .radial
            gradient.startPoint = CGPoint(x: 0.5, y: 0.5)
            // A radial gradient reaches as far from its start as the end point is, on each axis.
            gradient.endPoint = CGPoint(x: 0.5 + PaneDim.clearingReach.width, y: 0.5 + PaneDim.clearingReach.height)
            gradient.locations = PaneDim.clearing.map { NSNumber(value: $0.location) }
        }
        updateColors()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("not supported")
    }

    override func makeBackingLayer() -> CALayer {
        CAGradientLayer()
    }

    private func updateColors() {
        (layer as? CAGradientLayer)?.colors = PaneDim.clearing.map { color.withAlphaComponent($0.opacity).cgColor }
    }

    override func hitTest(_: NSPoint) -> NSView? {
        nil
    }
}

/// A veil: a flat layer of the pane's background, seen through at `alphaValue`.
@MainActor
final class VeilView: NSView {
    var color = NSColor.black {
        didSet {
            layer?.backgroundColor = color.cgColor
        }
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = color.cgColor
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("not supported")
    }

    override func hitTest(_: NSPoint) -> NSView? {
        nil
    }
}

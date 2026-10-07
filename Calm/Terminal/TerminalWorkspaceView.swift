import AppKit
import CalmModel

/// Lays out terminal panes from a `SplitTree`, with draggable dividers and gentle motion.
@MainActor
final class TerminalWorkspaceView: NSView {
    private(set) var tree: SplitTree<UUID>?
    private(set) var panes: [UUID: TerminalSurfaceView] = [:]
    private var dividers: [DividerView] = []
    private(set) var zoomedPane: UUID?
    /// The dotted lines under links that open, above the panes (they can't take subviews).
    private let linkMarks = LinkMarksView()
    /// Find's underlines and band (FEATURES.md → F16), over the panes like the link marks.
    private let findMarks = FindMarksView()
    /// Find's map, beside the pane being searched (one at a time).
    private let findMap = FindMapView()
    /// The veils over the panes that recede in a split, above the panes and their marks
    /// (TerminalWorkspaceView+Dim).
    let veils = VeilsView()
    var veilViews: [UUID: VeilView] = [:]
    /// The soft space the close question stands in, over the asked pane's veil (made when first needed).
    var clearing: ClearingView?
    /// The pane the layout's focus is on: the others recede. Not the first responder, so a
    /// question on another pane, or the window losing focus, leaves the dim as it is.
    var focusedID: UUID?
    /// The pane a close question is on: while it is up the others almost go.
    var askedID: UUID?
    /// The pane being dragged out of the split, while it is over the sidebar: it all but goes.
    var leavingID: UUID?

    /// The split icons, above the veils (TerminalWorkspaceView+Handles).
    let handles = HandlesView()
    var handleViews: [UUID: SplitHandleView] = [:]
    /// The pane the pointer is on, for its icon.
    var hoveredID: UUID?
    /// The pane whose icon's menu is open or which is being dragged by its icon: its icon stays.
    var busyHandleID: UUID?
    /// Whether the chrome is dark: the icons and their tiles are drawn in white, or in black.
    var handleIsDark = true {
        didSet { handleViews.values.forEach { $0.isDark = handleIsDark } }
    }

    /// The icon was clicked: the window controller has the menu (the pane is already focused).
    var onHandleClick: ((UUID, SplitHandleView) -> Void)?
    /// The icon is being dragged: the window controller says how it looks and what letting go does.
    var onHandleDrag: ((UUID) -> NSDraggingItem?)?
    var onHandleDragMoved: ((UUID, NSPoint) -> Void)?
    var onHandleDragEnded: ((UUID) -> Void)?
    /// A session was dropped beside pane `target`, on `direction`'s side of it.
    var onSessionDrop: ((SessionDrag, UUID, SplitTree<UUID>.Direction) -> Bool)?
    /// Where a dragged session would land, drawn as a dotted outline (TerminalWorkspaceView+SessionDrop).
    var landing: LandingView?

    var dividerColor = NSColor(white: 1, alpha: 0.08) {
        didSet { dividers.forEach { $0.color = dividerColor } }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        // Sessions dragged from the sidebar, or by a pane's icon, land here; the panes themselves
        // take files and text, never this type.
        registerForDraggedTypes([Self.sessionDragType])
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("not supported")
    }

    /// Visual gap between panes, in points. The divider's grab area is wider.
    static let gap: CGFloat = 1
    static let animationDuration: TimeInterval = 0.18

    override var isFlipped: Bool {
        true
    }

    // MARK: Structure

    /// Rebuilds the view from a saved layout, making each pane at its size in the view (so lay
    /// the view out first): a pane's shell starts at the size it's made with.
    func restore(tree: SplitTree<UUID>, makePane: (UUID, NSSize?) -> TerminalSurfaceView?) {
        let frames = paneFrames(tree)
        var present: [UUID: TerminalSurfaceView] = [:]
        for id in tree.leaves {
            present[id] = makePane(id, frames[id]?.size)
        }
        guard !present.isEmpty else { return }
        var pruned: SplitTree<UUID>? = tree
        for id in tree.leaves where present[id] == nil {
            pruned = pruned?.removing(id)
        }
        self.tree = pruned
        self.panes = present
        present.values.forEach { addSubview($0) }
        layoutPanes(animated: false)
    }

    /// Takes a pane out of the layout without ending its surface (the session manager does that).
    func detach(_ pane: TerminalSurfaceView) {
        guard let tree else { return }
        foldAway(pane, in: tree)
        if zoomedPane == pane.id {
            zoomedPane = nil
        }
        panes[pane.id] = nil
        pane.removeFromSuperview()
        self.tree = tree.removing(pane.id)
        if self.tree != nil {
            // The panes that stay take their final frames at once, and the closed pane's ghost
            // folds away over them (foldAway): the terminal is resized once, not on every step of
            // a glide, and nothing depends on AppKit's frame animation, which stalls when the
            // close comes from a deferred callback rather than an event.
            layoutPanes(animated: false)
        }
    }

    func setRoot(_ pane: TerminalSurfaceView) {
        panes = [pane.id: pane]
        tree = .leaf(pane.id)
        addSubview(pane)
        layoutPanes(animated: false)
    }

    /// Adds `newPane` next to `target`. The new pane grows in from the split edge.
    func split(_ target: TerminalSurfaceView, direction: SplitTree<UUID>.Direction, with newPane: TerminalSurfaceView) {
        guard let tree, tree.contains(target.id) else { return }
        zoomedPane = nil
        panes[newPane.id] = newPane
        self.tree = tree.splitting(target.id, direction: direction, with: newPane.id)

        // Start the new pane collapsed at the edge it grows from.
        let from = target.frame
        newPane.frame = switch direction {
        case .right: NSRect(x: from.maxX, y: from.minY, width: 0, height: from.height)
        case .left: NSRect(x: from.minX, y: from.minY, width: 0, height: from.height)
        case .down: NSRect(x: from.minX, y: from.maxY, width: from.width, height: 0)
        case .up: NSRect(x: from.minX, y: from.minY, width: from.width, height: 0)
        }
        addSubview(newPane)
        layoutPanes(animated: true)
    }

    /// Removes a pane; its sibling takes the space. Returns false when it was the last pane.
    @discardableResult
    func remove(_ pane: TerminalSurfaceView) -> Bool {
        guard let tree else { return false }
        if zoomedPane == pane.id {
            zoomedPane = nil
        }
        let remaining = tree.removing(pane.id)
        panes[pane.id] = nil
        pane.removeFromSuperview()
        pane.teardown()
        self.tree = remaining
        guard remaining != nil else { return false }
        layoutPanes(animated: true)
        return true
    }

    func neighbor(of pane: TerminalSurfaceView, toward direction: SplitTree<UUID>.Direction) -> TerminalSurfaceView? {
        tree?.neighbor(of: pane.id, toward: direction).flatMap { panes[$0] }
    }

    /// Next or previous pane in reading order, wrapping around.
    func cycle(from pane: TerminalSurfaceView, forward: Bool) -> TerminalSurfaceView? {
        guard let leaves = tree?.leaves, leaves.count > 1, let index = leaves.firstIndex(of: pane.id) else { return nil }
        let next = (index + (forward ? 1 : -1) + leaves.count) % leaves.count
        return panes[leaves[next]]
    }

    var orderedPanes: [TerminalSurfaceView] {
        (tree?.leaves ?? []).compactMap { panes[$0] }
    }

    var hasSplits: Bool {
        (tree?.leaves.count ?? 0) > 1
    }

    func resize(_ pane: TerminalSurfaceView, direction: SplitTree<UUID>.Direction, byPoints amount: CGFloat) -> Bool {
        guard let tree, hasSplits, let frame = tree.frames()[pane.id] else { return false }
        // Grow the pane toward `direction` by moving the shared divider.
        let span = direction == .left || direction == .right ? bounds.width : bounds.height
        guard span > 0 else { return false }
        let delta = Double(amount / span)
        let paneRatio = direction == .left || direction == .right ? frame.width : frame.height
        let signed = direction == .right || direction == .down ? delta : -delta
        _ = paneRatio
        self.tree = adjust(tree, around: pane.id, axis: direction == .left || direction == .right ? .horizontal : .vertical, by: signed)
        layoutPanes(animated: false)
        return true
    }

    func equalize() {
        tree = tree?.equalized()
        layoutPanes(animated: true)
    }

    func toggleZoom(_ pane: TerminalSurfaceView) -> Bool {
        guard hasSplits else { return false }
        zoomedPane = zoomedPane == pane.id ? nil : pane.id
        layoutPanes(animated: true)
        return true
    }

    // MARK: Link marks

    override func didAddSubview(_ subview: NSView) {
        super.didAddSubview(subview)
        guard let pane = subview as? TerminalSurfaceView else { return }
        // Each set of marks steps aside for the other (UIUX.md → Find, links), so both redraw.
        let redraw = { [weak self, weak pane] in
            guard let self, let pane else { return }
            linkMarks.update(pane)
            findMarks.update(pane)
            updateFindMap(pane)
        }
        pane.links.onChange = redraw
        pane.find.onChange = redraw
    }

    override func willRemoveSubview(_ subview: NSView) {
        if let pane = subview as? TerminalSurfaceView {
            pane.links.onChange = nil
            pane.find.onChange = nil
            linkMarks.remove(pane.id)
            findMarks.forget(pane.id)
            if findMap.paneID == pane.id {
                findMap.hide()
            }
            veilViews.removeValue(forKey: pane.id)?.removeFromSuperview()
            handleViews.removeValue(forKey: pane.id)?.removeFromSuperview()
            if hoveredID == pane.id {
                hoveredID = nil
            }
            if busyHandleID == pane.id {
                busyHandleID = nil
            }
        }
        super.willRemoveSubview(subview)
    }

    /// Keeps the marks above the panes and in step with them.
    private func layoutLinkMarks(animated: Bool) {
        let lastPane = subviews.lastIndex { $0 is TerminalSurfaceView }
        if let lastPane, (subviews.firstIndex(of: linkMarks) ?? -1) < lastPane {
            addSubview(linkMarks, positioned: .above, relativeTo: subviews[lastPane])
        }
        linkMarks.frame = bounds
        if (subviews.firstIndex(of: findMarks) ?? -1) < (subviews.firstIndex(of: linkMarks) ?? 0) {
            addSubview(findMarks, positioned: .above, relativeTo: linkMarks)
        }
        findMarks.frame = bounds
        // The veils lie over the marks, so a receding pane's marks recede with its text.
        if (subviews.firstIndex(of: veils) ?? -1) < (subviews.firstIndex(of: findMarks) ?? 0) {
            addSubview(veils, positioned: .above, relativeTo: findMarks)
        }
        veils.frame = bounds
        // The icons lie over the veils and the question's clearing: a receding pane's icon stays as
        // quiet as it is, and the clearing never covers it.
        if (subviews.firstIndex(of: handles) ?? -1) < (subviews.firstIndex(of: veils) ?? 0) {
            addSubview(handles, positioned: .above, relativeTo: veils)
        }
        handles.frame = bounds
        // The map takes the pointer, so it lies over everything else on the panes.
        if subviews.last !== findMap {
            addSubview(findMap, positioned: .above, relativeTo: nil)
        }
        for pane in panes.values {
            if animated {
                pane.resetLinkMarks() // the pane is about to change size; its text will move
                pane.resetFindMarks()
            } else {
                linkMarks.update(pane)
                findMarks.update(pane)
                updateFindMap(pane)
            }
        }
    }

    /// Shows `pane`'s map, or hides the map if it was `pane`'s and has nothing to show now.
    private func updateFindMap(_ pane: TerminalSurfaceView) {
        guard pane.showsFindMap, !pane.isHidden else {
            if findMap.paneID == pane.id {
                findMap.hide(fading: pane.find.words == nil)
            }
            return
        }
        findMap.update(pane, frame: pane.frame, inSplit: hasSplits && zoomedPane == nil, colors: findMarks.colors(for: pane))
    }

    #if DEBUG
        var findMapForTesting: String {
            findMap.descriptionForTesting
        }

        func findMarksForTesting(_ paneID: UUID) -> String {
            findMarks.descriptionForTesting(paneID)
        }

        func hoverFindMapForTesting(line: Int?) {
            findMap.hoverForTesting(line: line)
        }
    #endif

    // MARK: Layout

    override func layout() {
        super.layout()
        layoutPanes(animated: false)
    }

    func layoutPanes(animated: Bool) {
        guard let tree else { return }
        defer { layoutLinkMarks(animated: animated) }
        let frames = paneFrames(tree)
        let apply = {
            for (id, frame) in frames {
                guard let pane = self.panes[id] else { continue }
                pane.isHidden = false
                let veil = self.veilView(for: id)
                let handle = self.handleView(for: id)
                let corner = Self.handleFrame(in: frame)
                if animated {
                    pane.animator().frame = frame
                    veil.animator().frame = frame
                    handle.animator().frame = corner
                } else {
                    pane.frame = frame
                    veil.frame = frame
                    handle.frame = corner
                }
            }
            if let zoomed = self.zoomedPane {
                for (id, pane) in self.panes where id != zoomed {
                    pane.isHidden = true
                }
            }
        }
        if animated, !Motion.isReduced {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = Self.animationDuration
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                context.allowsImplicitAnimation = true
                apply()
            }
        } else {
            apply()
        }
        refreshVeils(animated: animated)
        rebuildDividers(tree)
    }

    private func paneFrames(_ tree: SplitTree<UUID>) -> [UUID: NSRect] {
        if let zoomed = zoomedPane {
            return [zoomed: bounds]
        }
        var result: [UUID: NSRect] = [:]
        for (id, unit) in tree.frames() {
            var rect = NSRect(
                x: unit.x * bounds.width, y: unit.y * bounds.height,
                width: unit.width * bounds.width, height: unit.height * bounds.height,
            )
            // Leave a hairline gap on inner edges; keep outer edges flush.
            if unit.x > 0 {
                rect.origin.x += Self.gap / 2
                rect.size.width -= Self.gap / 2
            }
            if unit.x + unit.width < 0.999 {
                rect.size.width -= Self.gap / 2
            }
            if unit.y > 0 {
                rect.origin.y += Self.gap / 2
                rect.size.height -= Self.gap / 2
            }
            if unit.y + unit.height < 0.999 {
                rect.size.height -= Self.gap / 2
            }
            result[id] = backingAlignedRect(rect, options: .alignAllEdgesNearest)
        }
        return result
    }

    // MARK: Dividers

    private func rebuildDividers(_ tree: SplitTree<UUID>) {
        dividers.forEach { $0.removeFromSuperview() }
        dividers = []
        guard zoomedPane == nil else { return }
        collectDividers(tree, in: NSRect(x: 0, y: 0, width: 1, height: 1), path: [])
    }

    private func collectDividers(_ tree: SplitTree<UUID>, in unit: NSRect, path: [Bool]) {
        guard case let .split(axis, ratio, first, second) = tree else { return }
        let firstUnit: NSRect
        let secondUnit: NSRect
        let line: NSRect
        switch axis {
        case .horizontal:
            let splitX = unit.minX + unit.width * ratio
            firstUnit = NSRect(x: unit.minX, y: unit.minY, width: unit.width * ratio, height: unit.height)
            secondUnit = NSRect(x: splitX, y: unit.minY, width: unit.width * (1 - ratio), height: unit.height)
            line = NSRect(x: splitX * bounds.width - 3, y: unit.minY * bounds.height, width: 6, height: unit.height * bounds.height)
        case .vertical:
            let splitY = unit.minY + unit.height * ratio
            firstUnit = NSRect(x: unit.minX, y: unit.minY, width: unit.width, height: unit.height * ratio)
            secondUnit = NSRect(x: unit.minX, y: splitY, width: unit.width, height: unit.height * (1 - ratio))
            line = NSRect(x: unit.minX * bounds.width, y: splitY * bounds.height - 3, width: unit.width * bounds.width, height: 6)
        }
        let divider = DividerView(axis: axis, color: dividerColor)
        divider.frame = line
        divider.onDrag = { [weak self] location in
            self?.dragDivider(path: path, axis: axis, unit: unit, to: location)
        }
        addSubview(divider)
        dividers.append(divider)
        collectDividers(first, in: firstUnit, path: path + [false])
        collectDividers(second, in: secondUnit, path: path + [true])
    }

    private func dragDivider(path: [Bool], axis: SplitTree<UUID>.Axis, unit: NSRect, to location: NSPoint) {
        guard let tree else { return }
        let ratio: Double = switch axis {
        case .horizontal: (location.x / bounds.width - unit.minX) / unit.width
        case .vertical: (location.y / bounds.height - unit.minY) / unit.height
        }
        self.tree = setRatio(tree, path: path, ratio: ratio)
        layoutPanes(animated: false)
    }

    private func setRatio(_ tree: SplitTree<UUID>, path: [Bool], ratio: Double) -> SplitTree<UUID> {
        guard case let .split(axis, current, first, second) = tree else { return tree }
        guard let step = path.first else {
            return .split(axis, ratio: min(max(ratio, 0.1), 0.9), first: first, second: second)
        }
        let rest = Array(path.dropFirst())
        return step
            ? .split(axis, ratio: current, first: first, second: setRatio(second, path: rest, ratio: ratio))
            : .split(axis, ratio: current, first: setRatio(first, path: rest, ratio: ratio), second: second)
    }

    /// Moves the nearest divider on `axis` around `leaf` by `delta` (a fraction of the whole area).
    private func adjust(_ tree: SplitTree<UUID>, around leaf: UUID, axis: SplitTree<UUID>.Axis, by delta: Double) -> SplitTree<UUID> {
        guard case let .split(splitAxis, ratio, first, second) = tree else { return tree }
        let inFirst = first.contains(leaf)
        let child = inFirst ? first : second
        // Prefer the innermost split on this axis.
        let adjustedChild = adjust(child, around: leaf, axis: axis, by: delta)
        if adjustedChild != child {
            return inFirst
                ? .split(splitAxis, ratio: ratio, first: adjustedChild, second: second)
                : .split(splitAxis, ratio: ratio, first: first, second: adjustedChild)
        }
        guard splitAxis == axis else { return tree }
        return .split(splitAxis, ratio: min(max(ratio + delta, 0.1), 0.9), first: first, second: second)
    }
}

/// A thin, draggable divider between panes.
@MainActor
final class DividerView: NSView {
    let axis: SplitTree<UUID>.Axis
    var color: NSColor {
        didSet { needsDisplay = true }
    }

    var onDrag: ((NSPoint) -> Void)?

    init(axis: SplitTree<UUID>.Axis, color: NSColor) {
        self.axis = axis
        self.color = color
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("not supported")
    }

    override func draw(_: NSRect) {
        color.setFill()
        let line = axis == .horizontal
            ? NSRect(x: bounds.midX - 0.5, y: 0, width: 1, height: bounds.height)
            : NSRect(x: 0, y: bounds.midY - 0.5, width: bounds.width, height: 1)
        line.fill()
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: axis == .horizontal ? .resizeLeftRight : .resizeUpDown)
    }

    override func mouseDragged(with event: NSEvent) {
        guard let superview else { return }
        onDrag?(superview.convert(event.locationInWindow, from: nil))
    }
}

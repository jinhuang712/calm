import AppKit
import CalmModel

/// Find's map (FEATURES.md → F16, UIUX.md → Find): along the searched pane's right edge, a tick
/// for every line of the scrollback with a match and a box for the part on screen. Under the
/// pointer it widens and names the line nearest it; a click makes that line's first match the
/// current one. It shows only while there's more log than the screen holds (`showsFindMap`).
@MainActor
final class FindMapView: NSView {
    private weak var pane: TerminalSurfaceView?
    /// The pane whose map this is, while it shows (not while it fades away).
    var paneID: UUID? {
        isHidden || isFading ? nil : pane?.id
    }

    private var colors: FindColors?
    private var text: NSColor = .textColor
    private var hovered: Int?
    private var isWide = false
    private let currentTick = CALayer()
    /// The current tick's line and its pane, so moving to another line slides it there.
    private var currentTickLine: (pane: UUID, line: Int)?
    /// New output's ticks, fading in over the map before the drawing takes them (`fresh`).
    private let freshTicks = CAShapeLayer()
    private var fresh: Set<Int> = []
    /// The lines drawn last, by number, and for which pane and words.
    private var drawn: (key: String, numbers: Set<Int>)?
    private var isFading = false
    /// Bumped by each show and hide, so a fade that finishes after the map came back leaves it.
    private var generation = 0
    private let tagView = FindMapTag()
    private var trackingArea: NSTrackingArea?

    /// The track's width at rest and under the pointer; its gap from the pane's right edge, from
    /// its top and bottom, and from the top in a split (below the split icon).
    private static let width: CGFloat = 8
    private static let wideWidth: CGFloat = 14
    private static let edge: CGFloat = 3
    private static let inset: CGFloat = 6
    private static let splitInset: CGFloat = 30
    /// Room on the left for the current tick, which sticks out 2 pt.
    private static let stickOut: CGFloat = 2
    /// The current tick's slide, the widening under the pointer, new ticks' fade, closing's fade.
    private static let slide: TimeInterval = 0.18
    private static let widen: TimeInterval = 0.12
    private static let fadeIn: TimeInterval = 0.15
    private static let fadeOut: TimeInterval = 0.12

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        currentTick.cornerRadius = 1
        layer?.addSublayer(freshTicks)
        layer?.addSublayer(currentTick)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("not supported")
    }

    override var isFlipped: Bool {
        true
    }

    /// Shows `pane`'s map beside it (`frame` is the pane's, in the superview), or hides it.
    func update(_ pane: TerminalSurfaceView, frame paneFrame: NSRect, inSplit: Bool, colors: FindColors) {
        if isFading || isHidden {
            generation += 1
            isFading = false
            layer?.removeAnimation(forKey: "calm.fade")
            alphaValue = 1
        }
        self.pane = pane
        self.colors = colors
        text = NSColor(hex: colors.foreground) ?? .textColor
        let width = (isWide ? Self.wideWidth : Self.width) + Self.stickOut
        let top = inSplit ? Self.splitInset : Self.inset
        frame = NSRect(
            x: paneFrame.maxX - Self.edge - width, y: paneFrame.minY + Self.inset,
            width: width, height: max(paneFrame.height - Self.inset - top, 0),
        )
        isHidden = false
        fadeInNewTicks(of: pane)
        placeCurrentTick()
        needsDisplay = true
        if hovered != nil {
            showTag()
        }
    }

    /// Hides the map: fading when find closes, at once otherwise.
    func hide(fading: Bool = false) {
        guard !isHidden, !isFading else { return }
        hovered = nil
        tagView.removeFromSuperview()
        currentTickLine = nil
        drawn = nil
        generation += 1
        guard fading, !Motion.isReduced, let layer else {
            finishHiding()
            return
        }
        isFading = true
        let generation = generation
        CATransaction.begin()
        CATransaction.setCompletionBlock { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.generation == generation else { return }
                self.finishHiding()
            }
        }
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 1
        fade.toValue = 0
        fade.duration = Self.fadeOut
        fade.timingFunction = CAMediaTimingFunction(name: .easeIn)
        layer.opacity = 0
        layer.add(fade, forKey: "calm.fade")
        CATransaction.commit()
    }

    private func finishHiding() {
        isHidden = true
        isFading = false
        isWide = false
        alphaValue = 1
        layer?.opacity = 1
        pane = nil
    }

    /// Ticks for lines new since the map was last drawn (output arriving) fade in; the box stays
    /// where the user is reading. A map whose lines mostly changed (new words, a scrollback
    /// full enough to drop its top lines and number them again) appears at once.
    private func fadeInNewTicks(of pane: TerminalSurfaceView) {
        guard let map = pane.find.map else { return }
        let key = pane.id.uuidString + (pane.find.words ?? "")
        let numbers = Set(map.lines.map(\.number))
        defer { drawn = (key, numbers) }
        guard let drawn, drawn.key == key, !Motion.isReduced, let position = pane.find.position, let colors,
              let solid = NSColor(hex: colors.solid) else { return }
        let new = numbers.subtracting(drawn.numbers)
        guard !new.isEmpty, new.count * 2 <= numbers.count else { return }
        let track = track
        let path = CGMutablePath()
        for (index, line) in map.lines.enumerated() where new.contains(line.number) {
            guard let y = map.y(of: index, height: Double(track.height), total: position.total) else { continue }
            let top = min((CGFloat(y) / 2).rounded(.down) * 2, track.height - 2)
            path.addRect(CGRect(x: track.minX + 1, y: top, width: track.width - 2, height: 2))
        }
        fresh.formUnion(new)
        let generation = generation
        CATransaction.begin()
        CATransaction.setCompletionBlock { [weak self] in
            MainActor.assumeIsolated {
                // Faded in: the drawing takes them over.
                guard let self, self.generation == generation else { return }
                self.fresh = []
                self.freshTicks.path = nil
                self.needsDisplay = true
            }
        }
        CATransaction.setDisableActions(true)
        freshTicks.frame = bounds
        freshTicks.path = path
        freshTicks.fillColor = solid.withAlphaComponent(colors.tickAlpha).cgColor
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 0
        fade.toValue = 1
        fade.duration = Self.fadeIn
        fade.timingFunction = CAMediaTimingFunction(name: .easeOut)
        freshTicks.add(fade, forKey: "calm.fade")
        CATransaction.commit()
    }

    // MARK: Drawing

    private var track: NSRect {
        NSRect(x: Self.stickOut, y: 0, width: bounds.width - Self.stickOut, height: bounds.height)
    }

    override func draw(_: NSRect) {
        guard let pane, let map = pane.find.map, let position = pane.find.position, let colors,
              let solid = NSColor(hex: colors.solid) else { return }
        let track = track
        text.withAlphaComponent(isWide ? 0.1 : 0.06).setFill()
        NSBezierPath(roundedRect: track, xRadius: 4, yRadius: 4).fill()
        // One tick per matching line; lines sharing a 2 pt slot draw darker.
        let height = Double(track.height)
        let hoveredY = hovered.flatMap { map.y(of: $0, height: height, total: position.total) }
        let hidden = fresh.isEmpty ? nil : FindMap(lines: map.lines.filter { !fresh.contains($0.number) }, rows: map.rows)
        for tick in (hidden ?? map).ticks(height: height, total: position.total) {
            let strength = tick.lines >= 3 ? 0.95 : tick.lines == 2 ? 0.78 : colors.tickAlpha
            let isHovered = hoveredY.map { abs($0 - tick.y) < 2 } ?? false
            (isHovered ? text : solid.withAlphaComponent(strength)).setFill()
            NSBezierPath(rect: NSRect(x: track.minX + 1, y: CGFloat(tick.y), width: track.width - 2, height: 2)).fill()
        }
        // The part on screen.
        let boxHeight = max(track.height * CGFloat(position.visible) / CGFloat(position.total), 4)
        let box = NSRect(
            x: track.minX, y: min(track.height * CGFloat(position.offset) / CGFloat(position.total), track.height - boxHeight),
            width: track.width, height: boxHeight,
        )
        let outline = NSBezierPath(roundedRect: box.insetBy(dx: 0.5, dy: 0.5), xRadius: 4, yRadius: 4)
        outline.lineWidth = 1
        text.withAlphaComponent(0.3).setStroke()
        outline.stroke()
    }

    /// The current match's tick: 4 pt, solid, sticking out 2 pt to the left. A layer of its own,
    /// so it can slide (UIUX.md → Find, motion).
    private func placeCurrentTick() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        guard let pane, let line = pane.findMapCurrentLine, let position = pane.find.position,
              let y = pane.find.map?.y(of: line, height: Double(bounds.height), total: position.total),
              let solid = colors.flatMap({ NSColor(hex: $0.solid) }) else {
            currentTick.isHidden = true
            currentTickLine = nil
            return
        }
        // Another line of the same pane's map: the tick slides there, as the band does.
        let slides = !currentTick.isHidden && currentTickLine?.pane == pane.id && currentTickLine?.line != line && !Motion.isReduced
        currentTickLine = (pane.id, line)
        if slides {
            CATransaction.setDisableActions(false)
            CATransaction.setAnimationDuration(Self.slide)
            CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeOut))
        }
        currentTick.isHidden = false
        currentTick.backgroundColor = solid.cgColor
        // The view is flipped, and its layer with it: y runs down from the top, as the ticks'.
        let top = min(max(CGFloat(y) - 1, 0), bounds.height - 4)
        currentTick.frame = NSRect(x: 0, y: top, width: bounds.width - 1, height: 4)
    }

    // MARK: The pointer

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }
        let area = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect], owner: self)
        addTrackingArea(area)
        trackingArea = area
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .arrow)
    }

    override func mouseEntered(with event: NSEvent) {
        setWide(true)
        hover(at: event)
    }

    override func mouseMoved(with event: NSEvent) {
        hover(at: event)
    }

    override func mouseExited(with _: NSEvent) {
        hovered = nil
        tagView.removeFromSuperview()
        setWide(false)
    }

    override func mouseDown(with event: NSEvent) {
        guard let pane, let line = line(at: event) else { return }
        pane.goToFindLine(line)
    }

    /// The map's own clicks: the terminal under it never sees them.
    override func acceptsFirstMouse(for _: NSEvent?) -> Bool {
        true
    }

    private func setWide(_ wide: Bool) {
        guard wide != isWide, let pane, let superview else { return }
        isWide = wide
        let paneFrame = pane.convert(pane.bounds, to: superview)
        let width = (wide ? Self.wideWidth : Self.width) + Self.stickOut
        let target = NSRect(x: paneFrame.maxX - Self.edge - width, y: frame.minY, width: width, height: frame.height)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Motion.duration(Self.widen)
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            animator().frame = target
        }
        placeCurrentTick()
        needsDisplay = true
    }

    private func hover(at event: NSEvent) {
        let line = line(at: event)
        guard line != hovered else { return }
        hovered = line
        needsDisplay = true
        if line == nil {
            tagView.removeFromSuperview()
        } else {
            showTag()
        }
    }

    private func line(at event: NSEvent) -> Int? {
        guard let pane, let map = pane.find.map, let position = pane.find.position else { return nil }
        let point = convert(event.locationInWindow, from: nil)
        return map.line(near: Double(point.y), height: Double(bounds.height), total: position.total)
    }

    /// The tag beside the hovered tick: "line 2,405" and the line's text.
    private func showTag() {
        guard let pane, let superview, let hovered, let map = pane.find.map, map.lines.indices.contains(hovered),
              let position = pane.find.position, let colors,
              let y = map.y(of: hovered, height: Double(bounds.height), total: position.total) else {
            tagView.removeFromSuperview()
            return
        }
        let line = map.lines[hovered]
        tagView.show(number: line.number, text: line.text, colors: colors)
        if tagView.superview !== superview {
            superview.addSubview(tagView, positioned: .above, relativeTo: self)
        }
        let size = tagView.fittingSize
        let tick = convert(NSPoint(x: 0, y: CGFloat(y)), to: superview)
        let paneFrame = pane.convert(pane.bounds, to: superview)
        let x = max(paneFrame.minX + 6, frame.minX - 8 - size.width)
        let top = min(max(tick.y - size.height / 2, paneFrame.minY + 4), paneFrame.maxY - 4 - size.height)
        tagView.frame = NSRect(x: x, y: top, width: min(size.width, frame.minX - 8 - x), height: size.height)
    }

    #if DEBUG
        var descriptionForTesting: String {
            guard !isHidden, let pane, let map = pane.find.map else { return "no map" }
            let ticks = map.ticks(height: Double(bounds.height), total: pane.find.position?.total ?? 1)
            let current = pane.findMapCurrentLine.map(String.init) ?? "nil"
            return "map \(frame), \(map.lines.count) lines, \(ticks.count) ticks, current line \(current), "
                + "hovered \(hovered.map(String.init) ?? "nil")"
        }

        /// The pointer over `line`'s tick, as a mouse move would put it.
        func hoverForTesting(line: Int?) {
            setWide(line != nil)
            hovered = line
            needsDisplay = true
            if line == nil {
                tagView.removeFromSuperview()
            } else {
                showTag()
            }
        }
    #endif
}

/// The map's tag: the line's number and its text, on the ⌘-link tag's surface. Takes no clicks.
@MainActor
private final class FindMapTag: NSView {
    private let number = NSTextField(labelWithString: "")
    private let words = NSTextField(labelWithString: "")
    private let stack: NSStackView

    override init(frame: NSRect) {
        stack = NSStackView(views: [number, words])
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.borderWidth = 1
        stack.orientation = .horizontal
        stack.alignment = .firstBaseline
        stack.spacing = 10
        stack.edgeInsets = NSEdgeInsets(top: 5, left: 10, bottom: 5, right: 10)
        stack.translatesAutoresizingMaskIntoConstraints = false
        words.lineBreakMode = .byTruncatingTail
        words.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor), stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor), stack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("not supported")
    }

    override func hitTest(_: NSPoint) -> NSView? {
        nil
    }

    func show(number line: Int, text: String, colors: FindColors) {
        let ink = NSColor(hex: colors.foreground) ?? .textColor
        let background = NSColor(hex: colors.background) ?? .windowBackgroundColor
        let dark = FindColors.isDark(colors.background)
        number.stringValue = "line \(line.formatted(.number))"
        number.font = .systemFont(ofSize: 11.5.scaled)
        number.textColor = ink.withAlphaComponent(0.46)
        words.stringValue = text
        words.font = .monospacedSystemFont(ofSize: 12.scaled, weight: .regular)
        words.textColor = ink
        // A step off the terminal's background, as the ⌘-link tag's.
        layer?.backgroundColor = (background.blended(withFraction: dark ? 0.07 : 0.55, of: .white) ?? background).cgColor
        layer?.borderColor = ink.withAlphaComponent(0.2).cgColor
    }
}

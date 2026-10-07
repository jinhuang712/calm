import AppKit
import CalmModel

/// The resting marks (FEATURES.md → F8, UIUX.md → Links): a faint dotted line under each link in
/// the visible text that opens, over one workspace's panes. libghostty draws nothing for links
/// until ⌘ is held, so Calm draws these; they take no clicks. The link under ⌘ loses its mark
/// while libghostty underlines it. The same dots outline the table cell under the pointer while
/// ⌥ is held (Copy Cell, F9), and an ⌥-drag's selection inside a cell is drawn here too.
@MainActor
final class LinkMarksView: NSView {
    /// Each pane's marks: a link's dotted lines, one per row it's on.
    private var marks: [UUID: [LinkMatch: [LinkMarkView]]] = [:]
    /// Each pane's hovered-link underline, one line per row.
    private var underlines: [UUID: [LinkMarkView]] = [:]
    /// Each pane's cell outline, while ⌥ is held over a table.
    private var outlines: [UUID: CellOutlineView] = [:]
    /// Each pane's ⌥-drag selection inside a cell, one band per line.
    private var selections: [UUID: [NSView]] = [:]

    /// How strong a selection band is, over the text it covers.
    private static let selectionOpacity = 0.4

    /// How strong the dots are, against the terminal's text color.
    static let opacity = 0.45

    override func hitTest(_: NSPoint) -> NSView? {
        nil
    }

    /// Draws `pane`'s marks: new ones fade in, gone ones fade out, the rest stay where they are.
    func update(_ pane: TerminalSurfaceView) {
        var views = marks[pane.id] ?? [:]
        let wanted = pane.isHidden ? [:] : pane.links.marks
        let color = (pane.config?.color("foreground") ?? .textColor).withAlphaComponent(Self.opacity)
        for (match, lines) in views where wanted[match] == nil {
            lines.forEach { Motion.fadeOutAndRemove($0, duration: 0.15) }
            views[match] = nil
        }
        for (match, rects) in wanted {
            // A strip along the bottom of the cells, below the text's own underline.
            let frames = rects.map { pane.convert(NSRect(x: $0.minX, y: $0.minY, width: $0.width, height: 3), to: self) }
            var lines = views[match] ?? []
            if lines.count != frames.count {
                lines.forEach { $0.removeFromSuperview() }
                lines = frames.map { frame in
                    let line = LinkMarkView(frame: frame)
                    addSubview(line)
                    Motion.fadeIn(line, duration: 0.2)
                    return line
                }
            }
            let isHovered = pane.links.hovered?.overlaps(match) ?? false
            for (line, frame) in zip(lines, frames) {
                line.frame = frame
                line.color = color
                line.isHidden = isHovered
            }
            views[match] = lines
        }
        marks[pane.id] = views
        updateUnderline(pane, color: color)
        updateOutline(pane, color: color)
        updateSelection(pane)
    }

    /// An ⌥-drag's selection inside a cell, in the terminal's own selection color, over the text
    /// (libghostty never saw the drag, so it draws nothing). Bands follow the pointer at once and
    /// fade when the selection goes.
    private func updateSelection(_ pane: TerminalSurfaceView) {
        let rects = pane.isHidden ? [] : pane.links.cellSelection
        var bands = selections[pane.id] ?? []
        if rects.isEmpty {
            bands.forEach { Motion.fadeOutAndRemove($0, duration: 0.2) }
            selections[pane.id] = nil
            return
        }
        let color = (pane.config?.color("selection-background") ?? pane.config?.color("foreground") ?? .selectedTextBackgroundColor)
            .withAlphaComponent(Self.selectionOpacity)
        while bands.count > rects.count {
            bands.removeLast().removeFromSuperview()
        }
        while bands.count < rects.count {
            let band = NSView(frame: .zero)
            band.wantsLayer = true
            band.layer?.cornerRadius = 2
            addSubview(band)
            bands.append(band)
        }
        for (band, rect) in zip(bands, rects) {
            band.frame = pane.convert(rect, to: self)
            band.layer?.backgroundColor = color.cgColor
        }
        selections[pane.id] = bands
    }

    /// The underline of a ⌘-hovered link that libghostty doesn't know whole (a program cut it across
    /// rows, or it's an agent's tag for a pasted image): libghostty underlines only the piece of it it
    /// sees, if any, so Calm draws the whole (a solid line where the resting mark is).
    private func updateUnderline(_ pane: TerminalSurfaceView, color: NSColor) {
        let runs = pane.isHidden ? [] : pane.links.hovered.map { $0.isCalmOwned ? $0.runs : [] } ?? []
        let frames = runs.compactMap { pane.rect(row: $0.row, columns: $0.columns) }
            .map { pane.convert(NSRect(x: $0.minX, y: $0.minY, width: $0.width, height: 3), to: self) }
        var lines = underlines[pane.id] ?? []
        if lines.count != frames.count {
            lines.forEach { $0.removeFromSuperview() }
            lines = frames.map { _ in
                let line = LinkMarkView(frame: .zero)
                line.isSolid = true
                addSubview(line)
                return line
            }
        }
        for (line, frame) in zip(lines, frames) {
            line.frame = frame
            line.color = color.withAlphaComponent(1)
        }
        underlines[pane.id] = lines
    }

    /// The cell under ⌥: it appears at once where the pointer is and goes quickly, so it follows
    /// the pointer from cell to cell without trailing it.
    private func updateOutline(_ pane: TerminalSurfaceView, color: NSColor) {
        guard let rect = pane.isHidden ? nil : pane.links.cellOutline else {
            if let outline = outlines.removeValue(forKey: pane.id) {
                Motion.fadeOutAndRemove(outline, duration: 0.1)
            }
            return
        }
        let outline = outlines[pane.id] ?? {
            let view = CellOutlineView(frame: .zero)
            addSubview(view)
            Motion.fadeIn(view, duration: 0.1)
            outlines[pane.id] = view
            return view
        }()
        outline.frame = pane.convert(rect, to: self)
        outline.color = color
    }

    func remove(_ paneID: UUID) {
        marks[paneID]?.values.joined().forEach { $0.removeFromSuperview() }
        marks[paneID] = nil
        underlines[paneID]?.forEach { $0.removeFromSuperview() }
        underlines[paneID] = nil
        outlines.removeValue(forKey: paneID)?.removeFromSuperview()
        selections.removeValue(forKey: paneID)?.forEach { $0.removeFromSuperview() }
    }
}

/// A table cell's outline: the link marks' dots, around the cell's text between its lines.
@MainActor
final class CellOutlineView: NSView {
    var color: NSColor = .clear {
        didSet {
            if color != oldValue {
                needsDisplay = true
            }
        }
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true // for the fade
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("not supported")
    }

    override func hitTest(_: NSPoint) -> NSView? {
        nil
    }

    override func draw(_: NSRect) {
        // Half a cell's room lies between the cell's text and the table's own lines, so the
        // outline sits in it without touching either.
        let outline = NSBezierPath(roundedRect: bounds.insetBy(dx: 1.5, dy: 1.5), xRadius: 3, yRadius: 3)
        outline.lineWidth = 1
        outline.setLineDash([1, 2], count: 2, phase: 0)
        color.setStroke()
        outline.stroke()
    }
}

/// One dotted line.
@MainActor
final class LinkMarkView: NSView {
    var color: NSColor = .clear {
        didSet {
            if color != oldValue {
                needsDisplay = true
            }
        }
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true // for the fade
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("not supported")
    }

    override func hitTest(_: NSPoint) -> NSView? {
        nil
    }

    /// A solid line (the hovered link's underline) instead of the resting mark's dots.
    var isSolid = false

    override func draw(_: NSRect) {
        let line = NSBezierPath()
        line.move(to: NSPoint(x: bounds.minX, y: 1.5))
        line.line(to: NSPoint(x: bounds.maxX, y: 1.5))
        line.lineWidth = 1
        if !isSolid {
            line.setLineDash([1, 2], count: 2, phase: 0)
        }
        color.setStroke()
        line.stroke()
    }
}

import AppKit
import CalmModel

/// The resting marks (FEATURES.md → F8, UIUX.md → Links): a faint dotted line under each link in
/// the visible text that opens, over one workspace's panes. libghostty draws nothing for links
/// until ⌘ is held, so Calm draws these; they take no clicks. The link under ⌘ loses its mark
/// while libghostty underlines it.
@MainActor
final class LinkMarksView: NSView {
    /// Each pane's marks: a link's dotted lines, one per row it's on.
    private var marks: [UUID: [LinkMatch: [LinkMarkView]]] = [:]

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
    }

    func remove(_ paneID: UUID) {
        marks[paneID]?.values.joined().forEach { $0.removeFromSuperview() }
        marks[paneID] = nil
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

    override func draw(_: NSRect) {
        let line = NSBezierPath()
        line.move(to: NSPoint(x: bounds.minX, y: 1.5))
        line.line(to: NSPoint(x: bounds.maxX, y: 1.5))
        line.lineWidth = 1
        line.setLineDash([1, 2], count: 2, phase: 0)
        color.setStroke()
        line.stroke()
    }
}

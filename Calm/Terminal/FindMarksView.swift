import AppKit
import CalmModel

/// Find's marks over one workspace's panes (FEATURES.md → F16, UIUX.md → Find): a 2 pt underline
/// in the accent under every match on screen, and on the current match's line a faint band from
/// edge to edge with a 3 pt bar at the pane's left. libghostty draws the current match itself (the
/// pill: its `search-selected` colors, which Calm sets), and its fill for the other matches is
/// turned off (CalmDefaults), since a fill read as a selection. Takes no clicks.
@MainActor
final class FindMarksView: NSView {
    private final class Marks {
        /// Holds the pane's marks, so closing find fades them together.
        let group = CALayer()
        var underlines: [CALayer] = []
        let band = CALayer()
        let bar = CALayer()
    }

    private var panes: [UUID: Marks] = [:]
    /// Each pane's colors, and what they came from.
    private var colorCache: [UUID: (key: String, value: FindColors)] = [:]

    /// The underline's thickness, and its gap below the text's baseline.
    private static let thickness: CGFloat = 2
    private static let gap: CGFloat = 1.5
    /// The edge bar's width.
    private static let barWidth: CGFloat = 3
    /// Stepping to a match on the same screen: the band and the bar slide to its line.
    private static let slide: TimeInterval = 0.18
    /// Closing find: the marks fade.
    private static let fadeOut: TimeInterval = 0.12

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("not supported")
    }

    override func hitTest(_: NSPoint) -> NSView? {
        nil
    }

    /// Draws `pane`'s marks where its matches are now (UIUX.md → Find, motion). Only a step to a
    /// match on the same screen moves something: the band and the bar slide to its line. Marks
    /// that come with typing, output or a scroll are where their text is at once, so they ride
    /// with it; closing find fades them.
    func update(_ pane: TerminalSurfaceView) {
        let find = pane.find
        guard !pane.isHidden, find.words != nil, !find.matches.isEmpty, let geometry = find.geometry, let layer else {
            remove(pane.id, fading: find.words == nil && !pane.isHidden)
            return
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        let marks = panes[pane.id] ?? makeMarks(pane.id, in: layer)
        marks.group.frame = layer.bounds
        let colors = colors(for: pane)
        let solid = NSColor(hex: colors.solid)?.cgColor ?? NSColor.controlAccentColor.cgColor

        // Every match but the current one, which wears the pill. Under ⌘ a link wins: find's line
        // steps aside under it while the link's own underline shows (UIUX.md → Find, links).
        let hovered = pane.links.hovered?.runs ?? []
        var frames: [NSRect] = []
        for (index, match) in find.matches.enumerated() where index != find.current {
            for piece in match.flatMap({ $0.subtracting(hovered) }) {
                guard let cells = pane.rect(row: piece.row, columns: piece.columns, origin: geometry.origin) else { continue }
                let top = cells.minY + geometry.baseline - Self.gap
                let line = NSRect(x: cells.minX, y: Self.half(top - Self.thickness), width: cells.width, height: Self.thickness)
                frames.append(convert(line, from: pane))
            }
        }
        while marks.underlines.count > frames.count {
            marks.underlines.removeLast().removeFromSuperlayer()
        }
        while marks.underlines.count < frames.count {
            let line = CALayer()
            line.cornerRadius = Self.thickness / 2
            marks.group.addSublayer(line)
            marks.underlines.append(line)
        }
        for (line, frame) in zip(marks.underlines, frames) {
            line.frame = frame
            line.backgroundColor = solid
        }

        // The current match's line: the band over its rows, and the bar at the pane's left edge.
        let rows = find.current.map { find.matches[$0].map(\.row) } ?? []
        if let first = rows.min(), let last = rows.max(),
           let top = pane.rect(row: first, columns: 0 ..< 1, origin: geometry.origin),
           let bottom = pane.rect(row: last, columns: 0 ..< 1, origin: geometry.origin) {
            let line = NSRect(x: 0, y: bottom.minY, width: pane.bounds.width, height: top.maxY - bottom.minY)
            let frame = convert(line, from: pane)
            let tint = colors.bandLayer
            let slides = find.slides && !marks.band.isHidden && !Motion.isReduced
            CATransaction.begin()
            if slides {
                CATransaction.setDisableActions(false)
                CATransaction.setAnimationDuration(Self.slide)
                CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeOut))
            }
            marks.band.frame = frame
            marks.bar.frame = NSRect(x: frame.minX, y: frame.minY, width: Self.barWidth, height: frame.height)
            CATransaction.commit()
            marks.band.backgroundColor = CGColor(srgbRed: tint.red, green: tint.green, blue: tint.blue, alpha: tint.alpha)
            marks.bar.backgroundColor = solid
            marks.band.isHidden = false
            marks.bar.isHidden = false
        } else {
            marks.band.isHidden = true
            marks.bar.isHidden = true
        }
    }

    /// Takes `paneID`'s marks away: fading when find closes, at once otherwise (no matches while
    /// typing, the pane going away).
    func remove(_ paneID: UUID, fading: Bool = false) {
        guard let marks = panes.removeValue(forKey: paneID) else { return }
        let group = marks.group
        guard fading, !Motion.isReduced else {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            group.removeFromSuperlayer()
            CATransaction.commit()
            return
        }
        CATransaction.begin()
        CATransaction.setCompletionBlock { group.removeFromSuperlayer() }
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 1
        fade.toValue = 0
        fade.duration = Self.fadeOut
        fade.timingFunction = CAMediaTimingFunction(name: .easeIn)
        group.opacity = 0
        group.add(fade, forKey: "calm.fade")
        CATransaction.commit()
    }

    func forget(_ paneID: UUID) {
        remove(paneID)
        colorCache[paneID] = nil
    }

    private func makeMarks(_ paneID: UUID, in layer: CALayer) -> Marks {
        let marks = Marks()
        marks.group.frame = layer.bounds
        // The band lies under the underlines, so they stay crisp on it.
        marks.group.addSublayer(marks.band)
        marks.group.addSublayer(marks.bar)
        layer.addSublayer(marks.group)
        panes[paneID] = marks
        return marks
    }

    /// The pane's colors, worked out as Calm wrote the pill's: a Calm theme's accent, or palette
    /// color 4 for the user's own colors (TerminalTheme). libghostty can't hand the pill's color
    /// back: a terminal color has no C value.
    func colors(for pane: TerminalSurfaceView) -> FindColors {
        let config = pane.shownConfig
        let background = (pane.effectiveBackgroundColor ?? config?.backgroundColor ?? .black).hexString
        let foreground = (config?.color("foreground") ?? .textColor).hexString
        let palette = config?.palette ?? []
        let accent = NSColor(hex: background).flatMap { TerminalTheme.chromeColors(matching: $0)?.findAccent }
            ?? (palette.count == 16 ? palette[4].hexString : foreground)
        let key = background + foreground + accent
        if let cached = colorCache[pane.id], cached.key == key {
            return cached.value
        }
        let colors = FindColors(background: background, foreground: foreground, accent: accent)
        colorCache[pane.id] = (key, colors)
        return colors
    }

    #if DEBUG
        /// The band's place and where it's drawn right now, mid-slide or not.
        func descriptionForTesting(_ paneID: UUID) -> String {
            guard let marks = panes[paneID] else { return "no marks" }
            let shown = marks.band.presentation()?.frame ?? marks.band.frame
            return "band \(marks.band.frame), drawn at \(shown), sliding \(marks.band.animationKeys() ?? []), "
                + "\(marks.underlines.count) underlines"
        }
    #endif

    /// To the nearest half point, so a 2 pt line stays sharp on a Retina screen.
    private static func half(_ value: CGFloat) -> CGFloat {
        (value * 2).rounded() / 2
    }
}

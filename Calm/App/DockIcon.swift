import AppKit
import CalmModel
import Observation
import QuartzCore

/// Calm's Dock icon while it runs (UIUX.md → App icon). At rest the Dock shows the app's own
/// icon (AppIcon.icon, in the user's icon style); while an agent works, or after work finished or
/// failed, Calm draws the icon itself: the chase, the ring closed in sage, the ring dimmed with a
/// red cell. It redraws only while something moves, and only frames that changed.
@MainActor
final class DockIcon {
    static let shared = DockIcon()

    private var motion = AppIconMotion()
    private let view = DockIconView()
    private var timer: Timer?
    private var drawn: (frame: AppIconFrame, dark: Bool)?
    private var appearanceObservation: NSKeyValueObservation?
    private var motionObserver: NSObjectProtocol?

    func start() {
        appearanceObservation = NSApp.observe(\.effectiveAppearance) { _, _ in
            MainActor.assumeIsolated {
                DockIcon.shared.drawn = nil
                DockIcon.shared.tick()
            }
        }
        // Reduce Motion turned off mid-run: the chase starts moving again.
        motionObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil, queue: .main,
        ) { _ in
            MainActor.assumeIsolated { DockIcon.shared.tick() }
        }
        followSessions()
    }

    /// Re-reads the sessions' states whenever the workspace changes.
    private func followSessions() {
        let states = withObservationTracking {
            SessionManager.shared.workspace.sessions.map(\.state)
        } onChange: {
            Task { @MainActor in DockIcon.shared.followSessions() }
        }
        motion.show(AppIconState.summarizing(states), at: CACurrentMediaTime())
        tick()
    }

    private func tick() {
        let now = CACurrentMediaTime()
        let reduced = Motion.isReduced
        let frame = reduced ? AppIconMotion.stillFrame(for: motion.state) : motion.frame(at: now)
        draw(frame.rounded)
        if reduced || motion.isStill(at: now) {
            timer?.invalidate()
            timer = nil
        } else if timer == nil {
            // 30 frames a second, the rate Calm's agent marks use; most of them change nothing,
            // because the cursor holds on each place for most of its beat.
            let timer = Timer(timeInterval: 1 / 30, repeats: true) { _ in
                MainActor.assumeIsolated { DockIcon.shared.tick() }
            }
            RunLoop.main.add(timer, forMode: .common)
            self.timer = timer
        }
    }

    private func draw(_ frame: AppIconFrame) {
        let tile = NSApp.dockTile
        if frame.isAtRest, motion.state == .idle {
            if tile.contentView != nil {
                tile.contentView = nil
                tile.display()
            }
            drawn = nil
            return
        }
        let dark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        if let drawn, drawn.frame == frame, drawn.dark == dark {
            return
        }
        view.frame = NSRect(origin: .zero, size: tile.size)
        view.iconFrame = frame
        view.dark = dark
        view.needsDisplay = true
        tile.contentView = view
        tile.display()
        drawn = (frame, dark)
    }

    #if DEBUG
        /// Writes the icon's states as PNGs (idle, two running frames, done, failed; dark and
        /// light) into a folder, since headless self-tests can't see the Dock.
        func renderForTesting(to folder: URL) -> Bool {
            let frames: [(String, AppIconFrame)] = [
                ("idle", .still),
                ("running-a", AppIconFrame(busy: 1, head: 3, done: 0, failed: 0)),
                ("running-b", AppIconFrame(busy: 1, head: 8.6, done: 0, failed: 0)),
                ("done", AppIconMotion.stillFrame(for: .done)),
                ("failed", AppIconMotion.stillFrame(for: .failed)),
            ]
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let view = DockIconView(frame: NSRect(x: 0, y: 0, width: 256, height: 256))
            var ok = true
            for dark in [true, false] {
                for (name, frame) in frames {
                    view.iconFrame = frame
                    view.dark = dark
                    guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return false }
                    view.cacheDisplay(in: view.bounds, to: rep)
                    let url = folder.appending(path: "\(name)-\(dark ? "dark" : "light").png")
                    ok = ok && (try? rep.representation(using: .png, properties: [:])?.write(to: url)) != nil
                }
            }
            return ok
        }
    #endif
}

/// Draws one frame of the icon on the standard 1024-point grid (the tile at 100…924), in the
/// same geometry and colors as AppIcon.icon (scripts/app-icon.py); change them together.
final class DockIconView: NSView {
    var iconFrame = AppIconFrame.still
    var dark = true

    override var isFlipped: Bool {
        true
    }

    /// The ring's places, counterclockwise from the cursor cell's resting place, as (row, column)
    /// on the 5 × 5 grid (AppIconFrame.places has the same order).
    private static let places = [(1, 4), (0, 3), (0, 2), (0, 1), (1, 0), (2, 0), (3, 0), (4, 1), (4, 2), (4, 3), (3, 4), (2, 4)]

    private static func cell(_ row: Int, _ column: Int) -> CGRect {
        CGRect(x: 200 + 128 * column, y: 200 + 128 * row, width: 112, height: 112)
    }

    /// The icon's shape: a superellipse, which matches the macOS icon's continuous corners.
    private static let tilePath: CGPath = {
        let path = CGMutablePath()
        let steps = 360
        for index in 0 ..< steps {
            let angle = Double(index) / Double(steps) * 2 * .pi
            let c = cos(angle)
            let s = sin(angle)
            let point = CGPoint(
                x: 512 + 412 * copysign(pow(abs(c), 0.4), c),
                y: 512 + 412 * copysign(pow(abs(s), 0.4), s),
            )
            if index == 0 {
                path.move(to: point)
            } else {
                path.addLine(to: point)
            }
        }
        path.closeSubpath()
        return path
    }()

    override func draw(_: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        let palette = dark ? Palette.dark : Palette.light
        let frame = iconFrame
        let places = frame.places
        let scale = bounds.width / 1024
        context.saveGState()
        context.scaleBy(x: scale, y: scale)

        // The tile and its shadow (shadows ignore the scale, so they take it themselves).
        context.saveGState()
        context.setShadow(
            offset: CGSize(width: 0, height: -10 * scale),
            blur: 24 * scale,
            color: palette.shadow.cgColor(alpha: palette.shadowAlpha),
        )
        context.addPath(Self.tilePath)
        context.setFillColor(palette.bottom.cgColor)
        context.fillPath()
        context.restoreGState()

        context.saveGState()
        context.addPath(Self.tilePath)
        context.clip()
        if let gradient = CGGradient(
            colorsSpace: nil, colors: [palette.top.cgColor, palette.bottom.cgColor] as CFArray, locations: [0, 1],
        ) {
            context.drawLinearGradient(gradient, start: CGPoint(x: 512, y: 100), end: CGPoint(x: 512, y: 924), options: [])
        }

        // The ring steps back while working, and loses its warmth to grey when something failed.
        let ringHue = palette.ring.mixed(with: palette.grey, frame.failed)
        let ring = palette.tile.mixed(with: ringHue, palette.ringWeight * (1 - 0.4 * frame.busy))
        for (index, place) in places.enumerated() where place.ring > 0 {
            fillCell(Self.places[index], ring, alpha: place.ring, in: context)
        }
        fillCell((2, 2), palette.center, alpha: 1, in: context)

        // The home cell (where the cursor rests) takes the state: sage for done, red for failed.
        let mark = max(frame.done, frame.failed)
        let state = frame.done >= frame.failed ? palette.done : palette.failed
        let glowState = frame.done >= frame.failed ? palette.glowDone : palette.glowFailed
        let glowAlpha = dark ? 0.35 * frame.busy + 0.25 * mark : 0.4 + 0.15 * frame.busy
        drawGlow(at: glowCenter(frame.head), color: palette.glow.mixed(with: glowState, mark), alpha: glowAlpha, in: context)
        for (index, place) in places.enumerated() where place.cursor > 0 {
            let color = index == 0 ? palette.cursor.mixed(with: state, mark) : palette.cursor
            fillCell(Self.places[index], color, alpha: place.cursor, in: context)
        }
        context.restoreGState()

        drawEdge(in: context, palette: palette)
        context.restoreGState()
    }

    private func fillCell(_ at: (Int, Int), _ color: RGB, alpha: Double, in context: CGContext) {
        let path = CGPath(roundedRect: Self.cell(at.0, at.1), cornerWidth: 26, cornerHeight: 26, transform: nil)
        context.addPath(path)
        context.setFillColor(color.cgColor(alpha: alpha))
        context.fillPath()
    }

    /// The cursor cell's center, between two places while it steps.
    private func glowCenter(_ head: Double) -> CGPoint {
        let count = Double(Self.places.count)
        let at = head.truncatingRemainder(dividingBy: count)
        let position = at < 0 ? at + count : at
        let first = Int(position)
        let fraction = position - Double(first)
        let from = Self.cell(Self.places[first % Self.places.count].0, Self.places[first % Self.places.count].1)
        let next = (first + 1) % Self.places.count
        let to = Self.cell(Self.places[next].0, Self.places[next].1)
        return CGPoint(x: from.midX + (to.midX - from.midX) * fraction, y: from.midY + (to.midY - from.midY) * fraction)
    }

    private func drawGlow(at center: CGPoint, color: RGB, alpha: Double, in context: CGContext) {
        guard alpha > 0, let gradient = CGGradient(
            colorsSpace: nil,
            colors: [color.cgColor(alpha: alpha), color.cgColor(alpha: alpha * 0.4), color.cgColor(alpha: 0)] as CFArray,
            locations: [0, 0.55, 1],
        ) else { return }
        context.drawRadialGradient(gradient, startCenter: center, startRadius: 0, endCenter: center, endRadius: 110, options: [])
    }

    /// A light top edge on dark; on light, a white highlight under a faint dark hairline.
    private func drawEdge(in context: CGContext, palette: Palette) {
        context.saveGState()
        context.addPath(Self.tilePath)
        context.setLineWidth(dark ? 3 : 2)
        context.replacePathWithStrokedPath()
        context.clip()
        let colors: [CGColor] = dark
            ? [RGB.white.cgColor(alpha: 0.2), RGB.white.cgColor(alpha: 0.04), RGB.white.cgColor(alpha: 0.08)]
            : [RGB.white.cgColor(alpha: 0.9), RGB.white.cgColor(alpha: 0), RGB.white.cgColor(alpha: 0)]
        if let gradient = CGGradient(colorsSpace: nil, colors: colors as CFArray, locations: dark ? [0, 0.5, 1] : [0, 0.4, 1]) {
            context.drawLinearGradient(gradient, start: CGPoint(x: 512, y: 100), end: CGPoint(x: 512, y: 924), options: [])
        }
        context.restoreGState()
        if !dark {
            context.addPath(Self.tilePath)
            context.setLineWidth(1.5)
            context.setStrokeColor(RGB.black.cgColor(alpha: 0.08))
            context.strokePath()
        }
    }

    /// The icon's colors, from Calm's own theme and state colors (UIUX.md → App icon).
    private struct Palette {
        var top: RGB
        var bottom: RGB
        /// The tile's middle, for mixing the ring into it.
        var tile: RGB
        var ring: RGB
        var ringWeight: Double
        var grey: RGB
        var center: RGB
        var cursor: RGB
        var done: RGB
        var failed: RGB
        var glow: RGB
        var glowDone: RGB
        var glowFailed: RGB
        var shadow: RGB
        var shadowAlpha: Double

        static let dark = Palette(
            top: RGB(0x2C2723), bottom: RGB(0x1B1815), tile: RGB(0x24201C),
            ring: RGB(0xCEA081), ringWeight: 0.45, grey: RGB(0x8B8580),
            center: RGB(0xCEA081), cursor: RGB(0xF3D9BD), done: RGB(0xAED6AE), failed: RGB(0xE39A90),
            glow: RGB(0xF6DCC0), glowDone: RGB(0xB5DBB5), glowFailed: RGB(0xE8A59C),
            shadow: .black, shadowAlpha: 0.28,
        )
        static let light = Palette(
            top: RGB(0xFCFAF7), bottom: RGB(0xEBE4DB), tile: RGB(0xF3EEE8),
            ring: RGB(0xC6AC97), ringWeight: 1, grey: RGB(0xBAB4AE),
            center: RGB(0x8F5F3C), cursor: RGB(0xD98A4E), done: RGB(0x5A9160), failed: RGB(0xB35A50),
            glow: RGB(0xF0A868), glowDone: RGB(0x9FD0A2), glowFailed: RGB(0xEBA59C),
            shadow: RGB(0x3A2A1C), shadowAlpha: 0.18,
        )
    }
}

/// An sRGB color that mixes: the icon blends solid colors rather than stacking see-through
/// layers, which read as washed out on a light tile.
private struct RGB {
    var red: Double
    var green: Double
    var blue: Double

    init(_ hex: Int) {
        red = Double((hex >> 16) & 0xFF) / 255
        green = Double((hex >> 8) & 0xFF) / 255
        blue = Double(hex & 0xFF) / 255
    }

    init(red: Double, green: Double, blue: Double) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    static let white = RGB(0xFFFFFF)
    static let black = RGB(0x000000)

    func mixed(with other: RGB, _ weight: Double) -> RGB {
        RGB(
            red: red + (other.red - red) * weight,
            green: green + (other.green - green) * weight,
            blue: blue + (other.blue - blue) * weight,
        )
    }

    var cgColor: CGColor {
        cgColor(alpha: 1)
    }

    func cgColor(alpha: Double) -> CGColor {
        CGColor(srgbRed: red, green: green, blue: blue, alpha: alpha)
    }
}

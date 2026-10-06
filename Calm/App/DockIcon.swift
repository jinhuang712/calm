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
    private let view: DockIconView = {
        let view = DockIconView()
        view.cachesStillParts = true
        return view
    }()

    private var timer: Timer?
    private var drawn: (frame: AppIconFrame, dark: Bool)?
    private var appearanceObservation: NSKeyValueObservation?
    private var motionObserver: NSObjectProtocol?
    private var sight = DockSight()
    private var sightObservers: [NSObjectProtocol] = []

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
        followSight()
        followSessions()
    }

    /// Nobody sees the Dock while the displays sleep or another user's session is in front, so
    /// the icon draws nothing then: a chase left running overnight drew 8 frames a second for no
    /// one. On return the next tick draws where the motion is by then.
    private func followSight() {
        let changes: [(Notification.Name, DockSight.Change)] = [
            (NSWorkspace.screensDidSleepNotification, .displaysSlept),
            (NSWorkspace.screensDidWakeNotification, .displaysWoke),
            (NSWorkspace.sessionDidResignActiveNotification, .sessionLeft),
            (NSWorkspace.sessionDidBecomeActiveNotification, .sessionReturned),
        ]
        sightObservers = changes.map { name, change in
            NSWorkspace.shared.notificationCenter.addObserver(forName: name, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated {
                    DockIcon.shared.sight.apply(change)
                    DockIcon.shared.tick()
                }
            }
        }
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
        timer?.invalidate()
        timer = nil
        guard sight.isSeen else { return }
        let now = CACurrentMediaTime()
        let reduced = Motion.isReduced
        // In whole steps: each frame is a new picture sent to the Dock, and at its size the ease
        // between places doesn't show (8 frames a second instead of 16).
        let frame = reduced ? AppIconMotion.stillFrame(for: motion.state) : motion.frame(at: now, wholeSteps: true)
        draw(frame.rounded)
        guard !reduced, !motion.isStill(at: now) else { return }
        // The steady chase changes only when the cursor steps, so the next tick is the next step
        // (8 a second; a millisecond late, so the step has surely happened). While something
        // eases, 30 a second, the rate Calm's agent marks use.
        let delay = motion.nextWholeStep(after: now).map { $0 - now + 0.001 } ?? 1 / 30
        let timer = Timer(timeInterval: max(delay, 0.001), repeats: false) { _ in
            MainActor.assumeIsolated { DockIcon.shared.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func draw(_ frame: AppIconFrame) {
        let tile = NSApp.dockTile
        if frame.isAtRest, motion.state == .idle {
            if tile.contentView != nil {
                tile.contentView = nil
                tile.display()
            }
            drawn = nil
            view.releaseChasePictures()
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

    /// The parts that never move (the tile, its shadow, its edge), drawn once per appearance, size
    /// and resolution, then stamped under each frame: the shadow's blur and the edge's stroke
    /// were most of a frame's cost, about 17 frames a second while an agent works (2026-09-30).
    /// Nothing that moves comes near the edge (the glow is gone 40 units of the 1024 grid inside
    /// it), so drawing the edge under the cells changes no pixel.
    private var still: (key: StillKey, layer: CGLayer)?
    /// On for the Dock, drawn through `NSDockTile.display` as the pixel test draws it. The
    /// welcome page's mark leaves it off: it redraws seldom, and through a layer-backed view,
    /// which the test doesn't cover.
    var cachesStillParts = false

    /// The chase's twelve pictures (`AppIconFrame.chasePlace`), each drawn whole the first time it
    /// comes round and stamped after that. The Dock draws into a half-float bitmap, where filling
    /// the cells through the tile's clip and the glow cost about 0.6 ms a frame, 8 frames a second
    /// while an agent works (sampled in the running app, 2026-10-06); a stamp is one copy. Only
    /// the settle and the changes between states, a second or so each, are drawn as they come.
    private var chase: (key: StillKey, layers: [Int: CGLayer])?

    private struct StillKey: Equatable {
        var dark: Bool
        var size: CGSize
        var resolution: CGFloat
    }

    /// Lets the chase's pictures go once the icon is at rest; the next run draws them again.
    func releaseChasePictures() {
        chase = nil
    }

    #if DEBUG
        var chasePicturesForTesting: Int {
            chase?.layers.count ?? 0
        }
    #endif

    override func draw(_: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        let palette = dark ? Palette.dark : Palette.light
        let frame = iconFrame
        let scale = bounds.width / 1024
        if cachesStillParts, let place = frame.chasePlace,
           let layer = chaseLayer(frame, place: place, like: context, palette: palette, scale: scale) {
            stamp(layer, in: context)
            return
        }
        if cachesStillParts, let layer = stillLayer(like: context, palette: palette, scale: scale) {
            stamp(layer, in: context)
        } else {
            drawStillParts(in: context, palette: palette, scale: scale, shadowUnit: 1)
        }
        drawMovingParts(frame, in: context, palette: palette, scale: scale)
    }

    /// Draws a layer made by `layer(like:)` over the whole view. The layer holds pixels as they
    /// land, flip and shadow included, so it goes on unflipped.
    private func stamp(_ layer: CGLayer, in context: CGContext) {
        context.saveGState()
        context.translateBy(x: 0, y: bounds.height)
        context.scaleBy(x: 1, y: -1)
        context.draw(layer, in: CGRect(origin: .zero, size: bounds.size))
        context.restoreGState()
    }

    /// The cells and the glow: everything that moves.
    private func drawMovingParts(_ frame: AppIconFrame, in context: CGContext, palette: Palette, scale: CGFloat) {
        let places = frame.places
        context.saveGState()
        context.scaleBy(x: scale, y: scale)
        context.addPath(Self.tilePath)
        context.clip()

        // The ring steps back while working, and loses its warmth to grey when something failed.
        let ringHue = palette.ring.mixed(with: palette.grey, frame.failed)
        let ring = palette.tile.mixed(with: ringHue, palette.ringWeight * (1 - 0.4 * frame.busy))
        for (index, place) in places.enumerated() where place.ring > 0 {
            fillCell(Self.places[index], ring, alpha: place.ring, in: context)
        }
        // The center (the welcome page draws it in after the ring).
        fillCell((2, 2), palette.center, alpha: frame.centerLevel, in: context)

        // The home cell (where the cursor rests) takes the state: sage for done, red for failed.
        let mark = max(frame.done, frame.failed)
        let state = frame.done >= frame.failed ? palette.done : palette.failed
        let glowState = frame.done >= frame.failed ? palette.glowDone : palette.glowFailed
        // The glow goes with the cursor, so it arrives and breathes with it (both are 1 in the Dock).
        let glowAlpha = (dark ? 0.35 * frame.busy + 0.25 * mark : 0.4 + 0.15 * frame.busy) * frame.cursorVisibility
        drawGlow(at: glowCenter(frame.head), color: palette.glow.mixed(with: glowState, mark), alpha: glowAlpha, in: context)
        for (index, place) in places.enumerated() where place.cursor > 0 {
            let color = index == 0 ? palette.cursor.mixed(with: state, mark) : palette.cursor
            fillCell(Self.places[index], color, alpha: place.cursor, in: context)
        }
        context.restoreGState()
    }

    private func stillKey(for context: CGContext) -> StillKey {
        let device = context.convertToDeviceSpace(CGSize(width: 1, height: 1))
        return StillKey(dark: dark, size: bounds.size, resolution: abs(device.width))
    }

    private func stillLayer(like context: CGContext, palette: Palette, scale: CGFloat) -> CGLayer? {
        let key = stillKey(for: context)
        if let still, still.key == key {
            return still.layer
        }
        guard let (layer, layerContext) = layer(like: context, key: key) else { return nil }
        drawStillParts(in: layerContext, palette: palette, scale: scale, shadowUnit: key.resolution)
        still = (key, layer)
        return layer
    }

    private func chaseLayer(
        _ frame: AppIconFrame, place: Int, like context: CGContext, palette: Palette, scale: CGFloat,
    ) -> CGLayer? {
        let key = stillKey(for: context)
        if chase?.key != key {
            chase = (key, [:])
        }
        if let layer = chase?.layers[place] {
            return layer
        }
        guard let (layer, layerContext) = layer(like: context, key: key) else { return nil }
        drawStillParts(in: layerContext, palette: palette, scale: scale, shadowUnit: key.resolution)
        drawMovingParts(frame, in: layerContext, palette: palette, scale: scale)
        chase?.layers[place] = layer
        return layer
    }

    /// A layer the size of the view, made for `context`, and its context set up to draw as the
    /// view draws: in points and flipped, so the shapes and the gradients land the same way.
    private func layer(like context: CGContext, key: StillKey) -> (CGLayer, CGContext)? {
        // A layer's size is in its context's base units, pixels for a bitmap: sized in points it
        // held half the pixels on a Retina Dock and blurred the tile's outline.
        let pixels = CGSize(width: bounds.width * key.resolution, height: bounds.height * key.resolution)
        guard let layer = CGLayer(context, size: pixels, auxiliaryInfo: nil), let layerContext = layer.context else {
            return nil
        }
        // A shadow ignores the transform: the view's context measures it in points, the layer's
        // in pixels (`shadowUnit`). The pixel test (DockIconViewTests) holds the two to the same
        // pixels.
        layerContext.translateBy(x: 0, y: pixels.height)
        layerContext.scaleBy(x: key.resolution, y: -key.resolution)
        return (layer, layerContext)
    }

    /// The tile, its shadow and its edge. `shadowUnit` is how many of the context's base units
    /// make a point.
    private func drawStillParts(in context: CGContext, palette: Palette, scale: CGFloat, shadowUnit: CGFloat) {
        context.saveGState()
        context.scaleBy(x: scale, y: scale)

        // The tile and its shadow (shadows ignore the scale, so they take it themselves).
        context.saveGState()
        context.setShadow(
            offset: CGSize(width: 0, height: -10 * scale * shadowUnit),
            blur: 24 * scale * shadowUnit,
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

        static var dark: Palette {
            BuildVariant.isDev ? dev.dark : shipped.dark
        }

        static var light: Palette {
            BuildVariant.isDev ? dev.light : shipped.light
        }

        static let shipped = (
            dark: Palette(
                top: RGB(0x2C2723), bottom: RGB(0x1B1815), tile: RGB(0x24201C),
                ring: RGB(0xCEA081), ringWeight: 0.45, grey: RGB(0x8B8580),
                center: RGB(0xCEA081), cursor: RGB(0xF3D9BD), done: RGB(0xAED6AE), failed: RGB(0xE39A90),
                glow: RGB(0xF6DCC0), glowDone: RGB(0xB5DBB5), glowFailed: RGB(0xE8A59C),
                shadow: .black, shadowAlpha: 0.28,
            ),
            light: Palette(
                top: RGB(0xFCFAF7), bottom: RGB(0xEBE4DB), tile: RGB(0xF3EEE8),
                ring: RGB(0xC6AC97), ringWeight: 1, grey: RGB(0xBAB4AE),
                center: RGB(0x8F5F3C), cursor: RGB(0xD98A4E), done: RGB(0x5A9160), failed: RGB(0xB35A50),
                glow: RGB(0xF0A868), glowDone: RGB(0x9FD0A2), glowFailed: RGB(0xEBA59C),
                shadow: RGB(0x3A2A1C), shadowAlpha: 0.18,
            ),
        )

        /// The dev build's icon (BuildVariant): the same mark on a cool tile, with violet where the
        /// shipped one is warm. Violet because no state uses it (working is blue, done sage,
        /// needs you amber, failed red); done and failed keep their colors, so the icon's states
        /// still read the same. Matches AppIconDev.icon (scripts/app-icon.py); change them together.
        static let dev = (
            dark: Palette(
                top: RGB(0x25232F), bottom: RGB(0x16151D), tile: RGB(0x1E1C26),
                ring: RGB(0xB8A8E8), ringWeight: 0.45, grey: RGB(0x86848E),
                center: RGB(0xB8A8E8), cursor: RGB(0xE3DAF8), done: RGB(0xAED6AE), failed: RGB(0xE39A90),
                glow: RGB(0xE6DCFA), glowDone: RGB(0xB5DBB5), glowFailed: RGB(0xE8A59C),
                shadow: .black, shadowAlpha: 0.28,
            ),
            light: Palette(
                top: RGB(0xF9F8FD), bottom: RGB(0xE6E3F0), tile: RGB(0xEFEDF6),
                ring: RGB(0xB9B0D0), ringWeight: 1, grey: RGB(0xB4B2BC),
                center: RGB(0x5E4C8F), cursor: RGB(0x7C5FD3), done: RGB(0x5A9160), failed: RGB(0xB35A50),
                glow: RGB(0xA98BF0), glowDone: RGB(0x9FD0A2), glowFailed: RGB(0xEBA59C),
                shadow: RGB(0x2A2440), shadowAlpha: 0.18,
            ),
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

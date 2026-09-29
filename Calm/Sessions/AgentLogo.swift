import AppKit
import CalmAgents
import CalmModel
import SwiftUI

/// An agent's own mark in its tile (UIUX.md → Agent marks): gray and quiet while the agent is
/// idle, moving in its own way while it works, settling once when the work ends, and still
/// otherwise. Nothing moves with Reduce Motion.
struct AgentLogo: View {
    let agent: AgentKind
    /// The session's state; nil where the mark only names the agent (welcome page, search).
    var state: SessionState?
    var size: CGFloat = 26
    /// `size` at the interface size.
    private var side: CGFloat {
        size.scaled
    }

    /// The sidebar's colors; nil for the system's (search, Settings).
    var style: SidebarStyle?
    /// When the work ended, while the mark settles.
    @State private var finishedAt: Date?
    @Environment(\.colorScheme) private var colorScheme

    private var isDark: Bool {
        style?.isDark ?? (colorScheme == .dark)
    }

    private var ink: Color {
        style?.primary ?? .primary
    }

    private var art: AgentMarkArt? {
        Agents.adapter(for: agent)?.mark
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: side * 0.3, style: .continuous)
                .fill(ink.opacity(isDark ? 0.07 : 0.06))
            mark
                // Idle: the agent is there but asleep (drawn in grays, below).
                .opacity(state == .idle ? 0.45 : 1)
        }
        .frame(width: side, height: side)
        // Built marks drop in from above the tile.
        .clipShape(RoundedRectangle(cornerRadius: side * 0.3, style: .continuous))
        .animation(.easeInOut(duration: 0.25), value: state)
        .onChange(of: state) { old, new in
            if new == .working {
                finishedAt = nil
            } else if old == .working, new != .needsYou {
                finishedAt = .now
            }
        }
        .task(id: finishedAt) {
            // Stop the clock once the mark has settled.
            guard let started = finishedAt, let art else { return }
            try? await Task.sleep(for: .seconds(MarkMotion.finishDuration(art.motion)))
            if finishedAt == started {
                finishedAt = nil
            }
        }
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var mark: some View {
        if let art, let paths = MarkPaths.paths(for: agent, art: art) {
            // Still while nobody can see the window (WindowPresence).
            if !Motion.isReduced, WindowPresence.shared.isVisible, state == .working || finishedAt != nil {
                // 30 frames a second is plenty for marks this small, and costs half as much.
                TimelineView(.animation(minimumInterval: 1 / 30)) { context in
                    MarkDrawing(
                        art: art, paths: paths, pose: pose(art, at: context.date),
                        time: context.date.timeIntervalSinceReferenceDate, size: side, isDark: isDark, ink: ink,
                    )
                }
            } else {
                MarkDrawing(
                    art: art, paths: paths, pose: MarkPose(), time: 0, size: side, isDark: isDark, ink: ink, asleep: state == .idle,
                )
            }
        } else {
            Text(agent.monogram)
                .calmFont(size: size * 0.46, weight: .semibold, design: .rounded)
                .foregroundStyle(ink.opacity(0.6))
        }
    }

    private func pose(_ art: AgentMarkArt, at date: Date) -> MarkPose {
        if let finishedAt, state != .working {
            return MarkMotion.finishing(art.motion, shapes: art.shapes.count, at: date.timeIntervalSince(finishedAt))
        }
        return MarkMotion.working(art.motion, shapes: art.shapes.count, at: date.timeIntervalSinceReferenceDate)
    }
}

/// Parsed once per agent: the marks never change while Calm runs.
@MainActor
private enum MarkPaths {
    private static var cache: [AgentKind: [Path]?] = [:]

    static func paths(for agent: AgentKind, art: AgentMarkArt) -> [Path]? {
        if let cached = cache[agent] {
            return cached
        }
        let parsed = art.shapes.map { SVGPath.path($0.path) }
        let paths = parsed.contains { $0 == nil } ? nil : parsed.compactMap(\.self)
        cache[agent] = .some(paths)
        return paths
    }
}

/// An agent's own frames, read once: the marks never change while Calm runs.
@MainActor
private enum MarkFrames {
    private static var cache: [URL: NSImage] = [:]

    static func image(_ frames: AgentMarkArt.Frames, at time: TimeInterval) -> NSImage? {
        guard !frames.images.isEmpty else { return nil }
        let index = MarkMotion.frameIndex(sequence: frames.sequence, framesPerSecond: frames.framesPerSecond, at: time)
        guard frames.images.indices.contains(index) else { return nil }
        let url = frames.images[index]
        if let cached = cache[url] {
            return cached
        }
        let image = NSImage(contentsOf: url)
        cache[url] = image
        return image
    }
}

/// A mark drawn at one pose of its motion.
private struct MarkDrawing: View {
    let art: AgentMarkArt
    let paths: [Path]
    let pose: MarkPose
    /// For the pulsing grid, whose squares keep their own time.
    let time: TimeInterval
    let size: CGFloat
    let isDark: Bool
    /// The text color, for the grid's squares.
    let ink: Color
    /// Idle: every color becomes the gray of its own lightness. Drawn so rather than with a
    /// grayscale filter, which costs a layer effect and leaves snapshots in color.
    var asleep = false

    var body: some View {
        let side = size * art.scale
        let frame = pose.framesOpacity > 0 ? art.frames.flatMap { MarkFrames.image($0, at: time) } : nil
        // Frames that can't be read leave the mark showing, still.
        let markOpacity = pose.framesOpacity > 0 && frame == nil ? 1 : pose.markOpacity
        ZStack {
            if markOpacity > 0 {
                ZStack {
                    ForEach(paths.indices, id: \.self) { index in
                        let drop = index < pose.drops.count ? pose.drops[index] : MarkPose.Drop()
                        shape(index, side: side)
                            .offset(y: drop.offset * side)
                            .opacity(drop.opacity)
                    }
                }
                .frame(width: side, height: side)
                .rotationEffect(.degrees(pose.rotation))
                .scaleEffect(pose.scale)
                .brightness(pose.brightness)
                .opacity(markOpacity)
            }
            if let frame, let frames = art.frames {
                Image(nsImage: frame)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: size * frames.scale, height: size * frames.scale)
                    .opacity(pose.framesOpacity)
            }
            if pose.gridOpacity > 0 {
                PulseGrid(time: time, color: ink)
                    .frame(width: size * 0.58, height: size * 0.58)
                    .opacity(pose.gridOpacity)
            }
        }
        .frame(width: size, height: size)
    }

    @ViewBuilder
    private func shape(_ index: Int, side: CGFloat) -> some View {
        let shape = art.shapes[index]
        let scale = side / art.viewBox.side
        let path = paths[index].applying(
            CGAffineTransform(scaleX: scale, y: scale).translatedBy(x: -art.viewBox.x, y: -art.viewBox.y),
        )
        switch shape.fill {
        case let .color(dark, light):
            path.fill(color(isDark ? dark : light), style: FillStyle(eoFill: shape.evenOdd))
        case let .gradient(stops):
            ZStack {
                Rectangle()
                    .fill(LinearGradient(colors: stops.map(color), startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: side * 2, height: side * 2)
                    .rotationEffect(.degrees(pose.gradientTurn))
                if let shine = pose.shine {
                    LinearGradient(
                        colors: [.clear, .white.opacity(0.8 * pose.shineOpacity), .clear],
                        startPoint: .leading, endPoint: .trailing,
                    )
                    .frame(width: side * 0.5, height: side)
                    .offset(x: (shine * 1.6 - 0.8) * side)
                }
            }
            .frame(width: side, height: side)
            .mask(path.fill(style: FillStyle(eoFill: shape.evenOdd)))
        }
    }

    private func color(_ hex: String) -> Color {
        asleep ? Color(white: Color.luminance(hex: hex)) : Color(hex: hex)
    }
}

/// Twelve small squares, each breathing on its own rhythm.
private struct PulseGrid: View {
    let time: TimeInterval
    let color: Color

    var body: some View {
        Canvas { context, size in
            // Squares 3 wide on a pitch of 4, in 15: the corners are left out.
            let unit = size.width / 15
            for (index, square) in MarkMotion.gridSquares.enumerated() {
                let rect = CGRect(x: Double(square.column) * 4 * unit, y: Double(square.row) * 4 * unit, width: 3 * unit, height: 3 * unit)
                context.opacity = MarkMotion.gridOpacity(square: index, at: time)
                context.fill(Path(roundedRect: rect, cornerRadius: unit), with: .color(color))
            }
        }
    }
}

/// A line a soft light crosses now and then (UIUX.md → Session cards, Working): enough to see
/// the agent is at it, never enough to pull the eye. Still with Reduce Motion.
struct ShimmerText: View {
    let text: String
    let color: Color
    /// The light itself: white on a dark background; on a light one a white band would read as
    /// the letters fading, so a deeper version of the color crosses instead.
    let highlight: Color
    @State private var isCrossing = Self.phase(at: Date.now.timeIntervalSinceReferenceDate) != nil

    private static let period = 2.6
    /// The share of each period the light takes to cross; it rests for the rest.
    private static let crossing = 0.6

    var body: some View {
        if Motion.isReduced || !WindowPresence.shared.isVisible {
            Text(text).foregroundStyle(color)
        } else {
            Group {
                if isCrossing {
                    TimelineView(.animation(minimumInterval: 1 / 30)) { context in
                        Text(text)
                            .foregroundStyle(color)
                            .overlay {
                                if let phase = Self.phase(at: context.date.timeIntervalSinceReferenceDate) {
                                    GeometryReader { geometry in
                                        LinearGradient(colors: [.clear, highlight, .clear], startPoint: .leading, endPoint: .trailing)
                                            .frame(width: geometry.size.width * 0.5)
                                            .offset(x: (phase * 1.5 - 0.5) * geometry.size.width)
                                    }
                                    .mask(Text(text))
                                }
                            }
                    }
                } else {
                    // While the light rests the line is still, so nothing redraws it.
                    Text(text).foregroundStyle(color)
                }
            }
            .task { await followCrossings() }
        }
    }

    /// Runs the timeline only while the light crosses: a timeline ticking through the rest
    /// redrew an unchanged line (40% of the time). At both ends of a crossing the band is outside
    /// the text, so the switch can't be seen; waking just after the change keeps it so.
    private func followCrossings() async {
        while !Task.isCancelled {
            let now = Date.now.timeIntervalSinceReferenceDate
            let crossing = Self.phase(at: now) != nil
            if crossing != isCrossing {
                isCrossing = crossing
            }
            try? await Task.sleep(for: .seconds(Self.untilChange(at: now) + 0.005), tolerance: .milliseconds(5))
        }
    }

    /// 0…1 while the light crosses (the first 60% of every 2.6 s), nil while it rests.
    static func phase(at time: TimeInterval) -> Double? {
        let cycle = MarkMotion.fraction(time, of: period)
        return cycle < crossing ? cycle / crossing : nil
    }

    /// Seconds from `time` until the light next starts or stops crossing.
    static func untilChange(at time: TimeInterval) -> TimeInterval {
        let cycle = MarkMotion.fraction(time, of: period)
        return (cycle < crossing ? crossing - cycle : 1 - cycle) * period
    }
}

extension Color {
    /// `#RRGGBB`; gray when it can't be read.
    init(hex: String) {
        self.init(nsColor: NSColor(hex: hex) ?? .gray)
    }

    /// How light `#RRGGBB` looks, 0…1 (Rec. 709 weights).
    static func luminance(hex: String) -> Double {
        guard let color = NSColor(hex: hex)?.usingColorSpace(.sRGB) else { return 0.5 }
        return 0.2126 * color.redComponent + 0.7152 * color.greenComponent + 0.0722 * color.blueComponent
    }
}

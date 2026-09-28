import CalmAgents
import Foundation

/// How an agent's mark is posed at one moment of its motion (UIUX.md → Agent marks).
struct MarkPose: Equatable {
    /// Degrees, clockwise.
    var rotation = 0.0
    var scale = 1.0
    /// The mark itself; a pulsing grid or the agent's own frames show in its place while it works.
    var markOpacity = 1.0
    var gridOpacity = 0.0
    var framesOpacity = 0.0
    /// Per shape, for marks that build: offset in mark heights (negative is above) and opacity.
    var drops: [Drop] = []
    /// Added brightness, for a built mark's closing flash.
    var brightness = 0.0
    /// Degrees the gradient inside the mark has turned.
    var gradientTurn = 0.0
    /// Where a crossing shine is, 0…1 left to right; nil when there's none.
    var shine: Double?
    var shineOpacity = 1.0

    struct Drop: Equatable {
        var offset = 0.0
        var opacity = 1.0
    }
}

/// Each motion as a pure function of time: `working` loops while the agent works, and
/// `finishing` plays once, from when the work ends, then the mark rests. Timings follow the
/// agents' own marks, slowed and softened (DESIGNS.md → Agent marks).
enum MarkMotion {
    static func working(_ motion: AgentMarkArt.Motion, shapes: Int, at time: TimeInterval) -> MarkPose {
        var pose = MarkPose()
        switch motion {
        case .frames:
            pose.markOpacity = 0
            pose.framesOpacity = 1
        case .turnAndRest:
            let seconds = time.truncatingRemainder(dividingBy: 2.2)
            pose.rotation = seconds < 1.6 ? 360 * easeInOutCubic(seconds / 1.6) : 0
        case .pulseGrid:
            pose.markOpacity = 0
            pose.gridOpacity = 1
        case .build:
            pose.drops = buildDrops(shapes: shapes, at: fraction(time, of: 3.2))
        case .gradientTurn:
            pose.gradientTurn = -360 * fraction(time, of: 4)
            let sweep = fraction(time, of: 3)
            pose.shine = sweep < 0.45 ? sweep / 0.45 : nil
        }
        return pose
    }

    /// How long the settling after the work takes.
    static func finishDuration(_ motion: AgentMarkArt.Motion) -> TimeInterval {
        switch motion {
        case .frames: 0.4
        case .turnAndRest: 1.3
        case .pulseGrid: 1.0
        case .build: 1.1
        case .gradientTurn: 1.6
        }
    }

    /// `time` is seconds since the work ended; at `finishDuration` it rests as it began.
    static func finishing(_ motion: AgentMarkArt.Motion, shapes: Int, at time: TimeInterval) -> MarkPose {
        var pose = MarkPose()
        let q = min(max(time / finishDuration(motion), 0), 1)
        switch motion {
        case .frames:
            // The frames keep playing as the resting mark fades in over them.
            pose.markOpacity = smooth(q / 0.75)
            pose.framesOpacity = 1 - pose.markOpacity
        case .turnAndRest:
            // Still turning when the work ends, slowing to a stop.
            pose.rotation = 360 * easeOutCubic(q)
        case .pulseGrid:
            pose.gridOpacity = 1 - smooth((time - 0.15) / 0.35)
            pose.markOpacity = smooth((time - 0.3) / 0.4)
            pose.scale = 0.88 + 0.12 * pose.markOpacity
        case .build:
            // The last piece drops in, and the mark flashes twice.
            pose.drops = (0 ..< shapes).map { _ in MarkPose.Drop() }
            if shapes > 0 {
                pose.drops[shapes - 1].offset = -1.2 * (1 - easeOutCubic(min(time / 0.35, 1)))
            }
            pose.brightness = 0.35 * pulse(time, at: 0.48, width: 0.12) + 0.25 * pulse(time, at: 0.74, width: 0.12)
        case .gradientTurn:
            pose.gradientTurn = -360 * easeOutCubic(q)
            if time < 0.9 {
                pose.shine = time / 0.9
                pose.shineOpacity = 1 - 0.6 * time / 0.9
            }
        }
        return pose
    }

    // MARK: - The grid that pulses in place of a mark

    struct GridSquare {
        let column: Int
        let row: Int
        /// One of the four brighter squares in the middle.
        let inner: Bool
    }

    /// Twelve squares of a 4×4 grid, corners left out, in reading order.
    static let gridSquares: [GridSquare] = [(1, 0), (2, 0), (0, 1), (1, 1), (2, 1), (3, 1), (0, 2), (1, 2), (2, 2), (3, 2), (1, 3), (2, 3)]
        .map { GridSquare(column: $0.0, row: $0.1, inner: (1 ... 2).contains($0.0) && (1 ... 2).contains($0.1)) }

    /// Each square on its own rhythm, fixed so the grid looks the same every time.
    private static let gridPeriods = [1.3, 1.8, 1.5, 1.2, 1.9, 1.1, 1.7, 1.6, 1.4, 2.0, 1.25, 1.65]
    private static let gridDelays = [0.2, 1.1, 0.7, 0.4, 1.3, 0.9, 0.3, 1.4, 0.1, 0.6, 1.0, 0.5]

    /// Edge squares breathe between 0.15 and 0.35, inner ones between 0.4 and 1.
    static func gridOpacity(square: Int, at time: TimeInterval) -> Double {
        let (low, high) = gridSquares[square].inner ? (0.4, 1.0) : (0.15, 0.35)
        let wave = 0.5 - 0.5 * cos(2 * .pi * (time + gridDelays[square]) / gridPeriods[square])
        return low + (high - low) * wave
    }

    // MARK: - Frames

    /// Which image of a looping sequence shows at `time`.
    static func frameIndex(sequence: [Int], framesPerSecond: Double, at time: TimeInterval) -> Int {
        guard !sequence.isEmpty, framesPerSecond > 0 else { return 0 }
        let position = Int(fraction(time, of: Double(sequence.count) / framesPerSecond) * Double(sequence.count))
        return sequence[min(position, sequence.count - 1)]
    }

    // MARK: - Building

    /// Shapes drop in one after another, hold, then fall away together.
    private static func buildDrops(shapes: Int, at p: Double) -> [MarkPose.Drop] {
        let stagger = min(0.14, 0.42 / Double(max(shapes, 1)))
        let fall = 0.12
        return (0 ..< shapes).map { index in
            let start = stagger * Double(index)
            if p < start {
                return MarkPose.Drop(offset: -1.2, opacity: 1)
            }
            if p < start + fall {
                return MarkPose.Drop(offset: -1.2 * (1 - easeOutCubic((p - start) / fall)), opacity: 1)
            }
            if p < 0.8 {
                return MarkPose.Drop()
            }
            if p < 0.92 {
                let u = (p - 0.8) / 0.12
                return MarkPose.Drop(offset: 0.4 * u * u, opacity: 1 - u)
            }
            return MarkPose.Drop(offset: -1.2, opacity: 0)
        }
    }

    // MARK: - Easing

    static func fraction(_ time: TimeInterval, of period: TimeInterval) -> Double {
        let value = time.truncatingRemainder(dividingBy: period) / period
        return value < 0 ? value + 1 : value
    }

    /// Eased (in and out) between keyframes given as (fraction, value), in order.
    static func keyframes(_ frames: [(Double, Double)], at p: Double) -> Double {
        guard let first = frames.first else { return 0 }
        if p <= first.0 {
            return first.1
        }
        for (from, to) in zip(frames, frames.dropFirst()) where p <= to.0 {
            let span = to.0 - from.0
            let u = span > 0 ? (p - from.0) / span : 1
            return from.1 + (to.1 - from.1) * smooth(u)
        }
        return frames.last?.1 ?? 0
    }

    /// Ease in and out, clamped to 0…1.
    static func smooth(_ x: Double) -> Double {
        let t = min(max(x, 0), 1)
        return 0.5 - 0.5 * cos(.pi * t)
    }

    static func easeInOutCubic(_ x: Double) -> Double {
        let t = min(max(x, 0), 1)
        return t < 0.5 ? 4 * t * t * t : 1 - pow(-2 * t + 2, 3) / 2
    }

    static func easeOutCubic(_ x: Double) -> Double {
        let t = min(max(x, 0), 1)
        return 1 - pow(1 - t, 3)
    }

    /// A soft bump peaking at `center`.
    private static func pulse(_ time: TimeInterval, at center: TimeInterval, width: TimeInterval) -> Double {
        let distance = abs(time - center) / width
        return distance >= 1 ? 0 : smooth(1 - distance)
    }
}

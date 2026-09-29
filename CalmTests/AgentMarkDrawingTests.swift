import AppKit
@testable import Calm
import CalmAgents
import CalmModel
import Foundation
import Testing

struct SVGPathTests {
    @Test func `numbers may run together, as SVG allows`() {
        let commands = SVGPath.commands("M1.5.5L-2-3.25h1e1z")
        #expect(commands == [
            .move(CGPoint(x: 1.5, y: 0.5)),
            .line(CGPoint(x: -2, y: -3.25)),
            .line(CGPoint(x: 8, y: -3.25)),
            .close,
        ])
    }

    @Test func `relative commands and implicit lines follow the pen`() {
        let commands = SVGPath.commands("m10 10 5 0v5h-5z")
        #expect(commands == [
            .move(CGPoint(x: 10, y: 10)),
            .line(CGPoint(x: 15, y: 10)),
            .line(CGPoint(x: 15, y: 15)),
            .line(CGPoint(x: 10, y: 15)),
            .close,
        ])
    }

    @Test func `smooth curves reflect the last control point`() {
        let commands = SVGPath.commands("M0 0C0 1 1 1 1 0S2 -1 2 0")
        #expect(commands?.last == .cubic(CGPoint(x: 1, y: -1), CGPoint(x: 2, y: -1), to: CGPoint(x: 2, y: 0)))
    }

    @Test func `what it can't read makes no path`() {
        #expect(SVGPath.path("M0 0A5 5 0 0 1 10 10") == nil)
        #expect(SVGPath.path("M0") == nil)
        #expect(SVGPath.path("10 10") == nil)
    }

    @Test func `every agent's real mark reads, within its box`() throws {
        for adapter in Agents.adapters {
            let mark = adapter.mark
            for shape in mark.shapes {
                let path = try #require(SVGPath.path(shape.path), "\(adapter.kind)")
                let bounds = path.boundingRect
                let box = CGRect(x: mark.viewBox.x, y: mark.viewBox.y, width: mark.viewBox.side, height: mark.viewBox.side)
                #expect(!bounds.isEmpty, "\(adapter.kind)")
                #expect(box.insetBy(dx: -1, dy: -1).contains(bounds), "\(adapter.kind): \(bounds) outside \(box)")
            }
        }
    }
}

struct MarkMotionTests {
    @Test func `every motion loops back to where it began`() {
        let periods: [AgentMarkArt.Motion: Double] = [.turnAndRest: 2.2, .build: 3.2]
        for (motion, period) in periods {
            let start = MarkMotion.working(motion, shapes: 3, at: 0)
            let next = MarkMotion.working(motion, shapes: 3, at: period)
            #expect(abs(start.rotation.truncatingRemainder(dividingBy: 360) - next.rotation.truncatingRemainder(dividingBy: 360)) < 0.001)
            #expect(abs(start.scale - next.scale) < 0.001)
        }
    }

    @Test func `settling ends at rest, upright`() {
        for motion in [AgentMarkArt.Motion.frames, .turnAndRest, .pulseGrid, .build, .gradientTurn] {
            let pose = MarkMotion.finishing(motion, shapes: 3, at: MarkMotion.finishDuration(motion))
            #expect(abs(pose.rotation.truncatingRemainder(dividingBy: 360)) < 0.001, "\(motion)")
            #expect(abs(pose.scale - 1) < 0.001, "\(motion)")
            #expect(pose.markOpacity == 1, "\(motion)")
            #expect(pose.gridOpacity == 0, "\(motion)")
            #expect(pose.framesOpacity == 0, "\(motion)")
            #expect(pose.shine == nil, "\(motion)")
            #expect(abs(pose.gradientTurn.truncatingRemainder(dividingBy: 360)) < 0.001, "\(motion)")
            #expect(pose.drops.allSatisfy { abs($0.offset) < 0.001 && $0.opacity == 1 }, "\(motion)")
        }
    }

    @Test func `frames show for as long as each lasts, and loop`() {
        let sequence = [2, 0, 0, 1]
        #expect(MarkMotion.frameIndex(sequence: sequence, framesPerSecond: 10, at: 0.05) == 2)
        #expect(MarkMotion.frameIndex(sequence: sequence, framesPerSecond: 10, at: 0.25) == 0)
        #expect(MarkMotion.frameIndex(sequence: sequence, framesPerSecond: 10, at: 0.35) == 1)
        #expect(MarkMotion.frameIndex(sequence: sequence, framesPerSecond: 10, at: 0.45) == 2)
        #expect(MarkMotion.frameIndex(sequence: [], framesPerSecond: 10, at: 1) == 0)
    }

    @Test func `the Claude spinner's frames are all there and read`() throws {
        let frames = try #require(ClaudeCodeAdapter().mark.frames)
        #expect(frames.sequence.allSatisfy(frames.images.indices.contains))
        #expect(Set(frames.sequence) == Set(frames.images.indices))
        #expect(abs(Double(frames.sequence.count) / frames.framesPerSecond - 4) < 0.001)
        let sizes = try frames.images.map { try #require(NSImage(contentsOf: $0)).size }
        #expect(Set(sizes.map(\.width)).count == 1 && sizes.allSatisfy { $0.width == $0.height })
    }

    @Test func `a turn rests before the next one`() {
        #expect(MarkMotion.working(.turnAndRest, shapes: 1, at: 0.8).rotation > 90)
        #expect(MarkMotion.working(.turnAndRest, shapes: 1, at: 1.9).rotation == 0)
    }

    @Test func `built pieces drop in order and hold together`() {
        let early = MarkMotion.working(.build, shapes: 3, at: 0.2)
        #expect(early.drops[0].offset > early.drops[1].offset)
        let holding = MarkMotion.working(.build, shapes: 3, at: 2.0)
        #expect(holding.drops.allSatisfy { $0.offset == 0 && $0.opacity == 1 })
    }

    @Test func `the grid's squares stay in their ranges`() {
        for square in MarkMotion.gridSquares.indices {
            for step in 0 ..< 40 {
                let opacity = MarkMotion.gridOpacity(square: square, at: Double(step) * 0.1)
                let range = MarkMotion.gridSquares[square].inner ? 0.4 ... 1.0 : 0.15 ... 0.35
                #expect(range.contains(opacity))
            }
        }
    }

    @Test func `the light crosses, then rests`() {
        #expect(ShimmerText.phase(at: 0.78) != nil)
        #expect(ShimmerText.phase(at: 2.0) == nil)
    }

    /// The shimmer's timeline runs only while the light crosses; these are its wake-ups.
    @Test func `the light's next start or stop is timed from the cycle`() {
        // A whole number of cycles; 2.6 isn't exact in binary, so the times sit inside the spans
        // rather than on their edges, where rounding picks a side.
        let cycle = 2.6 * 1000
        #expect(abs(ShimmerText.untilChange(at: cycle + 0.01) - 1.55) < 1e-6) // just started crossing
        #expect(abs(ShimmerText.untilChange(at: cycle + 1.3) - 0.26) < 1e-6) // mid-crossing
        #expect(abs(ShimmerText.untilChange(at: cycle + 1.57) - 1.03) < 1e-6) // just started resting
        #expect(abs(ShimmerText.untilChange(at: cycle + 2.34) - 0.26) < 1e-6) // resting
        // Waking 5 ms after a change finds the light where the wait said it would be.
        #expect(ShimmerText.phase(at: cycle + 1.56 + 0.005) == nil)
        #expect(ShimmerText.phase(at: cycle + 2.6 + 0.005) != nil)
    }
}

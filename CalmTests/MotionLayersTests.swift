import AppKit
@testable import Calm
import CalmAgents
import CalmModel
import SwiftUI
import Testing

@MainActor
struct MotionLayersTests {
    /// Draws a view as snapshots do; it must be in a window, so it has the window's scale.
    private func pixels(_ view: NSView) throws -> [UInt8] {
        view.layoutSubtreeIfNeeded()
        let rep = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: rep)
        let data = try #require(rep.bitmapData)
        return Array(UnsafeBufferPointer(start: data, count: rep.bytesPerRow * rep.pixelsHigh))
    }

    /// The layer loop shows the frame the SwiftUI mark shows at the same moment, the same size
    /// and in the same place (`MarkDrawing`: the image, resizable, high interpolation, centered).
    @Test func `the layer loop draws the frame the SwiftUI mark draws`() throws {
        let frames = try #require(Agents.adapter(for: .claudeCode)?.mark.frames)
        let size: CGFloat = 26
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 100, height: 100), styleMask: .borderless, backing: .buffered, defer: false,
        )
        let box = NSRect(x: 0, y: 0, width: size, height: size)
        for time in [0.0, 0.47, 1.9, 3.31] {
            let index = MarkMotion.frameIndex(sequence: frames.sequence, framesPerSecond: frames.framesPerSecond, at: time)
            let image = try #require(NSImage(contentsOf: frames.images[index]))
            let swiftUI = NSHostingView(rootView: Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .frame(width: size * frames.scale, height: size * frames.scale)
                .frame(width: size, height: size))
            swiftUI.frame = box
            window.contentView?.addSubview(swiftUI)
            let drawn = try pixels(swiftUI)
            swiftUI.removeFromSuperview()

            let loop = MarkFramesLoopView(frame: box)
            loop.animates = false
            window.contentView?.addSubview(loop)
            loop.show(frames, size: size, at: time)
            let layered = try pixels(loop)
            loop.removeFromSuperview()

            #expect(drawn.count == layered.count)
            let differences = zip(drawn, layered).map { abs(Int($0) - Int($1)) }
            let mean = Double(differences.reduce(0, +)) / Double(max(differences.count, 1))
            // A pixel is off when any of its four channels is off by more than 8.
            let offPixels = stride(from: 0, to: differences.count - 3, by: 4).count { differences[$0 ..< $0 + 4].contains { $0 > 8 } }
            let share = Double(offPixels) / Double(max(differences.count / 4, 1))
            // Two resamplers never agree to the bit: here up to 3% of the pixels, at the edges, a mean
            // under 1. The frame resampled twice (shrunk, then stretched) was off in 13%, mean 2.5; a
            // wrong frame is off by far more.
            #expect(mean < 1.5, "time \(time): mean difference \(mean)")
            #expect(share < 0.05, "time \(time): \(offPixels) pixels off")
        }
    }

    /// Core Animation plays what MarkMotion.frameIndex reads: each image of the sequence for
    /// one frame, looping, started where the wall clock is in the loop.
    @Test func `the frames loop is the sequence, one image a frame, on the wall clock`() throws {
        let frames = try #require(Agents.adapter(for: .claudeCode)?.mark.frames)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 100, height: 100), styleMask: .borderless, backing: .buffered, defer: false,
        )
        let loop = MarkFramesLoopView(frame: NSRect(x: 0, y: 0, width: 26, height: 26))
        window.contentView?.addSubview(loop)
        loop.show(frames, size: 26, at: 1000.5)
        let animation = try #require(loop.framesForTesting)
        let length = Double(frames.sequence.count) / frames.framesPerSecond
        #expect(animation.values?.count == frames.sequence.count)
        #expect(animation.keyTimes?.count == frames.sequence.count + 1)
        #expect(animation.calculationMode == .discrete)
        #expect(animation.repeatCount == .infinity)
        #expect(abs(animation.duration - length) < 1e-9)
        #expect(abs(animation.timeOffset - MarkMotion.fraction(1000.5, of: length) * length) < 1e-9)
    }

    /// The band's leading edge goes from half a width before the line to its end in the first
    /// 60% of 2.6 s, then waits past the end: ShimmerText's (phase × 1.5 − 0.5) × width.
    @Test func `the light crosses the line in 60 percent of its period, then rests past the end`() throws {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 100), styleMask: .borderless, backing: .buffered, defer: false,
        )
        let band = ShimmerBandView(frame: NSRect(x: 0, y: 0, width: 120, height: 16))
        window.contentView?.addSubview(band)
        band.layoutSubtreeIfNeeded()
        let light = try #require(band.lightForTesting)
        #expect(light.values?.compactMap { ($0 as? NSNumber)?.doubleValue } == [-60, 120, 120])
        #expect(light.keyTimes?.map(\.doubleValue) == [0, ShimmerText.crossing, 1])
        #expect(light.duration == ShimmerText.period)
        #expect(light.repeatCount == .infinity)
    }

    @Test func `the loop keeps its frames once drawn at a size`() throws {
        let frames = try #require(Agents.adapter(for: .claudeCode)?.mark.frames)
        let first = MarkFrameImages.image(frames.images[0], tile: 26, scale: frames.scale, pixelsPerPoint: 2)
        #expect(first != nil)
        #expect(first?.width == 52)
        #expect(MarkFrameImages.image(frames.images[0], tile: 26, scale: frames.scale, pixelsPerPoint: 2) === first)
        #expect(MarkFrameImages.image(frames.images[0], tile: 28, scale: frames.scale, pixelsPerPoint: 2) !== first)
    }
}

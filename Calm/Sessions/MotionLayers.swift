import AppKit
import CalmAgents
import CalmModel
import QuartzCore
import SwiftUI

/// A `.frames` mark's working loop (Claude Code's spinner), played by Core Animation. The same
/// frames in a `TimelineView` had SwiftUI lay out and render the whole sidebar again 30 times a
/// second per working card, about 2% of a core each (2026-09-30), and nothing inside SwiftUI
/// kept a frame to the mark alone (DESIGNS.md → Agent marks). A layer animation runs in the
/// render server: the app does nothing between frames.
///
/// It keeps to the wall clock as `MarkMotion.frameIndex` does, so it shows the frame the SwiftUI
/// path would at the same moment: cards side by side agree, and the settling after the work
/// (still drawn by SwiftUI) carries on from the frame the loop was on.
struct MarkFramesLoop: NSViewRepresentable {
    let frames: AgentMarkArt.Frames
    /// The tile's side, in points.
    let size: CGFloat

    func makeNSView(context _: Context) -> MarkFramesLoopView {
        let view = MarkFramesLoopView()
        view.show(frames, size: size)
        return view
    }

    func updateNSView(_ view: MarkFramesLoopView, context _: Context) {
        view.show(frames, size: size)
    }
}

final class MarkFramesLoopView: NSView {
    private let imageLayer = CALayer()
    private var shown: Shown?
    /// Off only in the pixel test, which holds one frame to compare.
    var animates = true

    /// What the loop was last set up for: the frames, the tile's side and the screen's scale.
    private struct Shown: Equatable {
        var frames: AgentMarkArt.Frames
        var size: CGFloat
        var scale: CGFloat
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        imageLayer.contentsGravity = .resize
        layer?.addSublayer(imageLayer)
        setAccessibilityElement(false)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("not supported")
    }

    override var isFlipped: Bool {
        true
    }

    /// The images are drawn at the screen's pixel size, so a move to another display redraws them.
    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        if let shown {
            self.shown = nil
            show(shown.frames, size: shown.size)
        }
    }

    override func layout() {
        super.layout()
        placeImage()
    }

    /// `time` is the wall clock (`timeIntervalSinceReferenceDate`); tests pass one.
    func show(_ frames: AgentMarkArt.Frames, size: CGFloat, at time: TimeInterval = Date.now.timeIntervalSinceReferenceDate) {
        let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        let next = Shown(frames: frames, size: size, scale: scale)
        if shown == next {
            return
        }
        shown = next
        let images = frames.images.map { MarkFrameImages.image($0, tile: size, scale: frames.scale, pixelsPerPoint: scale) }
        guard !images.contains(where: { $0 == nil }), !frames.sequence.isEmpty, frames.framesPerSecond > 0 else {
            imageLayer.removeAllAnimations()
            imageLayer.contents = nil
            return
        }
        let sequence = frames.sequence.compactMap { images.indices.contains($0) ? images[$0] : nil }
        let duration = Double(sequence.count) / frames.framesPerSecond
        let animation = CAKeyframeAnimation(keyPath: "contents")
        animation.values = sequence
        animation.calculationMode = .discrete
        // One more key time than values: each image holds for one frame.
        animation.keyTimes = (0 ... sequence.count).map { NSNumber(value: Double($0) / Double(sequence.count)) }
        animation.duration = duration
        animation.repeatCount = .infinity
        animation.isRemovedOnCompletion = false
        // Where the wall clock is in the loop, as MarkMotion.frameIndex reads it.
        animation.timeOffset = MarkMotion.fraction(time, of: duration) * duration
        imageLayer.contentsScale = scale
        // The model value is the frame showing now; snapshots (which draw the model) show it.
        let index = MarkMotion.frameIndex(sequence: frames.sequence, framesPerSecond: frames.framesPerSecond, at: time)
        imageLayer.contents = images.indices.contains(index) ? images[index] : sequence.first
        imageLayer.removeAllAnimations()
        if animates {
            imageLayer.add(animation, forKey: "frames")
        }
        placeImage()
    }

    #if DEBUG
        /// The loop, for the unit tests.
        var framesForTesting: CAKeyframeAnimation? {
            imageLayer.animation(forKey: "frames") as? CAKeyframeAnimation
        }

        /// The image the loop shows this moment (its presentation), as an index into the frames'
        /// images, and the ones MarkMotion puts the wall clock on now and a frame either side,
        /// for the self-test probe.
        func sampleForTesting() -> (shown: Int?, expected: [Int])? {
            guard let shown, let current = imageLayer.presentation()?.contents else { return nil }
            let images = shown.frames.images.map {
                MarkFrameImages.image($0, tile: shown.size, scale: shown.frames.scale, pixelsPerPoint: shown.scale)
            }
            let index = images.firstIndex { $0.map { ($0 as AnyObject) === (current as AnyObject) } ?? false }
            let now = Date.now.timeIntervalSinceReferenceDate
            let frame = 1 / shown.frames.framesPerSecond
            let expected = [now, now - frame, now + frame].map {
                MarkMotion.frameIndex(sequence: shown.frames.sequence, framesPerSecond: shown.frames.framesPerSecond, at: $0)
            }
            return (index, expected)
        }
    #endif

    private func placeImage() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        // The images are the whole tile, pixel for pixel (MarkFrameImages).
        imageLayer.frame = bounds
        CATransaction.commit()
    }
}

/// The light crossing "Working" (ShimmerText), played by Core Animation: a band half the line's
/// width that crosses in the first 60% of every 2.6 s and rests past the end for the rest, on
/// the wall clock like `ShimmerText.phase`. Masked to the letters by the SwiftUI view around it.
struct ShimmerBand: NSViewRepresentable {
    let highlight: Color

    func makeNSView(context: Context) -> ShimmerBandView {
        let view = ShimmerBandView()
        view.highlight = highlight.resolve(in: context.environment).cgColor
        return view
    }

    func updateNSView(_ view: ShimmerBandView, context: Context) {
        view.highlight = highlight.resolve(in: context.environment).cgColor
    }
}

final class ShimmerBandView: NSView {
    private let band = CAGradientLayer()
    private var laidOut: (size: CGSize, color: CGColor)?

    #if DEBUG
        /// The crossing, for the unit tests.
        var lightForTesting: CAKeyframeAnimation? {
            band.animation(forKey: "light") as? CAKeyframeAnimation
        }
    #endif
    var highlight: CGColor = .white {
        didSet { restart() }
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        band.startPoint = CGPoint(x: 0, y: 0.5)
        band.endPoint = CGPoint(x: 1, y: 0.5)
        layer?.addSublayer(band)
        setAccessibilityElement(false)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("not supported")
    }

    override var isFlipped: Bool {
        true
    }

    override func layout() {
        super.layout()
        restart()
    }

    #if DEBUG
        /// The band's leading edge this moment (its presentation) and where ShimmerText's phase
        /// puts it, in points, for the self-test probe.
        func sampleForTesting() -> (shown: CGFloat, expected: CGFloat)? {
            guard let presented = band.presentation(), bounds.width > 0 else { return nil }
            let phase = ShimmerText.heldPhase ?? ShimmerText.phase(at: Date.now.timeIntervalSinceReferenceDate) ?? 1
            return (presented.transform.m41, (phase * 1.5 - 0.5) * bounds.width)
        }
    #endif

    private func restart() {
        let size = bounds.size
        if let laidOut, laidOut.size == size, laidOut.color == highlight {
            return
        }
        laidOut = (size, highlight)
        let width = size.width
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        band.colors = [highlight.copy(alpha: 0) ?? highlight, highlight, highlight.copy(alpha: 0) ?? highlight]
        band.frame = CGRect(x: 0, y: 0, width: width * 0.5, height: size.height)
        // Where the band's leading edge is, as ShimmerText draws it: (phase × 1.5 − 0.5) × width,
        // and past the end while it rests.
        let now = Date.now.timeIntervalSinceReferenceDate
        let phase = ShimmerText.heldPhase ?? ShimmerText.phase(at: now) ?? 1
        band.transform = CATransform3DMakeTranslation((phase * 1.5 - 0.5) * width, 0, 0)
        band.removeAllAnimations()
        if ShimmerText.heldPhase == nil, width > 0 {
            let light = CAKeyframeAnimation(keyPath: "transform.translation.x")
            light.values = [-0.5 * width, width, width]
            light.keyTimes = [0, NSNumber(value: ShimmerText.crossing), 1]
            light.timingFunctions = [CAMediaTimingFunction(name: .linear), CAMediaTimingFunction(name: .linear)]
            light.duration = ShimmerText.period
            light.repeatCount = .infinity
            light.isRemovedOnCompletion = false
            light.timeOffset = MarkMotion.fraction(now, of: ShimmerText.period) * ShimmerText.period
            band.add(light, forKey: "light")
        }
        CATransaction.commit()
    }
}

/// Each frame drawn once onto the whole tile, at the screen's pixels, where the SwiftUI path
/// draws it: centered, `scale` of the tile, resampled once with high quality (its
/// `.interpolation(.high)`). Shrunk to its own whole-pixel size instead, the layer stretched it
/// again to the fractional size and place, and the mark came out soft (the pixel test caught it).
@MainActor
enum MarkFrameImages {
    private static var cache: [String: CGImage] = [:]

    /// `tile` in points; `scale` is the share of the tile the frame fills.
    static func image(_ url: URL, tile: CGFloat, scale: Double, pixelsPerPoint: CGFloat) -> CGImage? {
        let canvas = Int((tile * pixelsPerPoint).rounded())
        let side = tile * scale * pixelsPerPoint
        let key = "\(url.path)@\(canvas)/\(side)"
        if let cached = cache[key] {
            return cached
        }
        guard canvas > 0, let source = NSImage(contentsOf: url)?.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let context = CGContext(
                  data: nil, width: canvas, height: canvas, bitsPerComponent: 8, bytesPerRow: 0,
                  space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue,
              )
        else { return nil }
        context.interpolationQuality = .high
        let origin = (CGFloat(canvas) - side) / 2
        context.draw(source, in: CGRect(x: origin, y: origin, width: side, height: side))
        let image = context.makeImage()
        cache[key] = image
        return image
    }
}

#if DEBUG
    /// `calm.layer_motion`: samples every mark loop and light in the window for two seconds and
    /// logs how often each showed what the wall clock says it should. Snapshots can't: they draw
    /// the layers' model values, not their animations.
    @MainActor
    enum LayerMotionProbe {
        static func run(in root: NSView?) async {
            guard let root else { return }
            var loops: [MarkFramesLoopView] = []
            var bands: [ShimmerBandView] = []
            collect(root, &loops, &bands)
            var frames = (samples: 0, exact: 0, withinAFrame: 0, unknown: 0)
            var light = (samples: 0, within: 0, worst: CGFloat(0))
            let end = ContinuousClock.now + .seconds(2)
            while ContinuousClock.now < end {
                for loop in loops {
                    guard let sample = loop.sampleForTesting() else { continue }
                    frames.samples += 1
                    guard let shown = sample.shown else {
                        frames.unknown += 1
                        continue
                    }
                    if shown == sample.expected[0] {
                        frames.exact += 1
                    }
                    if sample.expected.contains(shown) {
                        frames.withinAFrame += 1
                    }
                }
                for band in bands {
                    guard let sample = band.sampleForTesting() else { continue }
                    light.samples += 1
                    let off = abs(sample.shown - sample.expected)
                    light.worst = max(light.worst, off)
                    if off <= 2 {
                        light.within += 1
                    }
                }
                try? await Task.sleep(for: .milliseconds(37))
            }
            let line = "layer motion: \(loops.count) mark loops, \(frames.samples) samples, \(frames.exact) on the wall clock's frame, "
                + "\(frames.withinAFrame) within a frame, \(frames.unknown) unknown; \(bands.count) lights, \(light.samples) samples, "
                + "\(light.within) within 2 pt, worst \(String(format: "%.1f", light.worst)) pt"
            FileHandle.standardError.write(Data("calm-selftest: \(line)\n".utf8))
        }

        private static func collect(_ view: NSView, _ loops: inout [MarkFramesLoopView], _ bands: inout [ShimmerBandView]) {
            if let loop = view as? MarkFramesLoopView {
                loops.append(loop)
            }
            if let band = view as? ShimmerBandView {
                bands.append(band)
            }
            for child in view.subviews {
                collect(child, &loops, &bands)
            }
        }
    }
#endif

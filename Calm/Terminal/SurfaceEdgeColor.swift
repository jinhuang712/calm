import AppKit
import IOSurface

/// The color libghostty drew along the top edge of a pane, read back from the frame it rendered.
///
/// With `window-padding-color = extend`, an app that paints its own background (OpenCode, Neovim)
/// colors the padding too, but libghostty has no API for that color. The title strip above the
/// terminal reads it from the pixels instead, so the two meet without a seam (UIUX.md → Themes).
enum SurfaceEdgeColor {
    /// libghostty's renderer tags its frames Display P3 (renderer/metal/Target.zig); used when a
    /// frame carries no color space.
    private static let fallbackColorSpace = CGColorSpace(name: CGColorSpace.displayP3)

    /// Points read down each side of the pane, spread evenly over its height.
    private static let sideSamples = 32

    /// A pixel, as libghostty's BGRA frames store it.
    struct Pixel: Equatable {
        var blue, green, red, alpha: UInt8

        /// Within a rounding step of `other`, so a gradient of one shade counts as one color.
        func isClose(to other: Pixel) -> Bool {
            abs(Int(blue) - Int(other.blue)) <= 2 && abs(Int(green) - Int(other.green)) <= 2 && abs(Int(red) - Int(other.red)) <= 2
                && abs(Int(alpha) - Int(other.alpha)) <= 2
        }
    }

    /// What the strip should take from a frame's top edge and its sides (the padding beside each
    /// row takes that row's edge color): the top edge when at least half the sides are that color
    /// too, so it's the background the app painted its pane in (OpenCode, Neovim), and the strip
    /// meets the padding without a seam. Else `nil`, and the strip keeps the theme's background:
    /// a top edge the sides don't share is a band across the top (Claude Code's sticky prompt).
    /// The middle of the pane is never read, since it's content: a diff can fill most of it, and
    /// the strip once took its green. Half, not most, because one side can be a column in its own
    /// shade (Neovim's sign column, a file tree) while the other is the background.
    static func edge(top: Pixel, sides: [Pixel]) -> Pixel? {
        let matching = sides.count { $0.isClose(to: top) }
        return !sides.isEmpty && matching * 2 >= sides.count ? top : nil
    }

    /// The color the title strip should take from a frame: the middle of its top row (padding,
    /// unless the padding is zero) when the pane's sides agree (see `edge`). `nil` when they
    /// don't, when the frame isn't 32-bit BGRA, or when it isn't opaque (a translucent background).
    static func top(of surface: IOSurface) -> NSColor? {
        guard surface.pixelFormat == kCVPixelFormatType_32BGRA, surface.width > 0, surface.height > 0 else { return nil }
        guard surface.lock(options: .readOnly, seed: nil) == kIOReturnSuccess else { return nil }
        let (width, height, stride) = (surface.width, surface.height, surface.bytesPerRow)
        let base = surface.baseAddress.assumingMemoryBound(to: UInt8.self)
        func pixel(_ x: Int, _ y: Int) -> Pixel {
            let bytes = base.advanced(by: y * stride + x * 4)
            return Pixel(blue: bytes[0], green: bytes[1], red: bytes[2], alpha: bytes[3])
        }
        let top = pixel(width / 2, 0)
        var sides: [Pixel] = []
        for index in 0 ..< sideSamples {
            let row = height * (2 * index + 1) / (2 * sideSamples)
            sides += [pixel(0, row), pixel(width - 1, row)]
        }
        surface.unlock(options: .readOnly, seed: nil)
        guard top.alpha == 255, let chosen = edge(top: top, sides: sides) else { return nil }

        let space = IOSurfaceCopyValue(surface, kIOSurfaceColorSpace as CFString)
            .flatMap { CGColorSpace(propertyListPlist: $0) } ?? fallbackColorSpace
        let components = [chosen.red, chosen.green, chosen.blue].map { CGFloat($0) / 255 } + [1]
        guard let space, let color = CGColor(colorSpace: space, components: components) else { return nil }
        return NSColor(cgColor: color)
    }
}

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

    /// Rows read for the body color, as fractions of the height; a full-width band on one of them
    /// (a highlighted line) doesn't outvote the others.
    private static let bodyRows: [CGFloat] = [0.3, 0.5, 0.7]
    private static let samplesPerRow = 32

    /// A pixel, as libghostty's BGRA frames store it.
    struct Pixel: Equatable {
        var blue, green, red, alpha: UInt8

        /// Within a rounding step of `other`, so a gradient of one shade counts as one color.
        func isClose(to other: Pixel) -> Bool {
            abs(Int(blue) - Int(other.blue)) <= 2 && abs(Int(green) - Int(other.green)) <= 2 && abs(Int(red) - Int(other.red)) <= 2
        }
    }

    /// What the strip should take from a frame's top row and body: the top row when the app
    /// painted the whole pane in that color (padding extends it, and the strip meets it without a
    /// seam), else the body. A top row that differs from the body is a band on part of the pane, such as
    /// Claude Code's sticky prompt: the strip taking that band's color would look tinted.
    static func edge(top: Pixel, body: Pixel?) -> Pixel {
        guard let body, !top.isClose(to: body) else { return top }
        return body
    }

    /// The most common color among `samples`: quantized to shades, ties to the first seen.
    static func common(_ samples: [Pixel]) -> Pixel? {
        struct Tally {
            var count = 0
            let first: Int
            let pixel: Pixel
        }
        var tallies: [[UInt8]: Tally] = [:]
        for (index, pixel) in samples.enumerated() {
            let key = [pixel.blue >> 2, pixel.green >> 2, pixel.red >> 2]
            tallies[key, default: Tally(first: index, pixel: pixel)].count += 1
        }
        return tallies.values.max { ($0.count, -$0.first) < ($1.count, -$1.first) }?.pixel
    }

    /// The color the title strip should take from a frame: the middle of its top row (padding,
    /// unless the padding is zero), or the body's when only part of the pane is painted. `nil`
    /// when the frame isn't 32-bit BGRA or isn't opaque (a translucent background).
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
        var body: [Pixel] = []
        for fraction in bodyRows {
            let row = min(height - 1, Int(CGFloat(height) * fraction))
            for index in 0 ..< samplesPerRow {
                // Across the middle 7/8 of the row, clear of the padding at either side.
                body.append(pixel(width / 16 + (width * 7 / 8) * index / samplesPerRow, row))
            }
        }
        surface.unlock(options: .readOnly, seed: nil)
        guard top.alpha == 255 else { return nil }

        let chosen = edge(top: top, body: common(body).flatMap { $0.alpha == 255 ? $0 : nil })
        let space = IOSurfaceCopyValue(surface, kIOSurfaceColorSpace as CFString)
            .flatMap { CGColorSpace(propertyListPlist: $0) } ?? fallbackColorSpace
        let components = [chosen.red, chosen.green, chosen.blue].map { CGFloat($0) / 255 } + [1]
        guard let space, let color = CGColor(colorSpace: space, components: components) else { return nil }
        return NSColor(cgColor: color)
    }
}

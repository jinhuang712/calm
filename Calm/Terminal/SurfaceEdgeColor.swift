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

    /// The pixel in the middle of the frame's top row: padding, unless the padding is zero. `nil`
    /// when the frame isn't 32-bit BGRA or isn't opaque (a translucent background).
    static func top(of surface: IOSurface) -> NSColor? {
        guard surface.pixelFormat == kCVPixelFormatType_32BGRA, surface.width > 0, surface.height > 0 else { return nil }
        guard surface.lock(options: .readOnly, seed: nil) == kIOReturnSuccess else { return nil }
        let bytes = surface.baseAddress.advanced(by: surface.width / 2 * 4).assumingMemoryBound(to: UInt8.self)
        let (blue, green, red, alpha) = (bytes[0], bytes[1], bytes[2], bytes[3])
        surface.unlock(options: .readOnly, seed: nil)
        guard alpha == 255 else { return nil }

        let space = IOSurfaceCopyValue(surface, kIOSurfaceColorSpace as CFString)
            .flatMap { CGColorSpace(propertyListPlist: $0) } ?? fallbackColorSpace
        let components = [red, green, blue].map { CGFloat($0) / 255 } + [1]
        guard let space, let color = CGColor(colorSpace: space, components: components) else { return nil }
        return NSColor(cgColor: color)
    }
}

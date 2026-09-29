import AppKit
@testable import Calm
import IOSurface
import Testing

struct SurfaceEdgeColorTests {
    /// A 4×2 BGRA frame, tagged like libghostty's, painted all over in `bgra`.
    private func frame(bgra: [UInt8], space: CGColorSpace? = CGColorSpace(name: CGColorSpace.displayP3)) throws -> IOSurface {
        let surface = try #require(IOSurface(properties: [
            .width: 4, .height: 2, .bytesPerElement: 4, .pixelFormat: kCVPixelFormatType_32BGRA,
        ]))
        surface.lock(options: [], seed: nil)
        let bytes = surface.baseAddress.assumingMemoryBound(to: UInt8.self)
        for y in 0 ..< 2 {
            for x in 0 ..< 4 {
                for channel in 0 ..< 4 {
                    bytes[y * surface.bytesPerRow + x * 4 + channel] = bgra[channel]
                }
            }
        }
        surface.unlock(options: [], seed: nil)
        if let plist = space?.copyPropertyList() {
            IOSurfaceSetValue(surface, kIOSurfaceColorSpace as CFString, plist)
        }
        return surface
    }

    @Test func `reads the top row in the frame's color space`() throws {
        let color = try #require(SurfaceEdgeColor.top(of: frame(bgra: [10, 20, 30, 255])))
        #expect(color.colorSpace == NSColorSpace.displayP3)
        #expect(abs(color.redComponent - 30 / 255) < 0.001)
        #expect(abs(color.greenComponent - 20 / 255) < 0.001)
        #expect(abs(color.blueComponent - 10 / 255) < 0.001)
    }

    @Test func `an sRGB frame stays sRGB`() throws {
        let color = try #require(SurfaceEdgeColor.top(of: frame(bgra: [0, 0, 255, 255], space: CGColorSpace(name: CGColorSpace.sRGB))))
        #expect(color.colorSpace == NSColorSpace.sRGB)
        #expect(color.redComponent == 1)
    }

    @Test func `an untagged frame is read as Display P3, as libghostty renders`() throws {
        let color = try #require(SurfaceEdgeColor.top(of: frame(bgra: [0, 0, 0, 255], space: nil)))
        #expect(color.colorSpace == NSColorSpace.displayP3)
    }

    /// A 64×20 BGRA frame with each pixel painted by `color(x, y)`, as libghostty draws a pane.
    private func pane(_ color: (Int, Int) -> [UInt8]) throws -> IOSurface {
        let surface = try #require(IOSurface(properties: [
            .width: 64, .height: 20, .bytesPerElement: 4, .pixelFormat: kCVPixelFormatType_32BGRA,
        ]))
        surface.lock(options: [], seed: nil)
        let bytes = surface.baseAddress.assumingMemoryBound(to: UInt8.self)
        for y in 0 ..< 20 {
            for x in 0 ..< 64 {
                for channel in 0 ..< 4 {
                    bytes[y * surface.bytesPerRow + x * 4 + channel] = color(x, y)[channel]
                }
            }
        }
        surface.unlock(options: [], seed: nil)
        if let plist = CGColorSpace(name: CGColorSpace.displayP3)?.copyPropertyList() {
            IOSurfaceSetValue(surface, kIOSurfaceColorSpace as CFString, plist)
        }
        return surface
    }

    private let dark: [UInt8] = [26, 29, 33, 255]
    private let grey: [UInt8] = [96, 96, 96, 255]
    /// The dark green Claude Code paints under an added line of a diff.
    private let added: [UInt8] = [0, 40, 2, 255]

    private func red(_ color: NSColor?) -> Int {
        Int(((color?.redComponent ?? -1) * 255).rounded())
    }

    /// Whether (x, y) is in the middle of the pane, where content sits, clear of its sides.
    private func inMiddle(_ x: Int, _ y: Int, from top: Int = 2) -> Bool {
        (4 ..< 60).contains(x) && (top ..< 18).contains(y)
    }

    @Test func `an app that paints the whole pane colors the strip like it`() throws {
        // Neovim, OpenCode: the top row and the sides agree, so the strip meets them without a seam.
        #expect(try red(SurfaceEdgeColor.top(of: pane { _, _ in grey })) == 96)
    }

    @Test func `content in the middle of the pane does not tint the strip`() throws {
        // Claude Code with a long diff on screen: the green filled most of the middle, and the
        // strip took it, though the top edge and the sides were the terminal's own background.
        #expect(try red(SurfaceEdgeColor.top(of: pane { x, y in inMiddle(x, y) ? added : dark })) == 33)
    }

    @Test func `an app's background colors the strip with content across its middle`() throws {
        // OpenCode showing a diff: its background still runs down the sides.
        #expect(try red(SurfaceEdgeColor.top(of: pane { x, y in inMiddle(x, y) ? added : grey })) == 96)
    }

    @Test func `a band on the top rows gives no color, so the strip keeps the theme's`() throws {
        // Claude Code's sticky prompt: a lighter band on the first rows, dark below, and
        // whatever content is in the middle.
        #expect(try SurfaceEdgeColor.top(of: pane { _, y in y < 3 ? grey : dark }) == nil)
        #expect(try SurfaceEdgeColor.top(of: pane { x, y in y < 3 ? grey : inMiddle(x, y, from: 3) ? added : dark }) == nil)
    }

    @Test func `a full-width band on one row does not outvote the rest`() throws {
        #expect(try red(SurfaceEdgeColor.top(of: pane { _, y in y == 10 ? grey : dark })) == 33)
    }

    @Test func `one side in a shade of its own still lets the other agree`() throws {
        // Neovim's sign column, or a file tree, down the left; the background on the right.
        #expect(try red(SurfaceEdgeColor.top(of: pane { x, _ in x < 2 ? grey : dark })) == 33)
    }

    @Test func `sides a shade off the top row are the same color`() throws {
        let nearly: [UInt8] = [27, 30, 34, 255]
        #expect(try red(SurfaceEdgeColor.top(of: pane { _, y in y == 0 ? nearly : dark })) == 34)
    }

    @Test func `an opaque band over a translucent pane gives no color`() throws {
        #expect(try SurfaceEdgeColor.top(of: pane { _, y in y < 3 ? grey : [0, 0, 0, 128] }) == nil)
    }

    @Test func `a translucent edge gives no color`() throws {
        #expect(try SurfaceEdgeColor.top(of: frame(bgra: [0, 0, 0, 128])) == nil)
    }
}

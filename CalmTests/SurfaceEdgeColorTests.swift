import AppKit
@testable import Calm
import IOSurface
import Testing

struct SurfaceEdgeColorTests {
    /// A 4×2 BGRA frame, tagged like libghostty's, with `bgra` across the first row.
    private func frame(bgra: [UInt8], space: CGColorSpace? = CGColorSpace(name: CGColorSpace.displayP3)) throws -> IOSurface {
        let surface = try #require(IOSurface(properties: [
            .width: 4, .height: 2, .bytesPerElement: 4, .pixelFormat: kCVPixelFormatType_32BGRA,
        ]))
        surface.lock(options: [], seed: nil)
        let bytes = surface.baseAddress.assumingMemoryBound(to: UInt8.self)
        for x in 0 ..< 4 {
            for channel in 0 ..< 4 {
                bytes[x * 4 + channel] = bgra[channel]
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

    /// A 64×20 BGRA frame with each row painted by `row(y)`, as libghostty draws a pane.
    private func pane(_ row: (Int) -> [UInt8]) throws -> IOSurface {
        let surface = try #require(IOSurface(properties: [
            .width: 64, .height: 20, .bytesPerElement: 4, .pixelFormat: kCVPixelFormatType_32BGRA,
        ]))
        surface.lock(options: [], seed: nil)
        let bytes = surface.baseAddress.assumingMemoryBound(to: UInt8.self)
        for y in 0 ..< 20 {
            for x in 0 ..< 64 {
                for channel in 0 ..< 4 {
                    bytes[y * surface.bytesPerRow + x * 4 + channel] = row(y)[channel]
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

    private func red(_ color: NSColor?) -> Int {
        Int(((color?.redComponent ?? -1) * 255).rounded())
    }

    @Test func `an app that paints the whole pane colors the strip like it`() throws {
        // Neovim, OpenCode: the top row and the body agree, so the strip meets them without a seam.
        #expect(try red(SurfaceEdgeColor.top(of: pane { _ in grey })) == 96)
    }

    @Test func `a band on the top rows does not tint the strip`() throws {
        // Claude Code's sticky prompt: a lighter band on the first rows, dark below.
        #expect(try red(SurfaceEdgeColor.top(of: pane { $0 < 3 ? grey : dark })) == 33)
    }

    @Test func `a full-width band on one body row does not outvote the rest`() throws {
        #expect(try red(SurfaceEdgeColor.top(of: pane { $0 == 10 ? grey : dark })) == 33)
    }

    @Test func `a body a shade off the top row is the same color`() throws {
        let nearly: [UInt8] = [27, 30, 34, 255]
        #expect(try red(SurfaceEdgeColor.top(of: pane { $0 == 0 ? nearly : dark })) == 34)
    }

    @Test func `the top row wins over a body that isn't opaque`() throws {
        #expect(try red(SurfaceEdgeColor.top(of: pane { $0 < 3 ? grey : [0, 0, 0, 128] })) == 96)
    }

    @Test func `the most common shade wins, and a tie goes to the first seen`() {
        typealias Pixel = SurfaceEdgeColor.Pixel
        let (a, b) = (Pixel(blue: 10, green: 10, red: 10, alpha: 255), Pixel(blue: 200, green: 200, red: 200, alpha: 255))
        #expect(SurfaceEdgeColor.common([a, b, b]) == b)
        #expect(SurfaceEdgeColor.common([a, b]) == a)
        #expect(SurfaceEdgeColor.common([]) == nil)
    }

    @Test func `a translucent edge gives no color`() throws {
        #expect(try SurfaceEdgeColor.top(of: frame(bgra: [0, 0, 0, 128])) == nil)
    }
}

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

    @Test func `a translucent edge gives no color`() throws {
        #expect(try SurfaceEdgeColor.top(of: frame(bgra: [0, 0, 0, 128])) == nil)
    }
}

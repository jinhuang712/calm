import AppKit
@testable import Calm
import Testing

struct CalmWindowTests {
    @Test func `a title bar double-click does what System Settings says, Zoom when unset`() {
        #expect(TitleBarDoubleClick(setting: nil) == .zoom)
        #expect(TitleBarDoubleClick(setting: "Maximize") == .zoom)
        #expect(TitleBarDoubleClick(setting: "Fill") == .fill)
        #expect(TitleBarDoubleClick(setting: "Minimize") == .minimize)
        #expect(TitleBarDoubleClick(setting: "None") == .nothing)
        #expect(TitleBarDoubleClick(setting: "something new") == .zoom)
    }

    @Test func `a window is filled when it covers the screen's usable area`() {
        let screen = NSRect(x: 0, y: 0, width: 1800, height: 1129)
        #expect(CalmWindow.isFilled(frame: screen, in: screen))
        // Zoom, Fill and window managers round to whole points.
        #expect(CalmWindow.isFilled(frame: screen.insetBy(dx: 0.5, dy: 0.5), in: screen))
        #expect(!CalmWindow.isFilled(frame: NSRect(x: 350, y: 306, width: 1100, height: 720), in: screen))
        // Full width but not full height (a half-screen tile, or a dragged edge) is not filled.
        #expect(!CalmWindow.isFilled(frame: NSRect(x: 0, y: 0, width: 1800, height: 700), in: screen))
        // Dragged off its place, it is just a big window.
        #expect(!CalmWindow.isFilled(frame: screen.offsetBy(dx: 40, dy: 0), in: screen))
    }

    /// The shape AppKit hands the window server, read where it keeps it: a failure here means a
    /// macOS changed the private methods SquareCorners overrides, and corners stay round.
    @MainActor
    @Test func `square corners change the asking window's shape, and no other's`() throws {
        func window(_ x: CGFloat) -> CalmWindow {
            let window = CalmWindow(
                contentRect: NSRect(x: x, y: -20000, width: 400, height: 300),
                styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                backing: .buffered,
                defer: false,
            )
            window.isReleasedWhenClosed = false
            return window
        }
        func cornerAlpha(_ window: NSWindow) throws -> CGFloat {
            let frame = try #require(window.contentView?.superview)
            let mask = try #require(frame.value(forKey: "_cornerMask") as? NSImage)
            let image = try #require(mask.cgImage(forProposedRect: nil, context: nil, hints: nil))
            return try #require(NSBitmapImageRep(cgImage: image).colorAt(x: 0, y: 0)).alphaComponent
        }
        let asking = window(-20000)
        let other = window(-21000)
        defer {
            asking.close()
            other.close()
        }
        #expect(try cornerAlpha(asking) == 0)
        asking.setSquareCorners(true)
        #expect(try cornerAlpha(asking) == 1)
        #expect(try cornerAlpha(other) == 0)
        asking.setSquareCorners(false)
        #expect(try cornerAlpha(asking) == 0)
    }

    @MainActor
    @Test func `a window's corners go square as it fills the screen, and round as it leaves`() throws {
        let screen = try #require(NSScreen.main)
        let window = CalmWindow(
            contentRect: screen.visibleFrame.insetBy(dx: 200, dy: 150),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false,
        )
        window.isReleasedWhenClosed = false
        defer { window.close() }
        window.updateCorners()
        #expect(!window.hasSquareCorners)
        // A resize posts the notification the window follows; it isn't shown, so nothing appears.
        window.setFrame(screen.visibleFrame, display: false)
        #expect(window.hasSquareCorners)
        window.setFrame(screen.visibleFrame.insetBy(dx: 200, dy: 150), display: false)
        #expect(!window.hasSquareCorners)
    }
}

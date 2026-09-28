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
}

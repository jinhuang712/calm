import AppKit
@testable import Calm
import Testing

struct WindowMinimumTests {
    @Test func `the narrowest window is what the panels take plus the terminal's room`() {
        // The sidebar alone, at the standard size: half of a 13-inch MacBook Air's screen.
        #expect(WindowMinimum.width(sidebar: 320, files: 0, scale: 1, screenWidth: nil) == 720)
        // The sidebar hidden: the terminal's room alone.
        #expect(WindowMinimum.width(sidebar: 0, files: 0, scale: 1, screenWidth: nil) == 400)
        // The files column too.
        #expect(WindowMinimum.width(sidebar: 320, files: 272, scale: 1, screenWidth: nil) == 992)
    }

    @Test func `the terminal's room grows with the interface size`() {
        // Largest (150%): the sidebar is 480 and the terminal keeps 600.
        #expect(WindowMinimum.width(sidebar: 480, files: 0, scale: 1.5, screenWidth: nil) == 1080)
    }

    @Test func `the narrowest is never wider than the screen`() {
        // Largest with both panels needs 1488 pt; a 13-inch screen has 1470.
        #expect(WindowMinimum.width(sidebar: 480, files: 408, scale: 1.5, screenWidth: 1470) == 1470)
        #expect(WindowMinimum.width(sidebar: 320, files: 0, scale: 1, screenWidth: 1470) == 720)
    }

    @Test func `a window narrower than the minimum widens and stays on its screen`() {
        let screen = NSRect(x: 0, y: 0, width: 1470, height: 920)
        // Room to the right: it keeps its place and grows rightward.
        #expect(WindowMinimum.widened(NSRect(x: 100, y: 50, width: 500, height: 600), to: 720, on: screen)
            == NSRect(x: 100, y: 50, width: 720, height: 600))
        // Against the right edge: it moves left so it all stays on screen.
        #expect(WindowMinimum.widened(NSRect(x: 1000, y: 50, width: 400, height: 600), to: 720, on: screen)
            == NSRect(x: 750, y: 50, width: 720, height: 600))
        // Wide enough already: nothing to do.
        #expect(WindowMinimum.widened(NSRect(x: 0, y: 0, width: 900, height: 600), to: 720, on: screen) == nil)
    }
}

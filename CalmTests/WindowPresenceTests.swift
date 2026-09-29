import AppKit
@testable import Calm
import Testing

struct WindowPresenceTests {
    @Test func `a window in view is seen`() {
        #expect(WindowPresence.isVisible(.visible, headless: false))
    }

    @Test func `a covered, minimized or far-away window is not`() {
        #expect(!WindowPresence.isVisible([], headless: false))
    }

    @Test func `a headless run's transparent window counts as seen`() {
        #expect(WindowPresence.isVisible([], headless: true))
    }
}

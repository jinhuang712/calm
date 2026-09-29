@testable import Calm
import Testing

struct PaneVisibilityTests {
    @Test func `a pane on screen stops and starts with its window`() {
        var visibility = PaneVisibility()
        #expect(visibility.update { $0.isWindowVisible = false } == false)
        #expect(visibility.update { $0.isWindowVisible = true } == true)
    }

    @Test func `a hidden session's pane stays asleep when the window comes back into view`() {
        var visibility = PaneVisibility()
        #expect(visibility.update { $0.isShown = false } == false)
        // Switched to another Space and back: the window is occluded, then visible again.
        #expect(visibility.update { $0.isWindowVisible = false } == nil)
        #expect(visibility.update { $0.isWindowVisible = true } == nil)
        #expect(!visibility.drawsFrames)
    }

    @Test func `a session shown while its window is covered draws once the window is seen`() {
        var visibility = PaneVisibility(isShown: false, isWindowVisible: false)
        #expect(visibility.update { $0.isShown = true } == nil)
        #expect(visibility.update { $0.isWindowVisible = true } == true)
    }

    @Test func `repeating a state changes nothing`() {
        var visibility = PaneVisibility()
        #expect(visibility.update { $0.isShown = true } == nil)
        #expect(visibility.update { $0.isWindowVisible = true } == nil)
    }
}

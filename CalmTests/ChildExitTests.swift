@testable import Calm
import Testing

/// libghostty's queued "child exited" report can reach the surface allocated where a freed one was.
@MainActor
struct ChildExitTests {
    @Test func `a pane's own process can't have run longer than the pane`() {
        #expect(TerminalSurfaceView.childExit(runtime: 300, fitsPaneAged: 0.4))
        #expect(TerminalSurfaceView.childExit(runtime: 60000, fitsPaneAged: 90))
    }

    @Test func `a report from an earlier surface doesn't close the new pane`() {
        // Seen in real use: a session closed after 13 s of zmx, its report reached a pane 0.3 s old.
        #expect(!TerminalSurfaceView.childExit(runtime: 13000, fitsPaneAged: 0.3))
    }
}

import AppKit
@testable import Calm
import Testing

/// Dictation and voice input methods reach a pane through NSTextInputClient, and both give up
/// quietly: dictation when the pane says it has no insertion point, and text a voice engine
/// commits after the key that started it is over when the pane drops it.
@MainActor
struct DictationInputTests {
    private func pane(command: String) throws -> TerminalSurfaceView {
        var options = TerminalSurfaceOptions.session
        options.command = command
        options.size = NSSize(width: 780, height: 672)
        let pane = TerminalSurfaceView(options: options)
        try #require(pane.surface != nil)
        return pane
    }

    /// Polls the screen: a program's echo reaches the grid a moment after the write.
    private func waitForText(_ text: String, in pane: TerminalSurfaceView) async -> Bool {
        for _ in 0 ..< 100 {
            if pane.viewportText()?.contains(text) == true {
                return true
            }
            try? await Task.sleep(for: .milliseconds(50))
        }
        return false
    }

    /// `{NSNotFound, 0}` reads as "this view has no insertion point": System Dictation never
    /// starts, and voice tools that look for a text field find none.
    @Test func `a pane with no selection has a caret to dictate into`() throws {
        let pane = try pane(command: "/bin/sleep 30")
        defer { pane.teardown() }
        let range = pane.selectedRange()
        #expect(range.location != NSNotFound)
        #expect(range.length == 0)
    }

    /// Voice engines commit from their own callback, not while a key event is being handled.
    @Test func `text committed with no event in flight reaches the program`() async throws {
        let pane = try pane(command: "/bin/cat")
        defer { pane.teardown() }
        try #require(NSApp.currentEvent == nil, "the test must run outside an event, as a voice engine's commit does")
        pane.insertText("dictated words", replacementRange: NSRange(location: NSNotFound, length: 0))
        #expect(await waitForText("dictated words", in: pane))
    }
}

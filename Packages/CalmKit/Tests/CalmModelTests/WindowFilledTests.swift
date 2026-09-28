@testable import CalmModel
import Foundation
import Testing

struct WindowFilledTests {
    /// `#expect` can't call a mutating method directly.
    func note(_ filled: Bool, in workspace: inout Workspace) -> Bool {
        workspace.noteWindowFilled(filled)
    }

    @Test func `a window left filling the screen is kept and reported as a change once`() {
        var workspace = Workspace()
        #expect(note(true, in: &workspace))
        #expect(workspace.windowFilled == true)
        // Every resize event reports the same state; only the first is news.
        #expect(!note(true, in: &workspace))
    }

    @Test func `leaving the filled state stores nothing`() {
        var workspace = Workspace()
        _ = workspace.noteWindowFilled(true)
        #expect(note(false, in: &workspace))
        #expect(workspace.windowFilled == nil)
        #expect(!note(false, in: &workspace))
    }

    @Test func `a window that was never filled is no change`() {
        var workspace = Workspace()
        #expect(!note(false, in: &workspace))
        #expect(workspace.windowFilled == nil)
    }

    @Test func `the filled state is saved, and older state without it still loads`() throws {
        var workspace = Workspace()
        _ = workspace.noteWindowFilled(true)
        let decoded = try JSONDecoder().decode(Workspace.self, from: JSONEncoder().encode(workspace))
        #expect(decoded.windowFilled == true)

        let older = try JSONDecoder().decode(Workspace.self, from: Data(#"{"projects": [], "sessions": [], "layouts": []}"#.utf8))
        #expect(older.windowFilled == nil)
    }
}

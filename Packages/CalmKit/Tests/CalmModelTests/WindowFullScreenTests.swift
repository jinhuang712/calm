@testable import CalmModel
import Foundation
import Testing

struct WindowFullScreenTests {
    /// `#expect` can't call a mutating method directly.
    func note(_ fullScreen: Bool, in workspace: inout Workspace) -> Bool {
        workspace.noteWindowFullScreen(fullScreen)
    }

    @Test func `a window left in full screen is kept and reported as a change once`() {
        var workspace = Workspace()
        #expect(note(true, in: &workspace))
        #expect(workspace.windowFullScreen == true)
        #expect(!note(true, in: &workspace))
    }

    @Test func `leaving full screen stores nothing`() {
        var workspace = Workspace()
        _ = workspace.noteWindowFullScreen(true)
        #expect(note(false, in: &workspace))
        #expect(workspace.windowFullScreen == nil)
        #expect(!note(false, in: &workspace))
    }

    @Test func `full screen is kept apart from a filled window under it`() {
        // Zoomed, then full screen: leaving full screen goes back to the zoomed window.
        var workspace = Workspace()
        _ = workspace.noteWindowFilled(true)
        _ = workspace.noteWindowFullScreen(true)
        #expect(workspace.windowFilled == true)
        #expect(workspace.windowFullScreen == true)
        _ = workspace.noteWindowFullScreen(false)
        #expect(workspace.windowFilled == true)
        #expect(workspace.windowFullScreen == nil)
    }

    @Test func `full screen is saved, and older state without it still loads`() throws {
        var workspace = Workspace()
        _ = workspace.noteWindowFullScreen(true)
        let decoded = try JSONDecoder().decode(Workspace.self, from: JSONEncoder().encode(workspace))
        #expect(decoded.windowFullScreen == true)

        // State saved by the version that only knew filled windows.
        let json = #"{"projects": [], "sessions": [], "layouts": [], "windowFilled": true}"#
        let older = try JSONDecoder().decode(Workspace.self, from: Data(json.utf8))
        #expect(older.windowFullScreen == nil)
        #expect(older.windowFilled == true)
    }
}

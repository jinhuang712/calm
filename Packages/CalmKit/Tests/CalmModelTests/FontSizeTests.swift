@testable import CalmModel
import Foundation
import Testing

struct FontSizeTests {
    /// `#expect` can't call a mutating method directly.
    func note(_ points: Float, configured: Float?, in workspace: inout Workspace) -> Bool {
        workspace.noteFontSize(points, configured: configured)
    }

    @Test func `a zoomed size is kept and reported as a change once`() {
        var workspace = Workspace()
        #expect(note(15, configured: 13, in: &workspace))
        #expect(workspace.fontSize == 15)
        // The other panes, resized to match, report the same size back.
        #expect(!note(15, configured: 13, in: &workspace))
    }

    @Test func `going back to the config's size stores nothing`() {
        var workspace = Workspace()
        _ = workspace.noteFontSize(15, configured: 13)
        #expect(note(13, configured: 13, in: &workspace))
        #expect(workspace.fontSize == nil)
        #expect(!note(13, configured: 13, in: &workspace))
    }

    @Test func `a config change at the default size is not a zoom`() {
        var workspace = Workspace()
        // font-size went from 13 to 14 in the config; panes follow it and report 14.
        #expect(!note(14, configured: 14, in: &workspace))
        #expect(workspace.fontSize == nil)
    }

    @Test func `without a configured size any size is kept`() {
        var workspace = Workspace()
        #expect(note(13, configured: nil, in: &workspace))
        #expect(workspace.fontSize == 13)
    }

    @Test func `the size is saved, and older state without it still loads`() throws {
        var workspace = Workspace()
        _ = workspace.noteFontSize(16.5, configured: 13)
        let decoded = try JSONDecoder().decode(Workspace.self, from: JSONEncoder().encode(workspace))
        #expect(decoded.fontSize == 16.5)

        let older = try JSONDecoder().decode(Workspace.self, from: Data(#"{"projects": [], "sessions": [], "layouts": []}"#.utf8))
        #expect(older.fontSize == nil)
    }
}

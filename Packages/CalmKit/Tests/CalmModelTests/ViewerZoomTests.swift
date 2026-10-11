@testable import CalmModel
import Foundation
import Testing

struct ViewerZoomTests {
    /// `#expect` can't call a mutating method directly.
    func note(_ zoom: Double, in workspace: inout Workspace) -> Bool {
        workspace.noteViewerZoom(zoom)
    }

    @Test func `a page steps up and down through the browser's sizes`() {
        #expect(ViewerZoom.step(1, bigger: true, kind: .page) == 1.1)
        #expect(ViewerZoom.step(1.1, bigger: true, kind: .page) == 1.25)
        #expect(ViewerZoom.step(1, bigger: false, kind: .page) == 0.9)
        #expect(ViewerZoom.step(0.67, bigger: false, kind: .page) == 0.5)
    }

    @Test func `the ends stay where they are`() {
        #expect(ViewerZoom.step(3, bigger: true, kind: .page) == 3)
        #expect(ViewerZoom.step(0.5, bigger: false, kind: .page) == 0.5)
        #expect(ViewerZoom.step(8, bigger: true, kind: .picture) == 8)
        #expect(ViewerZoom.step(0.5, bigger: false, kind: .picture) == 0.5)
    }

    @Test func `a size between steps goes to the nearer step that way`() {
        // A pinch left a picture at 1.37 of its fitting size.
        #expect(ViewerZoom.step(1.37, bigger: true, kind: .picture) == 1.5)
        #expect(ViewerZoom.step(1.37, bigger: false, kind: .picture) == 1.25)
        // Past the last step, ⌘− comes back to it rather than staying out there.
        #expect(ViewerZoom.step(10, bigger: false, kind: .picture) == 8)
    }

    @Test func `a size a hair off a step counts as that step`() {
        // 2/3 is what 0.67 reads back as after a round trip through a view's scale.
        #expect(ViewerZoom.step(2.0 / 3.0, bigger: true, kind: .page) == 0.75)
        #expect(ViewerZoom.step(2.0 / 3.0, bigger: false, kind: .page) == 0.5)
    }

    @Test func `pictures zoom further in than pages`() {
        #expect(ViewerZoom.step(3, bigger: true, kind: .picture) == 4)
        #expect(ViewerZoom.step(1, bigger: true, kind: .picture) == 1.25)
    }

    @Test func `the row says a size as a whole percentage`() {
        #expect(ViewerZoom.percent(1.25) == "125%")
        #expect(ViewerZoom.percent(1.1) == "110%")
        #expect(ViewerZoom.percent(0.67) == "67%")
        #expect(ViewerZoom.percent(2.0 / 3.0) == "67%")
        #expect(ViewerZoom.percent(8) == "800%")
    }

    @Test func `the size shows off 100%, and at 100% only under the pointer`() {
        #expect(ViewerZoom.showsSize(1.25, hovered: false))
        #expect(ViewerZoom.showsSize(0.9, hovered: false))
        #expect(!ViewerZoom.showsSize(1, hovered: false))
        // Stepped onto 100% with its own + or −: it stays until the pointer leaves.
        #expect(ViewerZoom.showsSize(1, hovered: true))
        #expect(!ViewerZoom.showsSize(1.0000001, hovered: false))
    }

    @Test func `a zoomed page size is kept and reported as a change once`() {
        var workspace = Workspace()
        #expect(note(1.25, in: &workspace))
        #expect(workspace.viewerZoom == 1.25)
        #expect(!note(1.25, in: &workspace))
    }

    @Test func `going back to a page's own size stores nothing`() {
        var workspace = Workspace()
        _ = workspace.noteViewerZoom(1.5)
        #expect(note(1, in: &workspace))
        #expect(workspace.viewerZoom == nil)
        #expect(!note(1, in: &workspace))
    }

    @Test func `the size is saved, and older state without it still loads`() throws {
        var workspace = Workspace()
        _ = workspace.noteViewerZoom(1.75)
        let decoded = try JSONDecoder().decode(Workspace.self, from: JSONEncoder().encode(workspace))
        #expect(decoded.viewerZoom == 1.75)

        let older = try JSONDecoder().decode(Workspace.self, from: Data(#"{"projects": [], "sessions": [], "layouts": []}"#.utf8))
        #expect(older.viewerZoom == nil)
    }
}

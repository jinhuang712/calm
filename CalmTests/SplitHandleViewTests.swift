import AppKit
@testable import Calm
import CalmModel
import Foundation
import Testing

/// The split icon's place and what it takes a click for (UIUX.md → Split panes).
@MainActor
struct SplitHandleViewTests {
    /// A flipped parent, as the workspace view is, so the icons' own coordinates are the parent's.
    private final class Parent: NSView {
        override var isFlipped: Bool {
            true
        }
    }

    private func layer(with handle: SplitHandleView) -> (Parent, HandlesView) {
        let parent = Parent(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        let handles = HandlesView(frame: parent.bounds)
        parent.addSubview(handles)
        handle.frame = NSRect(x: 360, y: 8, width: 24, height: 24)
        handles.addSubview(handle)
        return (parent, handles)
    }

    @Test func `the icon sits in the pane's top right corner`() {
        let frame = TerminalWorkspaceView.handleFrame(in: NSRect(x: 100, y: 50, width: 400, height: 300))
        #expect(frame == NSRect(x: 468, y: 58, width: 24, height: 24))
    }

    @Test func `an icon that shows takes the click and the rest of the pane does not`() {
        let handle = SplitHandleView(paneID: UUID())
        let (_, handles) = layer(with: handle)
        handle.alphaValue = 1
        #expect(handles.hitTest(NSPoint(x: 370, y: 20)) === handle)
        // The terminal under it keeps everything else.
        #expect(handles.hitTest(NSPoint(x: 100, y: 150)) == nil)
    }

    @Test func `an icon that is hidden lets the click through to the terminal`() {
        let handle = SplitHandleView(paneID: UUID())
        let (_, handles) = layer(with: handle)
        handle.alphaValue = 0
        #expect(handles.hitTest(NSPoint(x: 370, y: 20)) == nil)
    }

    @Test func `a session dragged from the sidebar carries Calm's own type and nothing the terminal would take`() {
        let provider = ActiveSessionDrag.provider(for: UUID())
        #expect(provider.hasItemConformingToTypeIdentifier(SessionDrag.typeIdentifier))
        #expect(!provider.hasItemConformingToTypeIdentifier("public.utf8-plain-text"))
        #expect(!provider.hasItemConformingToTypeIdentifier("public.file-url"))
        #expect(ActiveSessionDrag.current?.origin == .card)
    }
}

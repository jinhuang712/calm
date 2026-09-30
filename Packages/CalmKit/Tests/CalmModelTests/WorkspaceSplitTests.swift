@testable import CalmModel
import Foundation
import Testing

/// Bringing an existing session into a split, taking a pane out of one, and unsplitting
/// (UIUX.md → Split panes). None of them ends a session.
struct WorkspaceSplitTests {
    /// A split of `a` and `b`, and a session `c` alone in its own layout (the one on screen).
    private struct Trio {
        var workspace = Workspace()
        let a: Session.ID
        let b: Session.ID
        let c: Session.ID
    }

    private func makeTrio() throws -> Trio {
        var workspace = Workspace()
        let a = workspace.newSession(in: "/tmp/a")
        let split = workspace.splitSession(a.id, direction: .right, in: "/tmp/a")
        let b = try #require(split)
        let c = workspace.newSession(in: "/tmp/c")
        return Trio(workspace: workspace, a: a.id, b: b.id, c: c.id)
    }

    // MARK: Joining

    @Test func `a session joins the split beside another and its layout goes`() throws {
        let trio = try makeTrio()
        var workspace = trio.workspace
        let a = trio.a
        let b = trio.b
        let c = trio.c
        #expect(workspace.layouts.count == 2)
        let joined = workspace.join(c, beside: a, direction: .right)
        #expect(joined)
        #expect(workspace.layouts.count == 1)
        let layout = try #require(workspace.selectedLayout)
        #expect(layout.tree.leaves == [a, c, b])
        #expect(layout.focusedSessionID == c)
    }

    @Test func `the layout it came from keeps its other panes`() throws {
        let trio = try makeTrio()
        var workspace = trio.workspace
        let a = trio.a
        let b = trio.b
        let c = trio.c
        let below = workspace.splitSession(c, direction: .down, in: "/tmp/c")
        let d = try #require(below).id
        let joined = workspace.join(d, beside: a, direction: .left)
        #expect(joined)
        #expect(workspace.layout(containing: a)?.tree.leaves == [d, a, b])
        // c stays on its own, now the layout's only pane and its focus.
        let rest = try #require(workspace.layout(containing: c))
        #expect(rest.tree == .leaf(c))
        #expect(rest.focusedSessionID == c)
        #expect(workspace.selectedLayout?.id == workspace.layout(containing: a)?.id)
    }

    @Test func `a pane moves within its own split`() throws {
        let trio = try makeTrio()
        var workspace = trio.workspace
        let a = trio.a
        let b = trio.b
        let layoutID = try #require(workspace.layout(containing: a)?.id)
        let joined = workspace.join(a, beside: b, direction: .right)
        #expect(joined)
        let layout = try #require(workspace.layout(containing: b))
        #expect(layout.id == layoutID)
        #expect(layout.tree.leaves == [b, a])
        #expect(layout.focusedSessionID == a)
    }

    @Test func `nothing joins itself, or something that isn't there`() throws {
        let trio = try makeTrio()
        var workspace = trio.workspace
        let a = trio.a
        let c = trio.c
        let before = workspace
        let itself = workspace.join(a, beside: a, direction: .right)
        let stranger = workspace.join(UUID(), beside: a, direction: .right)
        let nowhere = workspace.join(c, beside: UUID(), direction: .right)
        #expect(!itself && !stranger && !nowhere)
        #expect(workspace == before)
    }

    @Test func `joining opens the group it sits in`() throws {
        let trio = try makeTrio()
        var workspace = trio.workspace
        let a = trio.a
        let c = trio.c
        let project = try #require(workspace.session(c)?.projectID)
        workspace.setCollapsed(project, true)
        #expect(workspace.isInCollapsedGroup(c))
        let joined = workspace.join(c, beside: a, direction: .down)
        #expect(joined)
        #expect(!workspace.isInCollapsedGroup(c))
    }

    // MARK: Taking out

    @Test func `a pane taken out is a session of its own and the split stays on screen`() throws {
        let trio = try makeTrio()
        var workspace = trio.workspace
        let a = trio.a
        let b = trio.b
        let c = trio.c
        workspace.select(a)
        let joined = workspace.join(c, beside: b, direction: .down) // a | (b over c), focus on c
        #expect(joined)
        let split = try #require(workspace.selectedLayout?.id)
        let out = workspace.takeOut(b)
        #expect(out)
        #expect(workspace.selectedLayout?.id == split)
        #expect(workspace.selectedLayout?.tree.leaves == [a, c])
        let alone = try #require(workspace.layout(containing: b))
        #expect(alone.tree == .leaf(b))
        #expect(alone.id != split)
        #expect(workspace.sessions.count == 3)
    }

    @Test func `taking out the focused pane hands the focus to the pane that took its room`() throws {
        let trio = try makeTrio()
        var workspace = trio.workspace
        let a = trio.a
        let b = trio.b
        let c = trio.c
        let joined = workspace.join(c, beside: b, direction: .down) // a | (b over c); focus on c
        #expect(joined)
        #expect(workspace.selectedLayout?.focusedSessionID == c)
        let out = workspace.takeOut(c)
        #expect(out)
        #expect(workspace.selectedLayout?.focusedSessionID == b)
        #expect(workspace.selectedLayout?.tree.leaves == [a, b])
    }

    @Test func `a pane that is alone has nothing to leave`() throws {
        let trio = try makeTrio()
        var workspace = trio.workspace
        let c = trio.c
        let before = workspace
        let out = workspace.takeOut(c)
        #expect(!out)
        #expect(workspace == before)
    }

    // MARK: Unsplitting

    @Test func `unsplitting leaves the pane you're in and gives every other its own layout`() throws {
        let trio = try makeTrio()
        var workspace = trio.workspace
        let a = trio.a
        let b = trio.b
        let c = trio.c
        let joined = workspace.join(c, beside: b, direction: .down) // a | (b over c); focus on c
        #expect(joined)
        let split = try #require(workspace.selectedLayout?.id)
        let freed = workspace.unsplit(split)
        #expect(freed == [a, b])
        #expect(workspace.selectedLayout?.id == split)
        #expect(workspace.selectedLayout?.tree == .leaf(c))
        for id in [a, b] {
            #expect(workspace.layout(containing: id)?.tree == .leaf(id))
        }
        #expect(workspace.layouts.count == 3)
        #expect(workspace.sessions.count == 3)
    }

    @Test func `a layout of one has nothing to unsplit`() throws {
        let trio = try makeTrio()
        var workspace = trio.workspace
        let c = trio.c
        let alone = try #require(workspace.layout(containing: c)?.id)
        let freed = workspace.unsplit(alone)
        #expect(freed.isEmpty)
    }

    // MARK: What the sidebar lights up

    @Test func `every session of a split on screen is in view, and a lone one is not`() throws {
        let trio = try makeTrio()
        var workspace = trio.workspace
        let a = trio.a
        let b = trio.b
        let c = trio.c
        #expect(workspace.selectedLayout?.tree.leaves == [c])
        #expect(workspace.sessionsInView.isEmpty)
        workspace.select(a)
        #expect(workspace.sessionsInView == [a, b])
        workspace.select(c)
        #expect(workspace.sessionsInView.isEmpty)
    }

    @Test func `nothing is in view while no session is chosen`() throws {
        let trio = try makeTrio()
        var workspace = trio.workspace
        workspace.selectedLayoutID = nil
        #expect(workspace.sessionsInView.isEmpty)
    }
}

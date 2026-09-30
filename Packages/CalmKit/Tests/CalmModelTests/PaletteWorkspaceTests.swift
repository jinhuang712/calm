@testable import CalmModel
import Foundation
import Testing

/// What the ⌘P palette does to the workspace: unsplit, go to the welcome page, mark done sessions
/// seen, fold every group.
struct PaletteWorkspaceTests {
    // MARK: Unsplit

    @Test func `unsplit gives every pane a layout of its own and closes nothing`() throws {
        var workspace = Workspace()
        let first = workspace.newSession(in: "/dev/apps/calm")
        let splitOnce = workspace.splitSession(first.id, direction: .right, in: "/dev/apps/calm")
        let second = try #require(splitOnce)
        let splitTwice = workspace.splitSession(second.id, direction: .down, in: "/dev/apps/calm")
        let third = try #require(splitTwice)
        let layoutID = try #require(workspace.layout(containing: first.id)?.id)
        #expect(workspace.layouts.count == 1)

        let apart = workspace.unsplit(layoutID)

        #expect(apart.count == 3)
        #expect(workspace.layouts.count == 3)
        #expect(workspace.sessions.count == 3)
        #expect(workspace.layouts.allSatisfy { $0.tree.leaves.count == 1 })
        // In the order the panes had, and each layout shows exactly its session.
        #expect(workspace.layouts.map(\.focusedSessionID) == [first.id, second.id, third.id])
        for session in [first, second, third] {
            #expect(workspace.layout(containing: session.id)?.tree.leaves == [session.id])
        }
    }

    @Test func `the session in focus keeps the layout that was on screen`() throws {
        var workspace = Workspace()
        let first = workspace.newSession(in: "/dev/apps/calm")
        let split = workspace.splitSession(first.id, direction: .right, in: "/dev/apps/calm")
        let second = try #require(split)
        let shown = try #require(workspace.selectedLayout)
        #expect(shown.focusedSessionID == second.id)

        workspace.unsplit(shown.id)

        #expect(workspace.selectedLayoutID == shown.id)
        #expect(workspace.selectedLayout?.tree.leaves == [second.id])
        #expect(workspace.layout(containing: first.id)?.id != shown.id)
    }

    @Test func `a layout with one session, or none, is left alone`() throws {
        var workspace = Workspace()
        let only = workspace.newSession(in: "/dev/apps/calm")
        let layouts = workspace.layouts
        let layoutID = try #require(workspace.layout(containing: only.id)?.id)
        let single = workspace.unsplit(layoutID)
        let missing = workspace.unsplit(UUID())
        #expect(single.isEmpty)
        #expect(missing.isEmpty)
        #expect(workspace.layouts == layouts)
    }

    // MARK: The welcome page

    @Test func `deselecting chooses no session and settles the one left`() {
        var workspace = Workspace()
        let session = workspace.newSession(in: "/dev/apps/calm")
        workspace.setState(session.id, .done)

        workspace.deselect()

        #expect(workspace.selectedLayout == nil)
        #expect(workspace.sessions.count == 1)
        #expect(workspace.session(session.id)?.state == .idle)
    }

    @Test func `deselecting with nothing chosen does nothing`() {
        var workspace = Workspace()
        workspace.deselect()
        #expect(workspace.selectedLayout == nil)
    }

    // MARK: Mark all done as seen

    @Test func `only finished sessions the user isn't in settle`() {
        var workspace = Workspace()
        let done = workspace.newSession(in: "/dev/apps/a")
        let failed = workspace.newSession(in: "/dev/apps/b")
        let waiting = workspace.newSession(in: "/dev/apps/c")
        let working = workspace.newSession(in: "/dev/apps/d")
        let current = workspace.newSession(in: "/dev/apps/e")
        workspace.setState(done.id, .done)
        workspace.setState(failed.id, .failed)
        workspace.setState(waiting.id, .needsYou)
        workspace.setState(working.id, .working)
        workspace.setState(current.id, .done)
        workspace.select(current.id)

        let settled = workspace.markDoneSeen(except: current.id)

        #expect(settled == [done.id])
        #expect(workspace.session(done.id)?.state == .idle)
        // A failure shouldn't go quiet unseen, what needs you or is working isn't finished, and
        // the session in front settles on its own when it is left.
        #expect(workspace.session(failed.id)?.state == .failed)
        #expect(workspace.session(waiting.id)?.state == .needsYou)
        #expect(workspace.session(working.id)?.state == .working)
        #expect(workspace.session(current.id)?.state == .done)
    }

    @Test func `nothing done unseen means nothing to mark`() {
        var workspace = Workspace()
        let session = workspace.newSession(in: "/dev/apps/calm")
        #expect(workspace.sessionsDoneUnseen(except: nil).isEmpty)
        #expect(workspace.markDoneSeen(except: session.id).isEmpty)
    }

    // MARK: Fold all

    @Test func `every group folds and unfolds together`() {
        var workspace = Workspace()
        workspace.newSession(in: "/dev/apps/a")
        workspace.newSession(in: "/dev/apps/b")
        #expect(workspace.projects.count == 2)

        workspace.setAllCollapsed(true)
        let folded = workspace.projects.map(\.isCollapsed)
        #expect(folded == [true, true])

        workspace.setAllCollapsed(false)
        let unfolded = workspace.projects.map(\.isCollapsed)
        #expect(unfolded == [false, false])
    }
}

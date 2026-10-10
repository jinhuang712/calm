@testable import CalmModel
import Foundation
import Testing

/// FEATURES.md → F2: a project's header dragged to another place among the projects.
struct ProjectReorderTests {
    // MARK: The order

    /// Three projects with a folder group made between the first two, as the array holds them
    /// when a session opened elsewhere before the second project was made.
    private func workspace() -> (Workspace, [Project.ID]) {
        var workspace = Workspace()
        let payments = workspace.addProject(path: "/Users/me/work/payments")
        _ = workspace.newSession(in: "/tmp")
        let billing = workspace.addProject(path: "/Users/me/work/billing")
        let calm = workspace.addProject(path: "/Users/me/dev/calm")
        _ = workspace.newSession(in: "/Users/me/.scratch/a", placement: .scratch)
        return (workspace, [payments.id, billing.id, calm.id])
    }

    @Test func `a project moves to where it was let go among the projects`() {
        var (workspace, ids) = workspace()
        workspace.moveProject(ids[2], to: 0)
        #expect(workspace.madeProjects.map(\.id) == [ids[2], ids[0], ids[1]])
        workspace.moveProject(ids[2], to: 2)
        #expect(workspace.madeProjects.map(\.id) == [ids[0], ids[1], ids[2]])
        workspace.moveProject(ids[0], to: 1)
        #expect(workspace.madeProjects.map(\.id) == [ids[1], ids[0], ids[2]])
    }

    @Test func `scratch stays on top and folder groups stay below`() {
        var (workspace, ids) = workspace()
        workspace.moveProject(ids[0], to: 2)
        #expect(workspace.orderedProjects.map(\.kind) == [.scratch, .project, .project, .project, .directory])
        #expect(workspace.madeProjects.map(\.id) == [ids[1], ids[2], ids[0]])
    }

    @Test func `a place past either end is the end`() {
        var (workspace, ids) = workspace()
        workspace.moveProject(ids[0], to: 9)
        #expect(workspace.madeProjects.map(\.id) == [ids[1], ids[2], ids[0]])
        workspace.moveProject(ids[0], to: -3)
        #expect(workspace.madeProjects.map(\.id) == [ids[0], ids[1], ids[2]])
    }

    @Test func `only a project the user made moves`() throws {
        var (workspace, _) = workspace()
        let before = workspace.projects
        let folder = try #require(workspace.projects.first { $0.kind == .directory })
        let scratch = try #require(workspace.projects.first { $0.kind == .scratch })
        workspace.moveProject(folder.id, to: 0)
        workspace.moveProject(scratch.id, to: 2)
        workspace.moveProject(UUID(), to: 0)
        #expect(workspace.projects == before)
    }

    @Test func `a lone project stays where it is`() {
        var workspace = Workspace()
        _ = workspace.newSession(in: "/tmp")
        let project = workspace.addProject(path: "/Users/me/work")
        let before = workspace.projects
        workspace.moveProject(project.id, to: 0)
        #expect(workspace.projects == before)
    }

    @Test func `the order is kept across a launch`() throws {
        var (workspace, ids) = workspace()
        workspace.moveProject(ids[1], to: 0)
        let restored = try JSONDecoder().decode(Workspace.self, from: JSONEncoder().encode(workspace))
        #expect(restored.madeProjects.map(\.id) == [ids[1], ids[0], ids[2]])
    }

    // MARK: The drag

    /// A short project, a tall one (open, with cards) and a short one, 22 apart.
    private let spans: [ProjectReorder.Span] = [
        .init(top: 0, bottom: 30),
        .init(top: 52, bottom: 200),
        .init(top: 222, bottom: 252),
    ]

    private func drag(_ index: Int) throws -> ProjectReorder {
        try #require(ProjectReorder(spans: spans, index: index, spacing: 22))
    }

    @Test func `fewer than two projects have no order to change`() {
        #expect(ProjectReorder(spans: [spans[0]], index: 0, spacing: 22) == nil)
        #expect(ProjectReorder(spans: spans, index: 3, spacing: 22) == nil)
    }

    @Test func `the dragged project never leaves the projects`() throws {
        // The first can't go above its own top, nor its bottom below the last project's bottom.
        #expect(try drag(0).clamped(-40) == 0)
        #expect(try drag(0).clamped(500) == 222)
        #expect(try drag(0).clamped(80) == 80)
        #expect(try drag(2).clamped(-500) == -222)
    }

    @Test func `a project passes another once its leading edge crosses the other's middle`() throws {
        // Going down, the short first project's bottom (30) crosses the tall one's middle (126) after 96.
        #expect(try drag(0).target(for: 90) == 0)
        #expect(try drag(0).target(for: 100) == 1)
        // and the last one's middle (237) after 207.
        #expect(try drag(0).target(for: 200) == 1)
        #expect(try drag(0).target(for: 210) == 2)
        // Going up, the last project's top (222) crosses the tall one's middle after 96.
        #expect(try drag(2).target(for: -90) == 2)
        #expect(try drag(2).target(for: -100) == 1)
        #expect(try drag(2).target(for: -500) == 0)
    }

    @Test func `a tall project passes a short one without travelling its own height`() throws {
        // Its bottom (200) crosses the last project's middle (237) after 37, not after 148 + 22.
        #expect(try drag(1).target(for: 36) == 1)
        #expect(try drag(1).target(for: 38) == 2)
        // Its top (52) crosses the first one's middle (15) after 37 going up.
        #expect(try drag(1).target(for: -38) == 0)
        #expect(try drag(1).target(for: 0) == 1)
    }

    @Test func `a section growing during a drag doesn't move the dragged one off the pointer`() throws {
        // The tall project dragged 30 down, then the first one's card grows 40: its place is 40 lower.
        let before = try drag(1)
        #expect(before.travel(from: 52, moved: 30) == 30)
        let grown = try #require(ProjectReorder(
            spans: [.init(top: 0, bottom: 70), .init(top: 92, bottom: 240), .init(top: 262, bottom: 292)], index: 1, spacing: 22,
        ))
        let travel = grown.travel(from: 52, moved: 30)
        #expect(travel == -10)
        #expect(grown.spans[1].top + grown.clamped(travel) == 52 + 30) // still where the pointer took it
    }

    @Test func `the projects passed step over and leave a hole the dragged one's size where it lands`() throws {
        // The first one dragged to the end: the other two move up by its height and a gap.
        let down = try drag(0)
        #expect((0 ..< 3).map { down.shift(of: $0, toward: 2) } == [0, -52, -52])
        // The last one now ends at 200, so the hole runs from 222 to 252: the first one's 30.
        #expect(spans[2].bottom + down.shift(of: 2, toward: 2) + 22 == 222)

        // The last one dragged to the top: the other two move down.
        let up = try drag(2)
        #expect((0 ..< 3).map { up.shift(of: $0, toward: 0) } == [52, 52, 0])
        // Over the tall one only: the first stays.
        #expect((0 ..< 3).map { up.shift(of: $0, toward: 1) } == [0, 52, 0])
        // Back over its own place: nothing moves.
        #expect((0 ..< 3).map { up.shift(of: $0, toward: 2) } == [0, 0, 0])
    }
}

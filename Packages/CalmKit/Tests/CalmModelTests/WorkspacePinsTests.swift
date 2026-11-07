@testable import CalmModel
import Foundation
import Testing

@Suite("Pinned sessions")
struct WorkspacePinsTests {
    /// Project `calm` holding two sessions and a folder group holding one, the first on screen.
    private func fixture() -> (Workspace, calm: Project, one: Session, two: Session, folder: Session) { // swiftlint:disable:this large_tuple
        var workspace = Workspace()
        let calm = workspace.addProject(path: "/code/calm")
        let group = Project(path: "/code/other", kind: .directory)
        workspace.projects.append(group)
        let one = Session(projectID: calm.id, workingDirectory: "/code/calm", createdAt: Date(timeIntervalSince1970: 1))
        let two = Session(projectID: calm.id, workingDirectory: "/code/calm", createdAt: Date(timeIntervalSince1970: 2))
        let folder = Session(projectID: group.id, workingDirectory: "/code/other", createdAt: Date(timeIntervalSince1970: 3))
        workspace.sessions = [one, two, folder]
        let layout = PaneLayout(tree: .leaf(one.id), focusedSessionID: one.id)
        workspace.layouts = [layout]
        workspace.selectedLayoutID = layout.id
        return (workspace, calm, one, two, folder)
    }

    @Test("a pin moves the session to the front and leaves its project alone")
    func pinOrder() {
        var (workspace, calm, one, two, folder) = fixture()
        workspace.setPin(folder.id, true, at: Date(timeIntervalSince1970: 10))
        workspace.setPin(two.id, true, at: Date(timeIntervalSince1970: 20))

        #expect(workspace.pinnedSessions.map(\.id) == [folder.id, two.id])
        #expect(workspace.sidebarSessions.map(\.id) == [folder.id, two.id, one.id])
        #expect(workspace.unpinnedSessions(in: calm.id).map(\.id) == [one.id])
        #expect(workspace.session(two.id)?.projectID == calm.id)
    }

    @Test("an unpinned session goes back to its place in the group")
    func unpinOrder() {
        var (workspace, calm, one, two, _) = fixture()
        workspace.setPin(one.id, true)
        workspace.setPin(one.id, false)

        #expect(workspace.pinnedSessions.isEmpty)
        #expect(workspace.unpinnedSessions(in: calm.id).map(\.id) == [one.id, two.id])
    }

    @Test("pinning twice keeps the first place")
    func pinTwice() {
        var (workspace, _, _, two, folder) = fixture()
        workspace.setPin(two.id, true, at: Date(timeIntervalSince1970: 10))
        workspace.setPin(folder.id, true, at: Date(timeIntervalSince1970: 20))
        workspace.setPin(two.id, true, at: Date(timeIntervalSince1970: 30))

        #expect(workspace.pinnedSessions.map(\.id) == [two.id, folder.id])
    }

    @Test("a folder group with every session pinned is not drawn, a project is")
    func emptiedGroups() {
        var (workspace, calm, one, two, folder) = fixture()
        workspace.setPin(folder.id, true)
        workspace.setPin(one.id, true)
        workspace.setPin(two.id, true)

        #expect(workspace.sidebarProjects.map(\.id) == [calm.id])
        // Still there: it comes back with the session.
        #expect(workspace.projects.count == 2)
    }

    @Test("unpinning into a folded group opens it only for a session on screen")
    func unpinIntoFold() {
        var (workspace, calm, one, two, _) = fixture()
        workspace.setPin(one.id, true)
        workspace.setPin(two.id, true)
        workspace.setCollapsed(calm.id, true)

        workspace.setPin(two.id, false)
        #expect(workspace.project(calm.id)?.isCollapsed == true)

        workspace.setPin(one.id, false)
        #expect(workspace.project(calm.id)?.isCollapsed == false)
    }

    @Test("pinning the session on screen opens a folded Pinned")
    func pinIntoFold() {
        var (workspace, _, one, two, _) = fixture()
        workspace.setPin(two.id, true)
        workspace.setAllCollapsed(true)
        #expect(workspace.pinnedIsCollapsed == true)

        workspace.setPin(one.id, true)
        #expect(workspace.pinnedIsCollapsed == nil)
    }

    @Test("a pinned session is in a folded group when Pinned is folded, not when its project is")
    func collapsedGroup() {
        var (workspace, calm, one, _, _) = fixture()
        workspace.setPin(one.id, true)
        workspace.setCollapsed(calm.id, true)
        #expect(!workspace.isInCollapsedGroup(one.id))

        workspace.pinnedIsCollapsed = true
        #expect(workspace.isInCollapsedGroup(one.id))

        workspace.reveal(one.id)
        #expect(workspace.pinnedIsCollapsed == nil)
        #expect(workspace.project(calm.id)?.isCollapsed == true)
    }

    @Test("a closed session takes its pin with it")
    func closing() {
        var (workspace, _, _, two, _) = fixture()
        workspace.setPin(two.id, true)

        workspace.sessions.removeAll { $0.id == two.id }
        #expect(workspace.pinnedSessions.isEmpty)
    }

    @Test("the pin is saved, and state files without one still load")
    func coding() throws {
        var (workspace, _, _, two, _) = fixture()
        workspace.setPin(two.id, true, at: Date(timeIntervalSince1970: 10))
        workspace.pinnedIsCollapsed = true

        let data = try JSONEncoder().encode(workspace)
        let loaded = try JSONDecoder().decode(Workspace.self, from: data)
        #expect(loaded.session(two.id)?.pinnedAt == Date(timeIntervalSince1970: 10))
        #expect(loaded.pinnedIsCollapsed == true)

        let plain = try JSONDecoder().decode(Workspace.self, from: JSONEncoder().encode(Workspace()))
        #expect(plain.pinnedSessions.isEmpty)
        #expect(plain.pinnedIsCollapsed == nil)
    }
}

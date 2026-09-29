@testable import CalmModel
import Foundation
import Testing

struct WorkspaceTests {
    /// A fake git lookup: these folders (and anything below) belong to the listed repo roots.
    func gitRoot(_ directory: String) -> String? {
        for root in ["/dev/apps/pinax", "/dev/personal/vibe-billing", "/dev/apps/calm"] where directory.hasPrefix(root) {
            return root
        }
        return nil
    }

    @Test func `a new session files itself under its git repository`() {
        var workspace = Workspace()
        let session = workspace.newSession(in: "/dev/apps/pinax/src", gitRoot: gitRoot)
        let project = workspace.project(session.projectID)
        #expect(project?.path == "/dev/apps/pinax")
        #expect(project?.name == "pinax")
        #expect(project?.isAutomatic == true)
    }

    @Test func `without a repository the folder itself becomes the project`() {
        var workspace = Workspace()
        let session = workspace.newSession(in: "/tmp/scratch", gitRoot: gitRoot)
        #expect(workspace.project(session.projectID)?.path == "/tmp/scratch")
    }

    @Test func `the most specific project wins`() {
        var workspace = Workspace()
        workspace.addProject(path: "/dev")
        let inner = workspace.addProject(path: "/dev/apps/calm")
        let session = workspace.newSession(in: "/dev/apps/calm/Calm/Terminal", gitRoot: gitRoot)
        #expect(session.projectID == inner.id)
    }

    @Test func `changing folder moves the session and removes the empty automatic project`() throws {
        var workspace = Workspace()
        let session = workspace.newSession(in: "/dev/apps/pinax", gitRoot: gitRoot)
        let moved = workspace.updateWorkingDirectory(session.id, to: "/dev/personal/vibe-billing/src", gitRoot: gitRoot)
        #expect(moved)
        #expect(try workspace.project(#require(workspace.session(session.id)?.projectID))?.name == "vibe-billing")
        #expect(!workspace.projects.contains { $0.name == "pinax" })
    }

    @Test func `a repository inside an automatic project gets its own project`() throws {
        var workspace = Workspace()
        let session = workspace.newSession(in: "/home/me", gitRoot: gitRoot)
        _ = workspace.newSession(in: "/home/me", gitRoot: gitRoot) // keeps the home project alive
        let moved = workspace.updateWorkingDirectory(session.id, to: "/home/me/dev/apps/pinax/src", gitRoot: { dir in
            dir.hasPrefix("/home/me/dev/apps/pinax") ? "/home/me/dev/apps/pinax" : nil
        })
        #expect(moved)
        #expect(try workspace.project(#require(workspace.session(session.id)?.projectID))?.name == "pinax")
        #expect(workspace.projects.map(\.name).sorted() == ["me", "pinax"])
    }

    @Test func `a user project keeps repositories inside it`() {
        var workspace = Workspace()
        let dev = workspace.addProject(path: "/dev")
        let session = workspace.newSession(in: "/dev/apps/pinax/src", gitRoot: gitRoot)
        #expect(session.projectID == dev.id)
    }

    @Test func `staying inside the project doesn't move the session`() {
        var workspace = Workspace()
        let session = workspace.newSession(in: "/dev/apps/pinax", gitRoot: gitRoot)
        let moved = workspace.updateWorkingDirectory(session.id, to: "/dev/apps/pinax/docs", gitRoot: gitRoot)
        #expect(!moved)
    }

    @Test func `pinned sessions stay put`() throws {
        var workspace = Workspace()
        let session = workspace.newSession(in: "/dev/apps/pinax", gitRoot: gitRoot)
        workspace.setPinned(session.id, true)
        let moved = workspace.updateWorkingDirectory(session.id, to: "/dev/apps/calm", gitRoot: gitRoot)
        #expect(!moved)
        #expect(try workspace.project(#require(workspace.session(session.id)?.projectID))?.name == "pinax")
    }

    @Test func `user projects are kept when empty`() {
        var workspace = Workspace()
        workspace.addProject(path: "/dev/apps/pinax")
        let session = workspace.newSession(in: "/dev/apps/pinax", gitRoot: gitRoot)
        workspace.removeSession(session.id)
        #expect(workspace.projects.map(\.name) == ["pinax"])
    }

    @Test func `adding a project refiles sessions already inside it`() {
        var workspace = Workspace()
        let session = workspace.newSession(in: "/work/client/api", gitRoot: gitRoot)
        #expect(workspace.project(session.projectID)?.path == "/work/client/api")
        let client = workspace.addProject(path: "/work/client")
        #expect(workspace.session(session.id)?.projectID == client.id)
        #expect(workspace.projects.count == 1)
    }

    @Test func `splitting adds a session to the same layout and focuses it`() throws {
        var workspace = Workspace()
        let first = workspace.newSession(in: "/dev/apps/calm", gitRoot: gitRoot)
        let split = workspace.splitSession(first.id, direction: .right, in: "/dev/apps/calm", gitRoot: gitRoot)
        let second = try #require(split)
        #expect(workspace.layouts.count == 1)
        #expect(workspace.layouts[0].tree.leaves == [first.id, second.id])
        #expect(workspace.layouts[0].focusedSessionID == second.id)
    }

    @Test func `removing the last session of a layout removes the layout`() {
        var workspace = Workspace()
        let first = workspace.newSession(in: "/dev/apps/calm", gitRoot: gitRoot)
        let other = workspace.newSession(in: "/dev/apps/pinax", gitRoot: gitRoot)
        workspace.removeSession(other.id)
        #expect(workspace.layouts.map(\.tree) == [.leaf(first.id)])
    }

    @Test func `closing the session on screen selects none, and choosing one selects it`() {
        var workspace = Workspace()
        let first = workspace.newSession(in: "/dev/apps/calm", gitRoot: gitRoot)
        let second = workspace.newSession(in: "/dev/apps/calm", gitRoot: gitRoot)
        workspace.newSession(in: "/dev/apps/calm", gitRoot: gitRoot)
        workspace.select(second.id)
        workspace.removeSession(second.id)
        #expect(workspace.selectedLayout == nil)
        #expect(workspace.layouts.count == 2)

        workspace.select(first.id)
        #expect(workspace.selectedLayout?.focusedSessionID == first.id)
    }

    @Test func `closing a session that isn't on screen leaves the selection alone`() {
        var workspace = Workspace()
        let first = workspace.newSession(in: "/dev/apps/calm", gitRoot: gitRoot)
        let second = workspace.newSession(in: "/dev/apps/calm", gitRoot: gitRoot)
        workspace.removeSession(first.id)
        #expect(workspace.selectedLayout?.focusedSessionID == second.id)
    }

    @Test func `closing a split's pane keeps its layout on screen`() throws {
        var workspace = Workspace()
        let first = workspace.newSession(in: "/dev/apps/calm", gitRoot: gitRoot)
        let split = workspace.splitSession(first.id, direction: .right, in: "/dev/apps/calm", gitRoot: gitRoot)
        let second = try #require(split)
        workspace.removeSession(second.id)
        #expect(workspace.selectedLayout?.focusedSessionID == first.id)
    }

    @Test func `closing the session on screen settles nobody`() {
        var workspace = Workspace()
        let first = workspace.newSession(in: "/dev/apps/calm", gitRoot: gitRoot)
        let second = workspace.newSession(in: "/dev/apps/calm", gitRoot: gitRoot)
        workspace.setState(first.id, .done)
        workspace.removeSession(second.id)
        #expect(workspace.session(first.id)?.state == .done) // nobody looked at it
    }

    @Test func `selecting a session shows its layout and settles the one left behind`() {
        var workspace = Workspace()
        let first = workspace.newSession(in: "/dev/apps/calm", gitRoot: gitRoot)
        let second = workspace.newSession(in: "/dev/apps/pinax", gitRoot: gitRoot)
        workspace.setState(first.id, .done)
        workspace.select(first.id)
        #expect(workspace.selectedLayout?.tree.contains(first.id) == true)
        #expect(workspace.session(first.id)?.state == .done)
        workspace.select(first.id)
        #expect(workspace.session(first.id)?.state == .done)
        workspace.select(second.id)
        #expect(workspace.session(first.id)?.state == .idle)
    }

    @Test func `a new session or split settles the session left behind`() {
        var workspace = Workspace()
        let first = workspace.newSession(in: "/dev/apps/calm", gitRoot: gitRoot)
        workspace.setState(first.id, .done)
        let second = workspace.newSession(in: "/dev/apps/calm", gitRoot: gitRoot)
        #expect(workspace.session(first.id)?.state == .idle)
        workspace.setState(second.id, .failed)
        workspace.splitSession(second.id, direction: .right, in: "/dev/apps/calm", gitRoot: gitRoot)
        #expect(workspace.session(second.id)?.state == .idle)
    }

    @Test func `sessions keep creation order in the sidebar`() {
        var workspace = Workspace()
        workspace.addProject(path: "/dev/apps/calm")
        let first = workspace.newSession(in: "/dev/apps/calm")
        let second = workspace.newSession(in: "/dev/apps/calm")
        let project = workspace.projects[0].id
        #expect(workspace.sessions(in: project).map(\.id) == [first.id, second.id])
    }

    @Test func `the workspace round-trips through JSON`() throws {
        var workspace = Workspace()
        let first = workspace.newSession(in: "/dev/apps/calm", gitRoot: gitRoot)
        workspace.splitSession(first.id, direction: .down, in: "/dev/apps/calm", gitRoot: gitRoot)
        let data = try JSONEncoder().encode(workspace)
        let decoded = try JSONDecoder().decode(Workspace.self, from: data)
        #expect(decoded == workspace)
    }

    @Test(arguments: [
        ("~/dev/", "~/dev"),
        ("/a/b/../c", "/a/c"),
        ("/", "/"),
    ])
    func `paths are standardized`(input: String, expected: String) {
        #expect(WorkspacePath.standardize(input) == WorkspacePath.standardize(expected))
    }

    @Test func `a sibling folder with a shared prefix is not inside`() {
        #expect(!WorkspacePath.isInside("/dev/apps/calmer", folder: "/dev/apps/calm"))
        #expect(WorkspacePath.isInside("/dev/apps/calm/x", folder: "/dev/apps/calm"))
    }
}

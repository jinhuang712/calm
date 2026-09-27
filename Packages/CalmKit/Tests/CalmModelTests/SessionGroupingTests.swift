@testable import CalmModel
import Foundation
import Testing

/// FEATURES.md → F2: projects the user made keep their sessions, scratch sessions sit on top,
/// everything else groups by repository or folder.
struct SessionGroupingTests {
    let repositories = ["/Users/me/dev/calm"]

    func gitRoot(_ folder: String) -> String? {
        repositories.first { folder == $0 || folder.hasPrefix($0 + "/") }
    }

    func group(_ workspace: Workspace, _ session: Session) -> Project? {
        workspace.session(session.id).flatMap { workspace.project($0.projectID) }
    }

    @Test func `a directory group holds only its own folder, so the home folder doesn't swallow the rest`() {
        var workspace = Workspace()
        let home = workspace.newSession(in: "/Users/me", gitRoot: gitRoot)
        let dev = workspace.newSession(in: "/Users/me/dev", gitRoot: gitRoot)
        let projects = workspace.newSession(in: "/Users/me/dev/projects", gitRoot: gitRoot)
        #expect(group(workspace, home)?.path == "/Users/me")
        #expect(group(workspace, dev)?.path == "/Users/me/dev")
        #expect(group(workspace, projects)?.path == "/Users/me/dev/projects")
        #expect(workspace.projects.allSatisfy { $0.kind == .directory })
    }

    @Test func `inside a repository, the group is the repository's root`() {
        var workspace = Workspace()
        let top = workspace.newSession(in: "/Users/me/dev/calm", gitRoot: gitRoot)
        let deep = workspace.newSession(in: "/Users/me/dev/calm/Packages/CalmKit", gitRoot: gitRoot)
        #expect(group(workspace, top)?.id == group(workspace, deep)?.id)
        #expect(group(workspace, deep)?.name == "calm")
    }

    @Test func `a session started in a project stays there when its shell leaves`() {
        var workspace = Workspace()
        let project = workspace.addProject(path: "/Users/me/work/payments")
        let session = workspace.newSession(in: "/Users/me/work/payments", placement: .project(project.id), gitRoot: gitRoot)
        #expect(workspace.session(session.id)?.isPinned == true)
        workspace.updateWorkingDirectory(session.id, to: "/tmp", gitRoot: gitRoot)
        #expect(group(workspace, session)?.id == project.id)

        // Let It Follow Its Folder: it groups by folder again.
        workspace.followFolder(session.id, gitRoot: gitRoot)
        #expect(group(workspace, session)?.path == "/tmp")
        #expect(workspace.project(project.id) != nil) // a project the user made stays when empty
    }

    @Test func `a folder inside a project the user made joins it without sticking`() {
        var workspace = Workspace()
        let project = workspace.addProject(path: "/Users/me/work")
        let session = workspace.newSession(in: "/Users/me/work/api", gitRoot: gitRoot)
        #expect(group(workspace, session)?.id == project.id)
        #expect(workspace.session(session.id)?.isPinned == false)
        workspace.updateWorkingDirectory(session.id, to: "/Users/me", gitRoot: gitRoot)
        #expect(group(workspace, session)?.path == "/Users/me")
    }

    @Test func `scratch sessions sit on top, in their own hidden folders, and never move`() throws {
        var workspace = Workspace()
        _ = workspace.addProject(path: "/Users/me/work")
        _ = workspace.newSession(in: "/Users/me/dev", gitRoot: gitRoot)
        let folder = "/Users/me/Library/Application Support/Calm/Scratch/0928-1432"
        let scratch = workspace.newSession(in: folder, placement: .scratch, gitRoot: gitRoot)
        let session = try #require(workspace.session(scratch.id))
        #expect(session.isScratch && session.isPinned)
        #expect(session.scratchFolder == folder)
        #expect(group(workspace, scratch)?.kind == .scratch)
        #expect(group(workspace, scratch)?.name == "Scratch")
        #expect(workspace.orderedProjects.map(\.kind) == [.scratch, .project, .directory])

        // The shell's title (often its folder) never shows; a name or an agent's title does.
        workspace.setTitle(scratch.id, folder)
        #expect(workspace.session(scratch.id)?.displayTitle.hasPrefix("Scratch · ") == true)
        #expect(workspace.session(scratch.id)?.title(agentTitle: "Try the new API") == "Try the new API")

        workspace.updateWorkingDirectory(scratch.id, to: "/Users/me/dev", gitRoot: gitRoot)
        #expect(group(workspace, scratch)?.kind == .scratch)
        workspace.followFolder(scratch.id, gitRoot: gitRoot) // not for scratch sessions
        #expect(group(workspace, scratch)?.kind == .scratch)

        workspace.removeSession(scratch.id)
        #expect(!workspace.projects.contains { $0.kind == .scratch }) // the group goes with its last session
    }

    @Test func `new sessions inherit a project, never scratch`() {
        var workspace = Workspace()
        let project = workspace.addProject(path: "/Users/me/work")
        let inProject = workspace.newSession(in: "/Users/me/work", placement: .project(project.id))
        let scratch = workspace.newSession(in: "/Users/me/Scratch/a", placement: .scratch)
        let loose = workspace.newSession(in: "/Users/me/dev")
        #expect(workspace.inheritedPlacement(from: inProject.id) == .project(project.id))
        #expect(workspace.inheritedPlacement(from: scratch.id) == .directory)
        #expect(workspace.inheritedPlacement(from: loose.id) == .directory)
        #expect(workspace.inheritedPlacement(from: nil) == .directory)
    }

    @Test func `making a project, moving into one, keeping a scratch session`() throws {
        var workspace = Workspace()
        let session = workspace.newSession(in: "/Users/me/dev/projects", gitRoot: gitRoot)
        let groupID = try #require(workspace.session(session.id)?.projectID)
        workspace.makeProject(groupID)
        #expect(workspace.project(groupID)?.kind == .project)
        #expect(workspace.session(session.id)?.isPinned == true)

        let other = workspace.addProject(path: "/Users/me/work")
        let loose = workspace.newSession(in: "/tmp", gitRoot: gitRoot)
        workspace.move(loose.id, to: other.id)
        #expect(group(workspace, loose)?.id == other.id)
        #expect(!workspace.projects.contains { $0.path == "/tmp" }) // its empty group went away

        let scratch = workspace.newSession(in: "/Users/me/Scratch/b", placement: .scratch)
        workspace.keepScratchAsProject(scratch.id, at: "/Users/me/work/prototype", gitRoot: gitRoot)
        let kept = try #require(workspace.session(scratch.id))
        #expect(!kept.isScratch && kept.isPinned)
        #expect(workspace.project(kept.projectID)?.path == "/Users/me/work/prototype")
        #expect(workspace.project(kept.projectID)?.kind == .project)
    }

    @Test func `at launch, sessions filed under the old rules move to their own groups`() throws {
        // As saved by the old rules: everything under an automatic home project.
        let oldState = """
        {"projects":[{"id":"00000000-0000-0000-0000-000000000001","path":"/Users/me","name":"~","isAutomatic":true,"isCollapsed":false},
        {"id":"00000000-0000-0000-0000-000000000002","path":"/Users/me/work","name":"work","isAutomatic":false,"isCollapsed":false}],
        "sessions":[
        {"id":"00000000-0000-0000-0000-00000000000a","projectID":"00000000-0000-0000-0000-000000000001",
         "title":"","workingDirectory":"/Users/me/dev","isPinned":false,"state":"idle","createdAt":0},
        {"id":"00000000-0000-0000-0000-00000000000b","projectID":"00000000-0000-0000-0000-000000000001",
         "title":"","workingDirectory":"/Users/me/dev/projects","isPinned":false,"state":"idle","createdAt":0}],
        "layouts":[]}
        """
        var workspace = try JSONDecoder().decode(Workspace.self, from: Data(oldState.utf8))
        #expect(workspace.projects.map(\.kind) == [.directory, .project])
        workspace.refileAll(gitRoot: gitRoot)
        #expect(workspace.projects.map(\.path).sorted() == ["/Users/me/dev", "/Users/me/dev/projects", "/Users/me/work"])

        // And it saves both ways: `kind`, plus `isAutomatic` for older builds.
        let saved = try JSONSerialization.jsonObject(with: JSONEncoder().encode(workspace)) as? [String: Any]
        let first = try #require((saved?["projects"] as? [[String: Any]])?.first)
        #expect(first["kind"] is String && first["isAutomatic"] is Bool)
    }
}

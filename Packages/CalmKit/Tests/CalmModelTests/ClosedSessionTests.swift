@testable import CalmModel
import Foundation
import Testing

/// FEATURES.md → F12: ⌘⇧T opens the session closed last again.
struct ClosedSessionTests {
    private func gitRoot(_ directory: String) -> String? {
        directory.hasPrefix("/dev/apps/pinax") ? "/dev/apps/pinax" : nil
    }

    /// What Calm keeps of `id` as it stands.
    private func record(_ id: Session.ID, in workspace: Workspace) throws -> ClosedSession {
        let session = try #require(workspace.session(id))
        return try #require(ClosedSession(session, in: workspace))
    }

    private func closing(_ id: Session.ID, in workspace: inout Workspace) throws -> ClosedSession {
        let closed = try record(id, in: workspace)
        workspace.removeSession(id)
        return closed
    }

    @Test func `a reopened session comes back to its folder under its name`() throws {
        var workspace = Workspace()
        let session = workspace.newSession(in: "/dev/apps/pinax/src", gitRoot: gitRoot)
        workspace.rename(session.id, to: "Payments")
        let closed = try closing(session.id, in: &workspace)
        #expect(workspace.sessions.isEmpty)

        let reopened = workspace.reopen(closed, in: closed.workingDirectory, gitRoot: gitRoot)
        #expect(reopened.id != session.id) // a new shell, so a new session
        #expect(reopened.workingDirectory == "/dev/apps/pinax/src")
        #expect(reopened.customName == "Payments")
        #expect(workspace.project(reopened.projectID)?.path == "/dev/apps/pinax")
        #expect(workspace.selectedLayout?.focusedSessionID == reopened.id)
        #expect(workspace.session(reopened.id) == reopened)
    }

    @Test func `it takes its old place among the sessions of its group`() throws {
        var workspace = Workspace()
        let first = workspace.newSession(in: "/dev/apps/pinax", gitRoot: gitRoot)
        let second = workspace.newSession(in: "/dev/apps/pinax", gitRoot: gitRoot)
        workspace.sessions[0].createdAt = Date(timeIntervalSince1970: 1000)
        workspace.sessions[1].createdAt = Date(timeIntervalSince1970: 2000)
        let closed = try closing(first.id, in: &workspace)

        let reopened = workspace.reopen(closed, in: closed.workingDirectory, gitRoot: gitRoot)
        #expect(workspace.sessions(in: reopened.projectID).map(\.id) == [reopened.id, second.id])
    }

    @Test func `a session that stayed in a project goes back to it`() throws {
        var workspace = Workspace()
        let project = workspace.addProject(path: "/dev/apps/pinax", gitRoot: gitRoot)
        let session = workspace.newSession(in: "/dev/apps/pinax", placement: .project(project.id), gitRoot: gitRoot)
        workspace.updateWorkingDirectory(session.id, to: "/tmp/elsewhere", gitRoot: gitRoot) // pinned: stays
        let closed = try closing(session.id, in: &workspace)
        #expect(closed.projectID == project.id)

        let reopened = workspace.reopen(closed, in: "/tmp/elsewhere", gitRoot: gitRoot)
        #expect(reopened.projectID == project.id)
        #expect(reopened.isPinned)
    }

    @Test func `a project removed meanwhile leaves the session to group by its folder`() throws {
        var workspace = Workspace()
        let project = workspace.addProject(path: "/dev/apps/pinax", gitRoot: gitRoot)
        let session = workspace.newSession(in: "/dev/apps/pinax/src", placement: .project(project.id), gitRoot: gitRoot)
        let closed = try closing(session.id, in: &workspace)
        workspace.removeProject(project.id, gitRoot: gitRoot)

        let reopened = workspace.reopen(closed, in: closed.workingDirectory, gitRoot: gitRoot)
        #expect(reopened.isPinned == false)
        #expect(workspace.project(reopened.projectID)?.path == "/dev/apps/pinax")
    }

    @Test func `a session that followed its folder is not tied to a project it happened to be in`() throws {
        var workspace = Workspace()
        workspace.addProject(path: "/dev/apps/pinax", gitRoot: gitRoot)
        let session = workspace.newSession(in: "/dev/apps/pinax/src", gitRoot: gitRoot)
        #expect(workspace.session(session.id)?.isPinned == false)
        #expect(try closing(session.id, in: &workspace).projectID == nil)
    }

    @Test func `scratch sessions are not kept: their folder goes with them`() {
        var workspace = Workspace()
        let session = workspace.newSession(in: "/tmp/scratch/one", placement: .scratch)
        #expect(ClosedSession(session, in: workspace) == nil)
    }

    @Test func `only an agent that was running comes back to its conversation`() throws {
        var workspace = Workspace()
        let session = workspace.newSession(in: "/dev/apps/pinax", gitRoot: gitRoot)
        var run = AgentRun(kind: .claudeCode, processID: 42)
        run.agentSessionID = "abc"
        run.transcriptPath = "/tmp/abc.jsonl"
        workspace.startAgentRun(session.id, run)
        let running = try record(session.id, in: workspace)
        #expect(running.conversation?.agentSessionID == "abc")
        #expect(running.conversation?.kind == .claudeCode)

        // Once it has exited, the conversation is a memory of the session, not part of what was open.
        workspace.endAgentRun(session.id)
        #expect(workspace.session(session.id)?.lastConversation?.agentSessionID == "abc")
        let ended = try record(session.id, in: workspace)
        #expect(ended.conversation == nil)
    }

    @Test func `an agent nothing is known about yet leaves a plain shell`() throws {
        var workspace = Workspace()
        let session = workspace.newSession(in: "/dev/apps/pinax", gitRoot: gitRoot)
        workspace.startAgentRun(session.id, AgentRun(kind: .codex, processID: 7))
        #expect(try record(session.id, in: workspace).conversation == nil)
    }

    @Test func `the newest closed session comes back first, and only the last few are kept`() throws {
        var workspace = Workspace()
        var closed = ClosedSessions()
        #expect(closed.isEmpty)
        #expect(closed.pop() == nil)

        for index in 0 ..< ClosedSessions.limit + 3 {
            let session = workspace.newSession(in: "/tmp/folder-\(index)")
            let record = try #require(ClosedSession(session, in: workspace))
            closed.push(record)
        }
        var folders: [String] = []
        while let next = closed.pop() {
            folders.append(next.workingDirectory)
        }
        #expect(folders.count == ClosedSessions.limit)
        #expect(folders.first == "/tmp/folder-\(ClosedSessions.limit + 2)")
        #expect(folders.last == "/tmp/folder-3")
        #expect(closed.isEmpty)
    }
}

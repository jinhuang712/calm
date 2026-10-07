@testable import Calm
import CalmModel
import Foundation
import Observation
import os
import Testing

/// Agents' hooks mostly repeat themselves, and every write to the manager's `workspace` has the
/// whole sidebar render again; a repeat must leave it alone.
@MainActor
struct SessionManagerReportTests {
    /// A manager over a saved workspace with one Claude Code session, working.
    private func manager() throws -> (manager: SessionManager, id: Session.ID) {
        var workspace = Workspace()
        let id = workspace.newSession(in: "/tmp/a", gitRoot: { _ in nil }).id
        workspace.startAgentRun(id, AgentRun(kind: .claudeCode, processID: 4242))
        workspace.noteAgentSession(id, kind: .claudeCode, agentSessionID: "s1", transcriptPath: "/tmp/a/s1.jsonl")
        workspace.report(id, StatusReport(state: .working, source: .hook), focusedSessionID: nil)
        let file = FileManager.default.temporaryDirectory.appending(path: "calm-reports-\(UUID().uuidString).json")
        let store = WorkspaceStore(fileURL: file)
        try store.save(workspace)
        return (SessionManager(store: store), id)
    }

    /// Whether `body` writes the manager's workspace, which everything that reads it observes.
    private func writesWorkspace(_ manager: SessionManager, _ body: () -> Void) -> Bool {
        // `onChange` is `@Sendable`; it runs at once, on the writing thread.
        let written = OSAllocatedUnfairLock(initialState: false)
        withObservationTracking {
            _ = manager.workspace
        } onChange: {
            written.withLock { $0 = true }
        }
        body()
        return written.withLock { $0 }
    }

    @Test func `a hook repeating what the session shows leaves the workspace alone`() throws {
        let (manager, id) = try manager()
        // What each tool call's PreToolUse and PostToolUse send.
        let written = writesWorkspace(manager) {
            manager.noteAgentSession(id, kind: .claudeCode, agentSessionID: "s1", transcriptPath: "/tmp/a/s1.jsonl")
            manager.report(id, StatusReport(state: .working, source: .hook))
        }
        #expect(!written)
        #expect(manager.workspace.session(id)?.state == .working)
    }

    @Test func `a hook that changes something still updates it`() throws {
        let (manager, id) = try manager()
        let finished = writesWorkspace(manager) {
            manager.report(id, StatusReport(state: .done, message: "All set.", source: .hook))
        }
        #expect(finished)
        #expect(manager.workspace.session(id)?.state == .done)
        // A new transcript (a resumed or cleared conversation) is news too.
        let renamed = writesWorkspace(manager) {
            manager.noteAgentSession(id, kind: .claudeCode, agentSessionID: "s2", transcriptPath: "/tmp/a/s2.jsonl")
        }
        #expect(renamed)
        #expect(manager.workspace.session(id)?.agent?.transcriptPath == "/tmp/a/s2.jsonl")
    }
}

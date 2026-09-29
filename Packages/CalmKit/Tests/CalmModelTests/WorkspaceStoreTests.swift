@testable import CalmModel
import Foundation
import Testing

struct WorkspaceStoreTests {
    let directory: URL

    init() throws {
        directory = FileManager.default.temporaryDirectory.appending(path: "calm-store-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    var store: WorkspaceStore {
        WorkspaceStore(fileURL: directory.appending(path: "state.json"))
    }

    @Test func `a missing file gives an empty workspace`() {
        #expect(store.load() == Workspace())
    }

    @Test func `saved state loads back unchanged`() throws {
        var workspace = Workspace()
        let first = workspace.newSession(in: "/dev/apps/calm")
        workspace.splitSession(first.id, direction: .right, in: "/dev/apps/calm")
        workspace.setTitle(first.id, "design docs")
        try store.save(workspace)
        #expect(store.load() == workspace)
    }

    @Test func `saving what the file already says leaves the file alone`() throws {
        var workspace = Workspace()
        let session = workspace.newSession(in: "/dev/apps/calm")
        #expect(try store.save(workspace))
        let file = directory.appending(path: "state.json")
        let written = try FileManager.default.attributesOfItem(atPath: file.path)[.systemFileNumber] as? Int
        #expect(try !store.save(workspace))
        // An atomic write replaces the file, so an untouched one keeps its file number.
        #expect(try FileManager.default.attributesOfItem(atPath: file.path)[.systemFileNumber] as? Int == written)
        workspace.setTitle(session.id, "design docs")
        #expect(try store.save(workspace))
        #expect(store.load() == workspace)
    }

    @Test func `a project's clicked-for mark survives a relaunch`() throws {
        var workspace = Workspace()
        let session = workspace.newSession(in: "/dev/apps/calm")
        workspace.setMarkSeed(session.projectID, 7)
        try store.save(workspace)
        #expect(store.load().project(session.projectID)?.markSeed == 7)
    }

    @Test func `a session that ran an agent Calm no longer knows still loads`() throws {
        // omp support was removed (2026-09-29). A state file saved while one was running, or that
        // remembers one to resume, must not cost the user every project and session.
        var workspace = Workspace()
        let ended = workspace.newSession(in: "/dev/apps/calm")
        let running = workspace.newSession(in: "/dev/apps/other")
        workspace.setTitle(running.id, "still here")
        workspace.startAgentRun(ended.id, AgentRun(kind: .claudeCode, processID: 41))
        workspace.noteAgentSession(ended.id, kind: .claudeCode, agentSessionID: "abc", transcriptPath: "/x/abc.jsonl")
        workspace.endAgentRun(ended.id)
        workspace.startAgentRun(running.id, AgentRun(kind: .claudeCode, processID: 42))
        try store.save(workspace)
        let saved = try #require(workspace.session(ended.id))
        #expect(saved.lastConversation?.kind == .claudeCode)
        #expect(try #require(workspace.session(running.id)).agent?.kind == .claudeCode)

        // The same file, as if the agent had been omp.
        let text = try String(contentsOf: store.fileURL, encoding: .utf8)
        try Data(text.replacingOccurrences(of: #""claudeCode""#, with: #""omp""#).utf8).write(to: store.fileURL)

        let loaded = store.load()
        #expect(loaded.sessions.count == 2)
        #expect(loaded.session(running.id)?.title == "still here")
        // Nothing is known of an agent that isn't supported, so it reads as no agent.
        #expect(loaded.sessions.allSatisfy { $0.agent == nil && $0.lastConversation == nil })
        let files = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        #expect(files.contains("state.json"))
        #expect(!files.contains { $0.hasPrefix("state.unreadable-") })
    }

    @Test func `a corrupt file is kept aside, not overwritten`() throws {
        try Data("{ not json".utf8).write(to: store.fileURL)
        #expect(store.load() == Workspace())
        let files = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        #expect(files.contains { $0.hasPrefix("state.unreadable-") })
        #expect(!files.contains("state.json"))
    }

    @Test func `a file from a newer version is kept aside`() throws {
        try Data(#"{"version": 99, "workspace": {"projects": [], "sessions": [], "layouts": []}}"#.utf8).write(to: store.fileURL)
        #expect(store.load() == Workspace())
        let files = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        #expect(files.contains { $0.hasPrefix("state.unreadable-") })
    }
}

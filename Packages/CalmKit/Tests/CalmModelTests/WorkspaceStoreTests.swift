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

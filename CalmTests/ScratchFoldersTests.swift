@testable import Calm
import Foundation
import Testing

struct ScratchFoldersTests {
    private func root() -> URL {
        FileManager.default.temporaryDirectory.appending(path: "calm-scratch-\(UUID().uuidString)", directoryHint: .isDirectory)
    }

    @Test func `each scratch session gets a new empty folder`() throws {
        let root = root()
        defer { try? FileManager.default.removeItem(at: root) }
        let now = Date(timeIntervalSince1970: 1_790_000_000)
        let first = try ScratchFolders.make(in: root, now: now)
        let second = try ScratchFolders.make(in: root, now: now) // the same second
        #expect(first != second)
        #expect(ScratchFolders.contents(of: first.path).isEmpty)
        #expect(FileManager.default.fileExists(atPath: second.path))
    }

    @Test func `an empty folder is removed, and Finder's .DS_Store doesn't count as a file`() throws {
        let root = root()
        defer { try? FileManager.default.removeItem(at: root) }
        let folder = try ScratchFolders.make(in: root)
        try Data().write(to: folder.appending(path: ".DS_Store"))
        #expect(ScratchFolders.contents(of: folder.path).isEmpty)
        ScratchFolders.discard(folder.path)
        #expect(!FileManager.default.fileExists(atPath: folder.path))
    }
}

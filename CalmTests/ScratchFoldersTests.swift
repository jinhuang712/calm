@testable import Calm
import CalmModel
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

    @Test func `scratch folders live in a hidden folder without spaces, which a prompt shows`() {
        let root = ScratchFolders.standardRoot(home: URL(filePath: "/Users/someone", directoryHint: .isDirectory))
        #expect(root.path == "/Users/someone/.local/share/calm/scratch")
        #expect(!root.path.contains(" "))
    }

    @Test func `unit tests keep their scratch folders out of the real one`() {
        let real = ScratchFolders.standardRoot(home: FileManager.default.homeDirectoryForCurrentUser)
        #expect(ScratchFolders.root != real)
        #expect(ScratchFolders.root.path.hasPrefix(CalmDefaults.directory.path))
    }

    @Test func `the root stays out of Time Machine, and a folder moved out of it doesn't`() throws {
        let root = root()
        defer { try? FileManager.default.removeItem(at: root) }
        let folder = try ScratchFolders.make(in: root)
        #expect(isExcludedFromBackup(root))
        #expect(isExcludedFromBackup(folder)) // inside the root

        // What Keep as Project… does: the folder leaves the root, and is backed up from then on.
        let kept = FileManager.default.temporaryDirectory.appending(path: "calm-kept-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: kept) }
        try FileManager.default.moveItem(at: folder, to: kept)
        #expect(!isExcludedFromBackup(kept))
    }

    /// Read through a fresh URL: resource values are cached on the one that was set.
    private func isExcludedFromBackup(_ url: URL) -> Bool {
        let fresh = URL(filePath: url.path, directoryHint: .isDirectory)
        return (try? fresh.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup) == true
    }
}

@MainActor
struct FilesColumnTitleTests {
    @Test func `the files column names a project's folder, and calls a scratch folder Scratch`() {
        let model = FilesModel()
        #expect(model.title == "No project")
        model.follow("/Users/someone/.local/share/calm/scratch/0929-021720", isScratch: true)
        #expect(model.title == "Scratch")
        model.follow("/Users/someone/dev/calm")
        #expect(model.title == WorkspacePath.displayName(for: "/Users/someone/dev/calm"))
    }
}

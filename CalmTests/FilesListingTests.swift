@testable import Calm
import Foundation
import Testing

struct FilesListingTests {
    /// A scratch folder under `/tmp`, which macOS reaches through the `/private/tmp` symlink.
    private func scratch() throws -> String {
        let folder = "/tmp/calm-files-\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
        return folder
    }

    private func touch(_ path: String, in folder: String) throws {
        let url = URL(filePath: folder).appending(path: path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("x\n".utf8).write(to: url)
    }

    private func git(_ arguments: [String], in folder: String) throws {
        let process = Process()
        process.executableURL = URL(filePath: "/usr/bin/git")
        process.arguments = ["-C", folder, "-c", "user.email=test@example.com", "-c", "user.name=Test"] + arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
    }

    @Test func `a plain folder: relative paths, hidden and build folders left out`() throws {
        let folder = try scratch()
        defer { try? FileManager.default.removeItem(atPath: folder) }
        for path in ["a.txt", "docs/b.md", "node_modules/x/c.js", ".hidden/d", ".env", "Tool.app/Contents/e"] {
            try touch(path, in: folder)
        }
        let listing = FilesListing.read(folder)
        #expect(listing.paths.sorted() == ["a.txt", "docs/b.md"])
        #expect(listing.changes.isEmpty)
        #expect(listing.branch == nil)
    }

    @Test func `a plain folder is walked breadth first, so a big first folder doesn't hide the rest`() throws {
        let folder = try scratch()
        defer { try? FileManager.default.removeItem(atPath: folder) }
        for index in 0 ..< 20 {
            try touch("aaa/deep/file\(index).txt", in: folder)
        }
        try touch("zzz/last.txt", in: folder)
        try touch("top.txt", in: folder)
        let paths = FilesListing.walk(folder, limit: 5).paths
        #expect(paths.count == 5)
        #expect(paths.contains("top.txt"))
        #expect(paths.contains("zzz/last.txt"))
    }

    @Test func `a repository subfolder: ignored files hidden, changes relative to the folder`() throws {
        let repo = try scratch()
        defer { try? FileManager.default.removeItem(atPath: repo) }
        for path in ["app/README.md", "app/src/main.swift", "app/gone.txt", "other/x.txt"] {
            try touch(path, in: repo)
        }
        try Data("*.log\n".utf8).write(to: URL(filePath: repo).appending(path: ".gitignore"))
        try git(["init", "-q", "-b", "main"], in: repo)
        try git(["add", "-A"], in: repo)
        try git(["commit", "-qm", "init"], in: repo)
        try Data("changed\n".utf8).write(to: URL(filePath: repo).appending(path: "app/README.md"))
        try FileManager.default.removeItem(atPath: repo + "/app/gone.txt")
        try touch("app/notes.txt", in: repo)
        try touch("app/debug.log", in: repo)
        try touch("other/new.txt", in: repo)

        let listing = FilesListing.read(repo + "/app")
        #expect(listing.paths.sorted() == ["README.md", "gone.txt", "notes.txt", "src/main.swift"])
        #expect(listing.changes == ["README.md": .modified, "gone.txt": .deleted, "notes.txt": .untracked])
        #expect(listing.branch == "main")
    }
}

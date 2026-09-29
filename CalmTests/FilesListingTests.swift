@testable import Calm
import CalmModel
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

    @Test func `a walk leaves the folders macOS guards unread until they're opened`() throws {
        let home = try scratch()
        defer { try? FileManager.default.removeItem(atPath: home) }
        for path in ["Documents/report.md", "Documents/deep/notes.md", "Downloads/x.zip", "projects/app/main.swift", "top.txt"] {
            try touch(path, in: home)
        }
        let guarded: Set = [home + "/Documents", home + "/Downloads"]

        let closed = FilesListing.walk(home, guarded: guarded)
        #expect(closed.paths.sorted() == ["projects/app/main.swift", "top.txt"])
        #expect(closed.unread.sorted() == ["Documents", "Downloads"])

        // Opening one reads it, and only it.
        let opened = FilesListing.walk(home, guarded: guarded, opened: ["Documents"])
        #expect(opened.paths.sorted() == ["Documents/deep/notes.md", "Documents/report.md", "projects/app/main.swift", "top.txt"])
        #expect(opened.unread == ["Downloads"])
    }

    @Test func `a walk that starts in a guarded folder reads it, and the folders below`() throws {
        let home = try scratch()
        defer { try? FileManager.default.removeItem(atPath: home) }
        try touch("Documents/report.md", in: home)
        try touch("Documents/Downloads/x.zip", in: home) // only ~/Downloads is guarded
        let guarded: Set = [home + "/Documents", home + "/Downloads"]

        let listing = FilesListing.walk(home + "/Documents", guarded: guarded)
        #expect(listing.paths.sorted() == ["Downloads/x.zip", "report.md"])
        #expect(listing.unread.isEmpty)
        // From the folder above, only the top-level Documents is guarded (not Documents/Downloads),
        // and a trailing slash on the root doesn't hide it from the check.
        let above = FilesListing.walk(home + "/", guarded: guarded)
        #expect(above.unread == ["Documents"])
        #expect(above.paths.isEmpty)
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

    @Test func `a repository subfolder: each change's lines, from git and for untracked files`() throws {
        let repo = try scratch()
        defer { try? FileManager.default.removeItem(atPath: repo) }
        let write = { (path: String, text: String) in
            let url = URL(filePath: repo).appending(path: path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(text.utf8).write(to: url)
        }
        try write("app/README.md", "one\ntwo\nthree\n")
        try write("app/src/Old.swift", "let a = 1\nlet b = 2\nlet c = 3\nlet d = 4\nlet e = 5\n")
        try write("app/gone.txt", "x\n")
        try Data([0x00, 0x01, 0x02]).write(to: URL(filePath: repo).appending(path: "app/icon.bin"))
        try write("top.txt", "top\n")
        try git(["init", "-q", "-b", "main"], in: repo)
        try git(["add", "-A"], in: repo)
        try git(["commit", "-qm", "init"], in: repo)

        try write("app/README.md", "one\nTWO\nthree\nfour\n") // 2 added, 1 removed
        try git(["mv", "app/src/Old.swift", "app/src/New.swift"], in: repo)
        try write("app/src/New.swift", "let a = 1\nlet b = 2\nlet c = 3\nlet d = 4\nlet e = 50\n")
        try git(["add", "app/src/New.swift"], in: repo) // renamed, 1 line changed
        try FileManager.default.removeItem(atPath: repo + "/app/gone.txt")
        try Data([0x00, 0x09, 0x09]).write(to: URL(filePath: repo).appending(path: "app/icon.bin")) // binary
        try write("app/Staged.md", "fresh\nfile\n")
        try git(["add", "app/Staged.md"], in: repo)
        try write("app/notes.txt", "a\nb\nc") // untracked, no newline at the end
        try write("top.txt", "top\nmore\n") // outside the folder

        let listing = FilesListing.read(repo + "/app")
        #expect(listing.changes["src/New.swift"] == .renamed)
        #expect(listing.lines == [
            "README.md": LineCounts(added: 2, deleted: 1),
            "src/New.swift": LineCounts(added: 1, deleted: 1),
            "gone.txt": LineCounts(added: 0, deleted: 1),
            "Staged.md": LineCounts(added: 2, deleted: 0),
            "notes.txt": LineCounts(added: 3, deleted: 0),
        ])
    }

    @Test func `a repository without commits lists its files, uncounted`() throws {
        let repo = try scratch()
        defer { try? FileManager.default.removeItem(atPath: repo) }
        try touch("a.txt", in: repo)
        try git(["init", "-q", "-b", "main"], in: repo)
        let listing = FilesListing.read(repo)
        #expect(listing.paths == ["a.txt"])
        #expect(listing.changes == ["a.txt": .untracked])
        #expect(listing.lines == ["a.txt": LineCounts(added: 1, deleted: 0)]) // counted by Calm, not git
    }
}

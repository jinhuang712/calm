@testable import Calm
import CalmModel
import Foundation
import Testing

struct ViewerChangeTests {
    /// A scratch folder under `/tmp`, which macOS reaches through the `/private/tmp` symlink.
    private func scratch() throws -> String {
        let folder = "/tmp/calm-viewer-\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
        return folder
    }

    private func write(_ text: String, to path: String, in folder: String) throws {
        let url = URL(filePath: folder).appending(path: path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
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

    /// A repository with `src/main.swift` committed.
    private func repository() throws -> String {
        let folder = try scratch()
        try git(["init", "-q"], in: folder)
        try write("let a = 1\nlet b = 2\nlet c = 3\n", to: "src/main.swift", in: folder)
        try git(["add", "."], in: folder)
        try git(["commit", "-q", "-m", "first"], in: folder)
        return folder
    }

    @Test func `a changed file: its diff against the last commit, and the last commit's text`() throws {
        let folder = try repository()
        defer { try? FileManager.default.removeItem(atPath: folder) }
        try write("let a = 1\nlet b = 20\nlet c = 3\nlet d = 4\n", to: "src/main.swift", in: folder)
        let change = ViewerChange.read("\(folder)/src/main.swift")
        guard case let .changed(diff, oldText) = change else {
            Issue.record("expected a change, got \(change)")
            return
        }
        #expect(oldText == "let a = 1\nlet b = 2\nlet c = 3\n")
        #expect(diff.marks == [2: .modified, 4: .added])
        #expect(change.lines == LineCounts(added: 2, deleted: 1))
        let payload = try #require(change.pagePayload)
        #expect((payload["marks"] as? [String: String]) == ["2": "modified", "4": "added"])
        #expect((payload["hunks"] as? [[String: Any]])?.count == 1)
    }

    @Test func `staged and unstaged changes count together, as in the files column`() throws {
        let folder = try repository()
        defer { try? FileManager.default.removeItem(atPath: folder) }
        try write("let a = 10\nlet b = 2\nlet c = 3\n", to: "src/main.swift", in: folder)
        try git(["add", "."], in: folder)
        try write("let a = 10\nlet b = 2\nlet c = 30\n", to: "src/main.swift", in: folder)
        #expect(ViewerChange.read("\(folder)/src/main.swift").lines == LineCounts(added: 2, deleted: 2))
    }

    @Test func `an untracked or newly added file is new, an unchanged one unchanged`() throws {
        let folder = try repository()
        defer { try? FileManager.default.removeItem(atPath: folder) }
        try write("hello\n", to: "notes.md", in: folder)
        #expect(ViewerChange.read("\(folder)/notes.md") == .new)
        try git(["add", "notes.md"], in: folder)
        #expect(ViewerChange.read("\(folder)/notes.md") == .new)
        #expect(ViewerChange.read("\(folder)/src/main.swift") == .unchanged)
    }

    @Test func `outside a repository, nothing changed`() throws {
        let folder = try scratch()
        defer { try? FileManager.default.removeItem(atPath: folder) }
        try write("text\n", to: "a.txt", in: folder)
        #expect(ViewerChange.read("\(folder)/a.txt") == .unchanged)
    }

    @Test @MainActor func `the header's folder is relative to the project, or from home outside it`() {
        let home = NSHomeDirectory()
        #expect(FileViewer.folder(of: "\(home)/dev/calm/scripts/fixtures/a.sh", in: "\(home)/dev/calm") == "scripts/fixtures")
        #expect(FileViewer.folder(of: "\(home)/dev/calm/README.md", in: "\(home)/dev/calm/") == nil)
        #expect(FileViewer.folder(of: "\(home)/Downloads/x.pdf", in: "\(home)/dev/calm") == "~/Downloads")
        // A sibling whose name starts like the project's isn't inside it.
        #expect(FileViewer.folder(of: "\(home)/dev/calm-old/a.sh", in: "\(home)/dev/calm") == "~/dev/calm-old")
        #expect(FileViewer.folder(of: "/tmp/a.txt", in: nil) == "/tmp")
    }
}

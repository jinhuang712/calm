@testable import Calm
import CalmModel
import Foundation
import Testing

struct WorktreeNameTests {
    /// A scratch folder under `/tmp`, made fresh so `GitRoot`'s cache never sees a path twice.
    private func scratch() throws -> String {
        let folder = "/tmp/calm-worktree-\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
        return folder
    }

    private func git(_ arguments: [String], in folder: String) throws {
        let process = Process()
        process.executableURL = URL(filePath: "/usr/bin/git")
        process.arguments = ["-C", folder, "-c", "user.email=test@example.com", "-c", "user.name=Test"] + arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        #expect(process.terminationStatus == 0, "git \(arguments.joined(separator: " "))")
    }

    @Test func `a linked worktree is named, the main checkout is not`() throws {
        let folder = try scratch()
        defer { try? FileManager.default.removeItem(atPath: folder) }
        let main = "\(folder)/app"
        try FileManager.default.createDirectory(atPath: main, withIntermediateDirectories: true)
        try git(["init", "-q"], in: main)
        try git(["commit", "-q", "--allow-empty", "-m", "first"], in: main)
        let linked = "\(main)/.claude/worktrees/dark-mode"
        try git(["worktree", "add", "-q", "-b", "wt-dark-mode", linked], in: main)
        try FileManager.default.createDirectory(atPath: "\(linked)/Sources/App", withIntermediateDirectories: true)

        #expect(GitRoot.worktreeName(linked) == "dark-mode")
        // A folder inside it is in it too.
        #expect(GitRoot.worktreeName("\(linked)/Sources/App") == "dark-mode")
        #expect(GitRoot.worktreeName(main) == nil)
    }

    @Test func `a submodule is not a worktree`() throws {
        let folder = try scratch()
        defer { try? FileManager.default.removeItem(atPath: folder) }
        // What `git submodule add` leaves: a `.git` file that points into `.git/modules`.
        let module = "\(folder)/vendor/lib"
        try FileManager.default.createDirectory(atPath: module, withIntermediateDirectories: true)
        try Data("gitdir: ../../.git/modules/lib\n".utf8).write(to: URL(filePath: "\(module)/.git"))
        #expect(GitRoot.find(module) == module)
        #expect(GitRoot.worktreeName(module) == nil)
    }

    @Test func `a plain folder has no worktree`() throws {
        let folder = try scratch()
        defer { try? FileManager.default.removeItem(atPath: folder) }
        #expect(GitRoot.worktreeName(folder) == nil)
    }

    @Test func `a session works in the worktree its agent is in`() throws {
        let folder = try scratch()
        defer { try? FileManager.default.removeItem(atPath: folder) }
        let main = "\(folder)/app"
        try FileManager.default.createDirectory(atPath: main, withIntermediateDirectories: true)
        try git(["init", "-q"], in: main)
        try git(["commit", "-q", "--allow-empty", "-m", "first"], in: main)
        let linked = "\(main)/.claude/worktrees/fix-paste"
        try git(["worktree", "add", "-q", "-b", "wt-fix-paste", linked], in: main)

        // The shell stays in the main checkout; the agent moves.
        var session = Session(projectID: UUID(), workingDirectory: main)
        #expect(session.worktreeName == nil)
        session.agent = AgentRun(kind: .claudeCode, processID: 1)
        session.agent?.tail = TranscriptTail(directory: linked)
        #expect(session.worktreeName == "fix-paste")
        session.agent?.tail = TranscriptTail(directory: main)
        #expect(session.worktreeName == nil)
    }
}

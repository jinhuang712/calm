@testable import Calm
import Foundation
import Testing

/// The cleanup of the worktrees agents make, against real git repositories in `/tmp`.
struct WorktreeCleanupTests {
    /// A repository with one commit and a worktree made the way `claude -w` makes one: its own
    /// branch from HEAD, locked by the agent. Returns the main checkout and the worktree.
    private func repository(lock: String?) throws -> (main: String, worktree: String) {
        let main = "/tmp/calm-cleanup-\(UUID().uuidString)/app"
        try FileManager.default.createDirectory(atPath: main, withIntermediateDirectories: true)
        try git(["init", "-q", "-b", "main"], in: main)
        try git(["commit", "-q", "--allow-empty", "-m", "first"], in: main)
        let worktree = "\(main)/.claude/worktrees/quiet-river"
        try git(["worktree", "add", "-q", "-b", "worktree-quiet-river", worktree], in: main)
        if let lock {
            try git(["worktree", "lock", "--reason", lock, worktree], in: main)
        }
        return (main, worktree)
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

    /// The pid of a process that has exited, as the agent has once its session closed.
    private func exitedPid() throws -> Int32 {
        let process = try Process.run(URL(filePath: "/usr/bin/true"), arguments: [])
        process.waitUntilExit()
        return process.processIdentifier
    }

    private func claudeLock(pid: Int32) -> String {
        "claude session quiet-river (pid \(pid) start Wed Oct  7 08:29:37 2026)"
    }

    /// The scratch folder the repository is in.
    private func remove(_ main: String) {
        try? FileManager.default.removeItem(atPath: (main as NSString).deletingLastPathComponent)
    }

    private func branches(_ main: String) -> String {
        GitCommand.run(["branch", "--format=%(refname:short)"], in: main) ?? ""
    }

    @Test func `an empty worktree whose agent exited goes, with its branch`() throws {
        let (main, worktree) = try repository(lock: claudeLock(pid: exitedPid()))
        defer { remove(main) }
        #expect(WorktreeCleanup.removeIfEmpty(worktree, wait: 0) == .removed)
        #expect(!FileManager.default.fileExists(atPath: worktree))
        #expect(branches(main) == "main\n")
    }

    @Test func `a file git doesn't track yet keeps it`() throws {
        let (main, worktree) = try repository(lock: claudeLock(pid: exitedPid()))
        defer { remove(main) }
        try Data("draft\n".utf8).write(to: URL(filePath: "\(worktree)/notes.md"))
        #expect(WorktreeCleanup.removeIfEmpty(worktree, wait: 0) == .notEmpty)
        #expect(FileManager.default.fileExists(atPath: "\(worktree)/notes.md"))
    }

    @Test func `a commit only its branch has keeps it`() throws {
        let (main, worktree) = try repository(lock: claudeLock(pid: exitedPid()))
        defer { remove(main) }
        try git(["commit", "-q", "--allow-empty", "-m", "work"], in: worktree)
        #expect(WorktreeCleanup.removeIfEmpty(worktree, wait: 0) == .notEmpty)
        #expect(FileManager.default.fileExists(atPath: worktree))
        #expect(branches(main).contains("worktree-quiet-river"))
    }

    @Test func `a worktree whose agent still runs is kept`() throws {
        let (main, worktree) = try repository(lock: claudeLock(pid: getpid()))
        defer { remove(main) }
        #expect(WorktreeCleanup.removeIfEmpty(worktree, wait: 0) == .agentRunning)
        #expect(FileManager.default.fileExists(atPath: worktree))
    }

    @Test func `a worktree no agent locked as its own is never touched`() throws {
        for lock in [nil, "", "on a removable drive"] {
            let (main, worktree) = try repository(lock: lock)
            defer { remove(main) }
            #expect(WorktreeCleanup.removeIfEmpty(worktree, wait: 0) == .notAnAgents)
            #expect(FileManager.default.fileExists(atPath: worktree))
        }
    }
}

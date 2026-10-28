@testable import CalmAgents
import Foundation
import Testing

/// A command typed before the shell's prompt must stay under the terminal's line limit (1023
/// bytes), or it is cut mid-character and never run (specs/CLI.md → `calm new`).
struct LongCommandTests {
    private func scratch() -> URL {
        FileManager.default.temporaryDirectory.appending(path: "calm-long-command-\(UUID().uuidString)")
    }

    @Test func `a short command is typed as it is`() {
        let directory = scratch()
        #expect(LongCommand.typed("claude 'hi'", in: directory) == "claude 'hi'")
        #expect(!FileManager.default.fileExists(atPath: directory.path))
    }

    @Test func `a long command becomes a short source line, and the shell runs all of it`() throws {
        let directory = scratch()
        defer { try? FileManager.default.removeItem(at: directory) }
        // 1.2 KB of three-byte characters and a quote, as in the prompt that was cut.
        let prompt = String(repeating: "你好 it's ", count: 120)
        let command = "print -r -- " + shellQuoted(prompt)
        let typed = LongCommand.typed(command, in: directory)
        #expect(typed.utf8.count < LongCommand.limit)
        #expect(typed.hasPrefix("source '"))

        let process = Process()
        process.executableURL = URL(filePath: "/bin/zsh")
        process.arguments = ["-fc", typed]
        let output = Pipe()
        process.standardOutput = output
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        #expect(String(bytes: data, encoding: .utf8) == prompt + "\n")
        // The file removed itself: no prompt stays on disk.
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path).isEmpty)
    }
}

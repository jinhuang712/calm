import Foundation

/// Runs `git -C <folder> …` and returns its output, or nil when it fails. Blocking: call it off the
/// main thread (the files column's listing, the cleanup of an agent's empty worktree).
enum GitCommand {
    static func run(_ arguments: [String], in folder: String) -> String? {
        let process = Process()
        process.executableURL = URL(filePath: "/usr/bin/git")
        process.arguments = ["-C", folder] + arguments
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return nil
        }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        return String(bytes: data, encoding: .utf8)
    }
}

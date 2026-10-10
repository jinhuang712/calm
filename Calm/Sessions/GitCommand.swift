import Foundation

/// Runs `git -C <folder> …` and returns its output, or nil when it fails. Blocking: call it off the
/// main thread (the files column's listing, the cleanup of an agent's empty worktree).
enum GitCommand {
    static func run(_ arguments: [String], in folder: String) -> String? {
        data(arguments, in: folder).flatMap { String(bytes: $0, encoding: .utf8) }
    }

    /// The same, as bytes: for output that may be long enough that decoding it all is the cost.
    static func data(_ arguments: [String], in folder: String) -> Data? {
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
        return data
    }
}

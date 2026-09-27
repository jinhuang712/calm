import Foundation

/// Keeps shells alive while Calm is closed, using the bundled zmx (https://zmx.sh, MIT).
///
/// Each session runs `zmx attach <name>` as its terminal command: attaching creates the
/// zmx session on first use and re-attaches (with scrollback) after a relaunch. Closing a
/// session in Calm kills its zmx session; quitting Calm only detaches.
enum PersistentShell {
    static var executable: URL? {
        guard let url = Bundle.main.resourceURL?.appending(path: "bin/zmx"),
              FileManager.default.isExecutableFile(atPath: url.path)
        else { return nil }
        return url
    }

    static var isAvailable: Bool {
        executable != nil && ProcessInfo.processInfo.environment["CALM_NO_PERSISTENCE"] != "1"
    }

    /// The terminal command for a session (run through `/bin/sh -c` by libghostty).
    static func attachCommand(name: String) -> String? {
        guard isAvailable, let executable else { return nil }
        return "\(shellQuoted(executable.path)) attach \(shellQuoted(name))"
    }

    /// Environment for the zmx client: no detach key, so Ctrl-\ stays with the program.
    static let environment = ["ZMX_NO_DETACH_KEY": "1"]

    /// Names of the zmx sessions that are alive right now.
    static func liveSessions() -> Set<String> {
        guard let output = run(["list", "--short"]) else { return [] }
        return Set(output.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty })
    }

    /// Ends a zmx session and the shell in it.
    static func kill(name: String) {
        _ = run(["kill", name, "--force"])
    }

    @discardableResult
    private static func run(_ arguments: [String]) -> String? {
        guard let executable else { return nil }
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return nil
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(data: data, encoding: .utf8)
    }

    static func shellQuoted(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}

/// Finds the git repository root for a folder by looking for `.git` upward. No processes spawned.
enum GitRoot {
    private nonisolated(unsafe) static var cache: [String: String?] = [:] // guarded by `lock`
    private static let lock = NSLock()

    static func find(_ directory: String) -> String? {
        lock.lock()
        if let cached = cache[directory] {
            lock.unlock()
            return cached
        }
        lock.unlock()

        var url = URL(filePath: directory, directoryHint: .isDirectory)
        var result: String?
        while url.path != "/" {
            if FileManager.default.fileExists(atPath: url.appending(path: ".git").path) {
                result = url.path
                break
            }
            url.deleteLastPathComponent()
        }
        lock.lock()
        cache[directory] = result
        lock.unlock()
        return result
    }
}

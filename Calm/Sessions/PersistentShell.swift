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

    /// Calm's own zmx directory, so Calm's sessions never mix with other apps' zmx sessions.
    /// Kept short: zmx puts a Unix socket per session here, and socket paths are length-limited.
    static var directory: String {
        (NSTemporaryDirectory() as NSString).appendingPathComponent("calm-zmx")
    }

    /// The terminal command for a session (run through `/bin/sh -c` by libghostty).
    ///
    /// `env -u ZMX_SESSION`: inside a zmx session that variable makes `attach` switch the
    /// *calling* terminal instead of starting a client, so it must never be inherited.
    static func attachCommand(name: String) -> String? {
        guard isAvailable, let executable else { return nil }
        try? FileManager.default.createDirectory(
            atPath: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700],
        )
        return "/usr/bin/env -u ZMX_SESSION \(shellQuoted(executable.path)) attach \(shellQuoted(name))"
    }

    /// Environment for the zmx client: Calm's own session directory, and no detach key
    /// (Ctrl-\ stays with the program).
    static var environment: [String: String] {
        ["ZMX_DIR": directory, "ZMX_NO_DETACH_KEY": "1"]
    }

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
        var env = ProcessInfo.processInfo.environment
        env["ZMX_SESSION"] = nil
        env["ZMX_DIR"] = directory
        process.environment = env
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

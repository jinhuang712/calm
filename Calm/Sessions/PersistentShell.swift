import CalmModel
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
        // Self-tests use their own (CALM_ZMX_DIR), so they never touch a real Calm's shells.
        if let override = ProcessInfo.processInfo.environment["CALM_ZMX_DIR"], !override.isEmpty {
            return override
        }
        return (NSTemporaryDirectory() as NSString).appendingPathComponent("calm-zmx")
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

    /// The shell process of each live zmx session, from `zmx list` (`name=… pid=… …` per line).
    static func shellProcesses() -> [String: pid_t] {
        listedShellProcesses() ?? [:]
    }

    /// The same, or nil when zmx couldn't say: with a list, a name missing from it is a shell
    /// that's gone (a dead session lists with no pid, `err=ConnectionRefused`).
    static func listedShellProcesses() -> [String: pid_t]? {
        run(["list"]).map(parseShellProcesses)
    }

    static func parseShellProcesses(_ listing: String) -> [String: pid_t] {
        var result: [String: pid_t] = [:]
        for line in listing.split(whereSeparator: \.isNewline) {
            var fields: [Substring: Substring] = [:]
            for field in line.split(whereSeparator: { $0 == "\t" || $0 == " " }) {
                guard let equals = field.firstIndex(of: "=") else { continue }
                fields[field[..<equals]] = field[field.index(after: equals)...]
            }
            if let name = fields["name"], let pid = fields["pid"].flatMap({ pid_t($0) }) {
                result[String(name)] = pid
            }
        }
        return result
    }

    /// Types `text` into a zmx session's terminal, as keys from a client would (`zmx send`): for a
    /// session no pane is attached to yet.
    static func send(name: String, text: String) {
        _ = run(["send", name, text])
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
        // What a failed command printed isn't an answer (an empty list would read as no shells).
        guard process.terminationStatus == 0 else { return nil }
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

    /// The worktree's name when the folder is inside a linked git worktree (its `.git` is a
    /// file pointing into the main repository's `worktrees/`), for session cards and the title strip.
    static func worktreeName(_ directory: String) -> String? {
        guard let root = find(directory) else { return nil }
        var isDirectory: ObjCBool = false
        let git = (root as NSString).appendingPathComponent(".git")
        guard FileManager.default.fileExists(atPath: git, isDirectory: &isDirectory), !isDirectory.boolValue,
              // A submodule's `.git` is a file too, but points into `modules/`: not a worktree.
              let pointer = try? String(contentsOfFile: git, encoding: .utf8), pointer.contains("/worktrees/")
        else { return nil }
        return (root as NSString).lastPathComponent
    }
}

extension Session {
    /// The linked git worktree the session's work is in, if any (see `activeDirectory`).
    var worktreeName: String? {
        GitRoot.worktreeName(activeDirectory)
    }
}

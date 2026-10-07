import Foundation

/// A running agent older than the one installed (UIUX.md → Title bar → the update hint): what a
/// restart would start, and what runs now, as far as Calm can tell.
public struct AgentUpdate: Equatable, Sendable {
    /// The installed version (`2.1.291`), when it can be read.
    public var installed: String?
    /// The running version, when it can still be read.
    public var running: String?

    public init(installed: String?, running: String?) {
        self.installed = installed
        self.running = running
    }
}

/// What one look at an agent's process found: the version it runs, and the update waiting.
public struct AgentVersions: Equatable, Sendable {
    public var running: String?
    public var update: AgentUpdate?

    public init(running: String?, update: AgentUpdate?) {
        self.running = running
        self.update = update
    }
}

/// Tells which version an agent's process runs and whether a newer one is installed, for any agent
/// (DESIGNS.md → Agents → Updates). Nothing here is agent-specific: it follows how the agent was
/// installed.
///
/// - **A native program behind a link whose path names the version** (Claude Code's
///   `~/.local/bin/claude` → `…/versions/2.1.291`, Codex's → `…/releases/0.159.0-…/bin/codex`):
///   the process's argv names its launcher; what that resolves to now is what a restart would run.
///   An update repoints it, or deletes the file the process runs.
/// - **A native program at a fixed path** (OpenCode's `~/.opencode/bin/opencode`): an update
///   replaces the file, so it is gone or newer than the process. The version comes from
///   `--version`, asked once per file.
/// - **A script run by node or bun** (pi): the shell names the command it ran in the process's
///   `_` variable, since pi overwrites its own argv. The version is the package's, and the script
///   being newer than the process means an update.
public enum AgentUpdates {
    /// What `process` runs and what is installed, or nil when that can't be told (a process that
    /// has exited, a launcher that is gone: an agent uninstalled rather than updated). `probe`
    /// asks a program its version; it is only called for a program whose path names none.
    public static func check(
        _ process: ProcessSnapshot, probe: (String) -> String? = probedVersion, slack: TimeInterval = 2,
    ) -> AgentVersions? {
        guard ProcessInspector.snapshot(of: process.processID) != nil, let target = installedProgram(of: process),
              let status = ProcessInspector.fileStatus(of: target)
        else { return nil }
        let started = ProcessInspector.startDate(of: process.processID) ?? .distantPast
        // `slack`: an agent started right after an install isn't behind it.
        let changedSinceStart = status.changed > started.addingTimeInterval(slack)
        if process.runsScript {
            // node doesn't keep the script mapped, so its file's change is all there is to go on.
            let installed = version(in: target) ?? packageVersion(near: target)
            return decideScript(installed: installed, changedSinceStart: changedSinceStart)
        }
        let running = ProcessInspector.executableFile(of: process.processID)
        // A new file at the same path: the path still resolves, but the mapped inode is another.
        let mapped = ProcessInspector.executableInode(of: process.processID)
        let replaced = mapped.map { $0 != status.identity } ?? changedSinceStart
        // Ask the program only when its path names no version.
        let installed = version(in: target) ?? probe(target)
        return decideNative(target: target, running: running, replaced: replaced, installed: installed)
    }

    /// The file a restart would run: the launcher resolved now. For a script, the script (pi's
    /// `cli.js`); nil when the launcher is gone.
    static func installedProgram(of process: ProcessSnapshot) -> String? {
        var launcher: String?
        if process.runsScript {
            // pi's argv is overwritten; the shell's `_` still names the command (zsh and bash set it).
            launcher = [process.commandPath, process.scriptPath].compactMap(\.self).first { path in
                path.hasPrefix("/") && !ProcessSnapshot.runtimes.contains((path as NSString).lastPathComponent)
            }
        } else if process.executablePath.hasPrefix("/") {
            launcher = process.executablePath
        }
        guard let launcher else { return nil }
        let target = URL(filePath: launcher).resolvingSymlinksInPath().path
        return FileManager.default.fileExists(atPath: target) ? target : nil
    }

    /// A native program: `running` is the file the process runs (nil: deleted by an update),
    /// `target` what the launcher leads to now, `replaced` whether the file at that path is no
    /// longer the one the process runs.
    static func decideNative(target: String, running: String?, replaced: Bool, installed: String?) -> AgentVersions {
        guard let running else {
            return AgentVersions(running: nil, update: AgentUpdate(installed: installed, running: nil))
        }
        if standardized(running) == standardized(target) {
            // The same path: a new file put there since the process started, or what it runs.
            return replaced
                ? AgentVersions(running: nil, update: AgentUpdate(installed: installed, running: nil))
                : AgentVersions(running: installed, update: nil)
        }
        let current = version(in: running)
        if let installed, let current, !isNewer(installed, than: current) {
            // The launcher pointing back at an older version is a choice, not an update.
            return AgentVersions(running: current, update: nil)
        }
        return AgentVersions(running: current, update: AgentUpdate(installed: installed, running: current))
    }

    /// A script: the package's version is the running one until the script changes under it.
    static func decideScript(installed: String?, changedSinceStart: Bool) -> AgentVersions {
        changedSinceStart
            ? AgentVersions(running: nil, update: AgentUpdate(installed: installed, running: nil))
            : AgentVersions(running: installed, update: nil)
    }

    // MARK: Versions

    /// The version a path names: its last component that starts with one (`2.1.291`,
    /// `0.160.1-aarch64-apple-darwin` → `0.160.1`).
    static func version(in path: String) -> String? {
        for component in path.split(separator: "/").reversed() {
            if let found = leadingVersion(component) {
                return found
            }
        }
        return nil
    }

    /// The version in a program's own words (`opencode v2.0.20`, `codex-cli 0.159.0`): the first
    /// word that is one, a leading "v" dropped.
    static func version(inOutput output: String) -> String? {
        for word in output.split(whereSeparator: { $0.isWhitespace }) {
            let bare = word.hasPrefix("v") ? word.dropFirst() : word[...]
            if let found = leadingVersion(bare), found.count == bare.count {
                return found
            }
        }
        return nil
    }

    private static func leadingVersion(_ text: Substring) -> String? {
        let digitsAndDots = text.prefix { $0.isNumber || $0 == "." }
        let parts = digitsAndDots.split(separator: ".", omittingEmptySubsequences: false)
        return parts.count >= 2 && parts.allSatisfy { !$0.isEmpty } ? String(digitsAndDots) : nil
    }

    /// The `version` of the nearest package.json above a script (pi's `…/pi-coding-agent/package.json`).
    static func packageVersion(near script: String) -> String? {
        var folder = URL(filePath: script).deletingLastPathComponent()
        for _ in 0 ..< 6 {
            let manifest = folder.appending(path: "package.json")
            if let data = try? Data(contentsOf: manifest),
               let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let version = object["version"] as? String {
                return version
            }
            folder.deleteLastPathComponent()
        }
        return nil
    }

    /// Whether `a` is a later version than `b`, number by number (`2.1.291` > `2.1.29`).
    static func isNewer(_ a: String, than b: String) -> Bool {
        let left = a.split(separator: ".").map { Int($0) ?? 0 }
        let right = b.split(separator: ".").map { Int($0) ?? 0 }
        for index in 0 ..< max(left.count, right.count) {
            let l = index < left.count ? left[index] : 0
            let r = index < right.count ? right[index] : 0
            if l != r {
                return l > r
            }
        }
        return false
    }

    private static func standardized(_ path: String) -> String {
        URL(filePath: path).standardizedFileURL.resolvingSymlinksInPath().path
    }

    // MARK: Asking a program

    private struct FileStamp: Hashable {
        var path: String
        var inode: UInt64
        var modified: Date
        var size: UInt64
    }

    private nonisolated(unsafe) static var probed: [FileStamp: String?] = [:] // guarded by `probeLock`
    private static let probeLock = NSLock()

    /// `<program> --version`, once per file (a new file, or a changed one, is asked again); nil when
    /// it doesn't answer with a version in two seconds. Off the main thread: it starts a process.
    public static func probedVersion(_ program: String) -> String? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: program) else { return nil }
        let stamp = FileStamp(
            path: program,
            inode: (attributes[.systemFileNumber] as? NSNumber)?.uint64Value ?? 0,
            modified: attributes[.modificationDate] as? Date ?? .distantPast,
            size: (attributes[.size] as? NSNumber)?.uint64Value ?? 0,
        )
        probeLock.lock()
        if let known = probed[stamp] {
            probeLock.unlock()
            return known
        }
        probeLock.unlock()
        let found = runVersion(program)
        probeLock.lock()
        probed[stamp] = found
        probeLock.unlock()
        return found
    }

    private static func runVersion(_ program: String) -> String? {
        let process = Process()
        process.executableURL = URL(filePath: program)
        process.arguments = ["--version"]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return nil
        }
        let deadline = Date().addingTimeInterval(2)
        while process.isRunning, Date() < deadline {
            usleep(20000)
        }
        if process.isRunning {
            process.terminate()
            return nil
        }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8).flatMap(version(inOutput:))
    }
}

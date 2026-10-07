import Foundation

/// A running agent older than the one installed (UIUX.md → Title bar → the update hint): what a
/// restart would start, and what runs now, as far as the files say.
public struct AgentUpdate: Equatable, Sendable {
    /// The installed version (`2.1.291`), when the installed program's path names one.
    public var installed: String?
    /// The running version, when its file is still there and its path names one.
    public var running: String?

    public init(installed: String?, running: String?) {
        self.installed = installed
        self.running = running
    }
}

/// Tells whether an agent's process runs an older program than the one its command starts now,
/// from files alone: no agent runs `--version`, and nothing is agent-specific (DESIGNS.md →
/// Agents → Updates).
///
/// The process was started through its launcher, the path in its argv (`~/.local/bin/claude`);
/// what that path resolves to now is what a restart would run. Installers that keep versions
/// side by side (Claude Code, Codex) repoint the launcher, so the two paths differ; ones that
/// replace a file delete the old one, so the running file is gone. Either way the version is
/// read from the path where it names one (`…/versions/2.1.291`, `…/releases/0.160.1-aarch64-…`).
public enum AgentUpdates {
    /// The update for `process`, or nil when it runs what its launcher starts (or that can't be
    /// told: a script runtime, whose own updates say nothing about the agent's; a process that
    /// has exited; a launcher that is gone, i.e. an agent uninstalled rather than updated).
    public static func check(_ process: ProcessSnapshot) -> AgentUpdate? {
        guard process.scriptPath == nil, process.executablePath.hasPrefix("/"),
              ProcessInspector.snapshot(of: process.processID) != nil
        else { return nil }
        let launcher = URL(filePath: process.executablePath).resolvingSymlinksInPath().path
        guard FileManager.default.fileExists(atPath: launcher) else { return nil }
        return compare(launcherTarget: launcher, running: ProcessInspector.executableFile(of: process.processID))
    }

    /// The version `processID` runs, as the path of its file names it (nil once the file was
    /// deleted, or for a path that names none): what the session menu shows by the agent's name.
    public static func runningVersion(of processID: Int32) -> String? {
        ProcessInspector.executableFile(of: processID).flatMap(version(in:))
    }

    /// The decision, from the two paths: where the launcher points now, and the file the process
    /// runs (nil: deleted).
    static func compare(launcherTarget: String, running: String?) -> AgentUpdate? {
        let installed = version(in: launcherTarget)
        guard let running else {
            return AgentUpdate(installed: installed, running: nil)
        }
        guard standardized(running) != standardized(launcherTarget) else { return nil }
        let current = version(in: running)
        if let installed, let current {
            // The launcher pointing back at an older version is a choice, not an update.
            return isNewer(installed, than: current) ? AgentUpdate(installed: installed, running: current) : nil
        }
        return AgentUpdate(installed: installed, running: current)
    }

    /// The version a path names: its last component that starts with one (`2.1.291`,
    /// `0.160.1-aarch64-apple-darwin` → `0.160.1`).
    static func version(in path: String) -> String? {
        for component in path.split(separator: "/").reversed() {
            let digitsAndDots = component.prefix { $0.isNumber || $0 == "." }
            let parts = digitsAndDots.split(separator: ".", omittingEmptySubsequences: false)
            if parts.count >= 2, parts.allSatisfy({ !$0.isEmpty }) {
                return String(digitsAndDots)
            }
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
}

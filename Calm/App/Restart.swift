import AppKit
import Darwin

/// Calm → Restart Calm: an ordinary quit, then the app opens again once this process is gone.
/// Quitting only detaches persistent shells, so every session comes back with its scrollback
/// and running programs, agents included.
///
/// What keeps it safe:
/// - It is the same quit as ⌘Q: the same save, and the same question when shells aren't kept
///   alive. The relaunch is set up only once the quit can no longer be cancelled.
/// - The new Calm starts only after this one has exited, so two never attach to the same shells
///   or write the same state at once. One that hasn't exited after 30 s isn't joined at all.
/// - It opens the app at the same path, so a copy installed there meanwhile (install.sh) is
///   the one that starts, and never another copy with the same bundle ID (a Debug build).
/// - A copy installed meanwhile moved this one aside (install.sh and get.sh rename it
///   `.Calm.app.previous-…`), and macOS went on starting that moved copy for the path, twice in a
///   row on 2026-10-12, with the new copy registered there; with the moved copy gone, it started
///   the new one (RUNBOOK.md → Installing under a running Calm). So once this Calm has exited, its moved copy is
///   deleted before the path is opened, and after a plain quit too, since the Dock and Spotlight
///   lead to it as well.
/// - The new Calm gets this one's environment (`open` hands on its own), so shells keep the
///   same `PATH`, and a Calm started with `CALM_*` overrides (a Debug build, a self-test) never
///   comes back sharing the real Calm's state and shells. The self-test drivers are left out,
///   so a test doesn't run again.
@MainActor
enum Restart {
    /// While a restart's quit is under way (the quit question words itself for it).
    private(set) static var isRequested = false

    static func request() {
        isRequested = true
        NSApp.terminate(nil)
        // `terminate` returns only when the quit was cancelled.
        isRequested = false
    }

    /// From `applicationWillTerminate`, when the quit is certain: once this process is gone, a
    /// restart opens Calm again, and a copy an installer moved aside is deleted.
    static func afterExit() {
        let moved = movedCopy(launchedFrom: Bundle.main.bundleURL, runningFrom: runningExecutable())
        guard isRequested || moved != nil else { return }
        let helper = Process()
        helper.executableURL = URL(fileURLWithPath: "/bin/sh")
        helper.arguments = helperArguments(
            waitingFor: getpid(),
            removing: moved,
            then: isRequested ? openCommand(app: Bundle.main.bundleURL, background: Headless.isOn) : [],
        )
        helper.environment = relaunchEnvironment(ProcessInfo.processInfo.environment)
        helper.standardInput = FileHandle.nullDevice
        helper.standardOutput = FileHandle.nullDevice
        helper.standardError = FileHandle.nullDevice
        do {
            try helper.run()
        } catch {
            // Degrade to a plain quit: nothing is lost, the user opens Calm again.
            FileHandle.standardError.write(Data("calm: restart couldn't start its helper (\(error)); quitting only\n".utf8))
        }
    }

    /// `open` for the app at this path. Without `-n`, so a Calm the user opened in the moment
    /// between is brought forward instead of joined by a second one.
    nonisolated static func openCommand(app: URL, background: Bool) -> [String] {
        // A headless self-test never comes to the front.
        (background ? ["/usr/bin/open", "-g"] : ["/usr/bin/open"]) + [app.path]
    }

    /// This Calm's environment, less what drives a self-test (typing, actions, snapshots, quitting).
    nonisolated static func relaunchEnvironment(_ environment: [String: String]) -> [String: String] {
        environment.filter { name, _ in !name.hasPrefix("CALM_SELFTEST_") && !name.hasPrefix("CALM_SNAPSHOT") }
    }

    /// The copy this Calm runs from when an installer moved it aside while it ran: install.sh and
    /// get.sh rename it `.Calm.app.previous-…`, beside the new one at the path it started from. Nil
    /// when it still runs from there, or was moved anywhere else, which is someone's own doing.
    nonisolated static func movedCopy(launchedFrom bundle: URL, runningFrom executable: String?) -> URL? {
        guard let executable else { return nil }
        let macOS = URL(fileURLWithPath: executable).deletingLastPathComponent()
        let contents = macOS.deletingLastPathComponent()
        let running = contents.deletingLastPathComponent()
        guard macOS.lastPathComponent == "MacOS", contents.lastPathComponent == "Contents",
              running.lastPathComponent.hasPrefix(".Calm.app.previous-"),
              running.deletingLastPathComponent().standardizedFileURL.path == bundle.deletingLastPathComponent().standardizedFileURL.path
        else { return nil }
        return running
    }

    /// Where this process's program file is now. `Bundle.main` keeps the path it started from;
    /// the kernel follows the file when its app is moved.
    private static func runningExecutable() -> String? {
        var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN) * 4)
        let length = proc_pidpath(getpid(), &buffer, UInt32(buffer.count))
        return length > 0 ? String(cString: buffer) : nil
    }

    /// `/bin/sh` arguments: wait for `pid` to exit, delete the copy at `moved` with its Launch
    /// Services record, then run `command` (none: nothing more).
    ///
    /// The helper is its own process because it has to outlive Calm. It watches the process
    /// itself (`ps`, where an unreaped zombie counts as gone) rather than a fixed delay, and
    /// retries the command for a few seconds, since install.sh may be swapping the app just
    /// then, or Launch Services may not have noticed the old Calm leave yet.
    nonisolated static func helperArguments(waitingFor pid: pid_t, removing moved: URL?, then command: [String]) -> [String] {
        ["-c", helperScript, "calm-restart", String(pid), moved?.path ?? ""] + command
    }

    private nonisolated static let helperScript = """
    pid=$1; moved=$2; shift 2
    i=0
    while stat=$(/bin/ps -o stat= -p "$pid"); do
      case $stat in *Z*) break ;; esac
      i=$((i + 1)); [ "$i" -ge 300 ] && exit 1
      /bin/sleep 0.1
    done
    if [ -n "$moved" ]; then
      /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -u "$moved" >/dev/null 2>&1
      /bin/rm -rf "$moved"
    fi
    [ $# -eq 0 ] && exit 0
    i=0
    until "$@"; do
      i=$((i + 1)); [ "$i" -ge 10 ] && exit 1
      /bin/sleep 0.5
    done
    """
}

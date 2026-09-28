import AppKit

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

    /// From `applicationWillTerminate`, when the quit is certain.
    static func relaunchAfterExit() {
        guard isRequested else { return }
        let helper = Process()
        helper.executableURL = URL(fileURLWithPath: "/bin/sh")
        helper.arguments = helperArguments(
            waitingFor: getpid(),
            then: openCommand(app: Bundle.main.bundleURL, background: Headless.isOn),
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

    /// `/bin/sh` arguments: wait for `pid` to exit, then run `command`.
    ///
    /// The helper is its own process because it has to outlive Calm. It watches the process
    /// itself (`ps`, where an unreaped zombie counts as gone) rather than a fixed delay, and
    /// retries the command for a few seconds, since install.sh may be swapping the app just
    /// then, or Launch Services may not have noticed the old Calm leave yet.
    nonisolated static func helperArguments(waitingFor pid: pid_t, then command: [String]) -> [String] {
        ["-c", helperScript, "calm-restart", String(pid)] + command
    }

    private nonisolated static let helperScript = """
    pid=$1; shift
    i=0
    while stat=$(/bin/ps -o stat= -p "$pid"); do
      case $stat in *Z*) break ;; esac
      i=$((i + 1)); [ "$i" -ge 300 ] && exit 1
      /bin/sleep 0.1
    done
    i=0
    until "$@"; do
      i=$((i + 1)); [ "$i" -ge 10 ] && exit 1
      /bin/sleep 0.5
    done
    """
}

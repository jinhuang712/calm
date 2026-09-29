import CalmControl
import Foundation

/// Calm runs once per control socket. A second copy that got as far as starting would unlink the
/// running Calm's socket and bind its own, restore the same saved sessions and attach to the same
/// shells. Every hook then reaches the newcomer, and when it quits they reach nothing: the
/// sessions of the Calm still running stop following their agents and sit gray while agents work.
/// (That happened when a script ran the app's binary with `--version`.)
///
/// A Calm that answers on the socket owns the user's sessions, so a newcomer steps aside before it
/// starts anything. Restart is unaffected (the new Calm starts after the old one has exited), and
/// self-tests and Debug runs that set `CALM_SOCKET` look at their own path.
enum SingleInstance {
    static func yieldToRunningCalm() {
        // The unit-test host runs beside whatever Calm the developer has open.
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil,
              ControlClient.isListening()
        else { return }
        Trace.note("another Calm is running; this one quits without starting")
        FileHandle.standardError.write(Data("calm: another Calm is already running; leaving it be\n".utf8))
        // Not `terminate`: the quit path saves state, and this process never loaded any, so it
        // would write an empty sidebar over the real one.
        exit(0)
    }
}

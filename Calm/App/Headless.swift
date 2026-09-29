import AppKit

/// Headless self-tests (`CALM_HEADLESS=1`, Debug builds only): Calm runs without ever showing
/// itself or taking focus, so tests don't disturb whoever is using the Mac.
///
/// - No Dock icon, never activated: the user's frontmost app keeps focus and the keyboard.
/// - The window is fully transparent, click-through and out of window cycling, and it never
///   becomes key (a key window, even invisible, would take the user's typing).
/// - Because it never becomes key, terminal focus and "the session the user is looking at"
///   treat the main window as if it were in front.
/// - A transparent window counts as occluded, which would pause rendering; panes keep
///   rendering so snapshots show real content, and App Nap is held off so timers stay on time.
/// - The Mac may still sleep, and the run quits by itself after `lifetime`: one that no script
///   was waiting for (its script killed, or a relaunch) once ran for three hours, at 5% of a
///   core, holding off the Mac's idle sleep on battery.
enum Headless {
    #if DEBUG
        static let isOn = ProcessInfo.processInfo.environment["CALM_HEADLESS"] == "1"
    #else
        static let isOn = false
    #endif

    @MainActor private static var activity: NSObjectProtocol?

    /// How long a headless run may live: the snapshot's delay plus ten minutes, well past
    /// selftest.sh's own watchdog (the delay plus a minute) and any motion probe.
    static func lifetime(snapshotDelay: TimeInterval?) -> TimeInterval {
        max(snapshotDelay ?? 0, 0) + 600
    }

    /// Before any window exists (the activation policy is set in main.swift, before launch).
    @MainActor
    static func prepareApp() {
        guard isOn else { return }
        activity = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiatedAllowingIdleSystemSleep, .latencyCritical],
            reason: "Headless self-test",
        )
        let delay = ProcessInfo.processInfo.environment["CALM_SNAPSHOT_DELAY"].flatMap(Double.init)
        let lifetime = lifetime(snapshotDelay: delay)
        DispatchQueue.main.asyncAfter(deadline: .now() + lifetime) {
            MainActor.assumeIsolated {
                FileHandle.standardError.write(Data("calm-selftest: headless run quit after \(Int(lifetime))s\n".utf8))
                SessionManager.shared.prepareForQuit()
                exit(0)
            }
        }
    }

    /// Shows the window without showing it: in the window list (so it renders and can be
    /// snapshotted) but invisible, click-through and never key.
    @MainActor
    static func present(_ window: NSWindow) {
        window.alphaValue = 0
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.collectionBehavior.insert([.transient, .ignoresCycle])
        window.orderFrontRegardless()
    }
}

extension NSPasteboard {
    /// The pasteboard Calm copies to and pastes from: the general one, or a private one in a
    /// headless self-test, so a run never reads or replaces the user's clipboard (a test that
    /// saved and put back only text once lost an image the user had copied).
    static var calm: NSPasteboard {
        Headless.isOn ? NSPasteboard(name: .init("calm-selftest")) : .general
    }
}

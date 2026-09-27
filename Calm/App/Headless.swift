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
enum Headless {
    #if DEBUG
        static let isOn = ProcessInfo.processInfo.environment["CALM_HEADLESS"] == "1"
    #else
        static let isOn = false
    #endif

    @MainActor private static var activity: NSObjectProtocol?

    /// Before any window exists (the activation policy is set in main.swift, before launch).
    @MainActor
    static func prepareApp() {
        guard isOn else { return }
        activity = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiated, .latencyCritical],
            reason: "Headless self-test",
        )
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

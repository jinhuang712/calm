import AppKit

// A second Calm steps aside before it starts anything (see SingleInstance).
SingleInstance.yieldToRunningCalm()

// AppKit entry point. The terminal engine is initialized before the app runs
// so every later call into libghostty has a ready global state.
MainActor.assumeIsolated {
    GhosttyRuntime.initializeProcess()

    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    // Headless self-tests run as an accessory app, set before launch so AppKit never brings
    // Calm to the front (see Headless.swift).
    app.setActivationPolicy(Headless.isOn ? .accessory : .regular)
    #if DEBUG
        // Self-tests check both variants of a theme without changing the system's appearance.
        switch ProcessInfo.processInfo.environment["CALM_APPEARANCE"] {
        case "light": app.appearance = NSAppearance(named: .aqua)
        case "dark": app.appearance = NSAppearance(named: .darkAqua)
        default: break
        }
    #endif
    withExtendedLifetime(delegate) {
        app.run()
    }
}

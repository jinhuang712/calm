import AppKit

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
    withExtendedLifetime(delegate) {
        app.run()
    }
}

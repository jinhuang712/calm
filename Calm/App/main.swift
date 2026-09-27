import AppKit

// AppKit entry point. The terminal engine is initialized before the app runs
// so every later call into libghostty has a ready global state.
MainActor.assumeIsolated {
    GhosttyRuntime.initializeProcess()

    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.regular)
    withExtendedLifetime(delegate) {
        app.run()
    }
}

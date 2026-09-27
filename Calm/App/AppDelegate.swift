import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_: Notification) {
        Headless.prepareApp()
        UserDefaults.standard.register(defaults: [
            // Holding a key should repeat it, not open the accent picker.
            "ApplePressAndHoldEnabled": false,
            // On macOS 26 the autofill heuristics cost a lot of CPU in terminal views.
            "NSAutoFillHeuristicControllerEnabled": false,
        ])
    }

    func applicationDidFinishLaunching(_: Notification) {
        NSApp.mainMenu = MainMenu.make()
        TerminalEngine.shared.delegate = TerminalWindowManager.shared
        TerminalEngine.shared.start()
        // Unit tests host the app; they don't need a live shell.
        let isTesting = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
        if !isTesting {
            SessionManager.shared.restore()
            ControlServer.shared.start()
            SessionProbe.shared.start()
            AttentionCenter.shared.start()
            TerminalWindowManager.shared.openMainWindow()
        }
        if !Headless.isOn {
            NSApp.activate()
        }

        #if DEBUG
            SelfTest.scheduleIfRequested()
        #endif
    }

    func applicationShouldTerminate(_: NSApplication) -> NSApplication.TerminateReply {
        // With persistent shells, quitting only detaches: nothing is lost, so don't ask.
        guard !PersistentShell.isAvailable, TerminalEngine.shared.needsConfirmQuit else { return .terminateNow }
        let alert = NSAlert()
        alert.messageText = "Quit Calm?"
        alert.informativeText = "Processes are still running in some terminals."
        alert.addButton(withTitle: "Quit")
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn ? .terminateNow : .terminateCancel
    }

    func applicationWillTerminate(_: Notification) {
        ControlServer.shared.stop()
        SessionManager.shared.prepareForQuit()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_: NSApplication) -> Bool {
        true
    }

    func applicationShouldHandleReopen(_: NSApplication, hasVisibleWindows: Bool) -> Bool {
        if !hasVisibleWindows {
            TerminalWindowManager.shared.openMainWindow()
        }
        return true
    }
}

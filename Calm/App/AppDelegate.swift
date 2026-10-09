import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_: Notification) {
        Trace.begin()
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
        Trace.note("engine started")
        AccessibilitySettings.startObserving()
        // Unit tests host the app; they don't need a live shell.
        let isTesting = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
        if !isTesting {
            // Before any shell starts: zsh starts through it (⌘ Return).
            ShellIntegration.prepare()
            SessionManager.shared.restore()
            Trace.note("state restored")
            // Before the control server and the window: the saved rows are checked against the
            // running agents, so hooks refine a settled sidebar and the first frame is right.
            SessionProbe.shared.settleSavedRuns()
            ControlServer.shared.start()
            Trace.note("control socket listening")
            SessionProbe.shared.start()
            Trace.note("probe scheduled")
            AttentionCenter.shared.start()
            AgentIntegrations.prepare()
            Trace.note("agent integrations ready")
            SearchService.start()
            Trace.note("search started")
            // A check a few seconds later, and only when one is due (UpdateChecker).
            UpdateChecker.shared.start()
            TerminalWindowManager.shared.openMainWindow()
            Trace.note("window open")
            // Headless self-tests run without a Dock icon.
            if !Headless.isOn {
                DockIcon.shared.start()
            }
        }
        if !Headless.isOn {
            NSApp.activate()
        }

        #if DEBUG
            SelfTest.scheduleIfRequested()
        #endif
    }

    func applicationShouldTerminate(_: NSApplication) -> NSApplication.TerminateReply {
        // With persistent shells, quitting only detaches: nothing is lost, so don't ask. Persistence
        // can also stop mid-run (zmx failing), and then shells end with Calm like anywhere else.
        let shellsSurvive = PersistentShell.isAvailable && SessionManager.shared.persistenceEnabled
        guard !shellsSurvive, TerminalEngine.shared.needsConfirmQuit else { return .terminateNow }
        let alert = NSAlert()
        if Restart.isRequested {
            alert.messageText = "Restart \(BuildVariant.appName)?"
            alert.informativeText = "Processes are still running in some terminals. Restarting ends them."
            alert.addButton(withTitle: "Restart")
        } else {
            alert.messageText = "Quit \(BuildVariant.appName)?"
            alert.informativeText = "Processes are still running in some terminals."
            alert.addButton(withTitle: "Quit")
        }
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn ? .terminateNow : .terminateCancel
    }

    func applicationWillTerminate(_: Notification) {
        ControlServer.shared.stop()
        SessionManager.shared.prepareForQuit()
        Restart.relaunchAfterExit()
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

import AppKit

/// Two rare failures of Calm's saved state that would otherwise lose the user's sessions without
/// a word: a state file that couldn't be read at launch, and a save that failed. Each says what
/// happened and what is still safe; nothing else in Calm uses an alert for this.
@MainActor
enum StateAlerts {
    private static var failing = false

    /// Tests and self-tests have nobody to answer.
    private static var canShow: Bool {
        !Headless.isOn && ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil
    }

    /// At launch, when the saved state was moved aside: Calm opens empty, and the old file is
    /// where a newer Calm (or a repair) can still read it.
    static func tellAboutUnreadableState(_ kept: URL?) {
        guard let kept, canShow else { return }
        let alert = NSAlert()
        alert.messageText = "Couldn't read your saved sessions"
        alert.informativeText = "\(BuildVariant.appName) opened empty. The old file is kept as \(kept.lastPathComponent), "
            + "so nothing is deleted. It may come from a newer version of \(BuildVariant.appName)."
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Show in Finder")
        if alert.runModal() == .alertSecondButtonReturn {
            NSWorkspace.shared.activateFileViewerSelecting([kept])
        }
    }

    /// A save ended (`SessionManager.saveNow`). A failure (a full disk, a folder that isn't
    /// writable) leaves changes since the last good save only in memory: told once per run of
    /// failures, since every change retries the save and would ask again each time.
    static func saved(failure error: (any Error)?) {
        guard let error else {
            failing = false
            return
        }
        guard !failing else { return }
        failing = true
        // Later, off the save's own call: it can run while Calm quits, and an alert shouldn't
        // hold that up.
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                guard canShow else { return }
                let alert = NSAlert()
                alert.messageText = "Couldn't save your sessions"
                alert.informativeText = "Changes since the last save are only in memory and are lost if \(BuildVariant.appName) quits. "
                    + "\(error.localizedDescription) It tries again at the next change."
                alert.addButton(withTitle: "OK")
                alert.runModal()
            }
        }
    }
}

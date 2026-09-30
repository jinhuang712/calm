import AppKit
import Observation

/// Whether anyone can see Calm's window: on screen and at least partly uncovered, so not
/// minimized, hidden, on another Space or on a sleeping display. Motion that exists only to be
/// seen (an agent's mark while it works, the light crossing "Working") holds still while it
/// isn't: every frame of it redraws the sidebar, about 2% of a core per working card (measured
/// 2026-09-30), and agents often work on with nobody looking. Calm only in the background, with
/// its window still in view, keeps moving: a frozen mark would read as a stuck agent.
@MainActor @Observable
final class WindowPresence {
    static let shared = WindowPresence()

    private(set) var isVisible = true

    /// A headless self-test's window is transparent, which counts as occluded; it animates as if
    /// seen, as its panes keep rendering, so snapshots show what a user would.
    nonisolated static func isVisible(_ occlusion: NSWindow.OcclusionState, headless: Bool) -> Bool {
        occlusion.contains(.visible) || headless
    }

    func windowOcclusionDidChange(_ window: NSWindow) {
        #if DEBUG
            if isForcedForTesting {
                return
            }
        #endif
        let visible = Self.isVisible(window.occlusionState, headless: Headless.isOn)
        if visible != isVisible {
            isVisible = visible
        }
    }

    #if DEBUG
        private var isForcedForTesting = false

        /// Self-tests (`calm.window_unseen`, `calm.window_seen`): a headless window never
        /// changes its occlusion, so the check of what an unseen window costs sets it.
        func forceForTesting(visible: Bool) {
            isForcedForTesting = true
            isVisible = visible
        }
    #endif
}

extension MainWindowController {
    // MARK: NSWindowDelegate

    func windowDidChangeOcclusionState(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        WindowPresence.shared.windowOcclusionDidChange(window)
    }
}

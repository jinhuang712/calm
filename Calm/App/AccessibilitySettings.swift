import AppKit

/// The system's display accessibility settings Calm follows (UIUX.md → Accessibility), and
/// applying a change to them without a relaunch.
@MainActor
enum AccessibilitySettings {
    /// Increase Contrast: the chrome's quieter text and lines get stronger, and the terminal keeps
    /// a minimum text contrast (CalmDefaults). Self-tests can force it (`CALM_INCREASE_CONTRAST=1`).
    static var increaseContrast: Bool {
        #if DEBUG
            if ProcessInfo.processInfo.environment["CALM_INCREASE_CONTRAST"] == "1" {
                return true
            }
        #endif
        return NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
    }

    static var reduceMotion: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    private static var observer: NSObjectProtocol?

    /// Reduce Motion and Increase Contrast reach the Ghostty config (the cursor glide, minimum
    /// contrast), so a change reloads it; the chrome follows through the reload.
    static func startObserving() {
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil, queue: .main,
        ) { _ in
            MainActor.assumeIsolated {
                TerminalEngine.shared.reloadConfig(soft: false)
                TerminalWindowManager.shared.controllers.forEach { $0.applyAppearance() }
            }
        }
    }
}

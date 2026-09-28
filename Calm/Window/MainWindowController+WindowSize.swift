import AppKit

/// The window's size across launches (FEATURES.md → F1): AppKit saves the windowed frame, and
/// Calm adds whether the window was left filling the screen.
extension MainWindowController {
    /// Brings the window back as the user left it: the frame AppKit saved, then filling the
    /// screen again if it was left that way.
    func restoreFrame() {
        if window?.frameAutosaveName.isEmpty == false, window?.setFrameUsingName(Self.frameName) != true {
            window?.center()
        }
        if manager.windowWasFilled {
            (window as? CalmWindow)?.fillAsLeft()
        }
        tracksFill = true
    }

    /// Remembers whether the window now fills the screen. AppKit's autosave doesn't: it keeps
    /// the last windowed frame, so a window left zoomed came back at its old size.
    private func noteFill() {
        // Full screen and miniaturizing change the frame without the user having resized it.
        guard tracksFill, let window = window as? CalmWindow,
              !window.styleMask.contains(.fullScreen), !window.isMiniaturized
        else { return }
        manager.windowFillDidChange(window.isFilled)
    }

    // MARK: NSWindowDelegate

    func windowDidResize(_: Notification) {
        noteFill()
    }

    func windowDidMove(_: Notification) {
        noteFill()
    }
}

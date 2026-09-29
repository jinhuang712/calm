import AppKit

/// The window's size across launches (FEATURES.md → F1): AppKit saves the windowed frame, and
/// Calm adds whether the window was left filling the screen, or in full screen.
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
        tracksWindowState = true
    }

    /// Enters full screen again if the window was left there, once it is on screen. The window
    /// under it is the one `restoreFrame` set up, so leaving full screen goes back to it.
    func restoreFullScreen() {
        // A headless run must never take a Space over on the screen of whoever is using the Mac.
        guard manager.windowWasFullScreen, !Headless.isOn,
              window?.styleMask.contains(.fullScreen) == false
        else { return }
        // A turn of the run loop later: the launch activates the app right after opening the window.
        Task { @MainActor [weak self] in
            self?.window?.toggleFullScreen(nil)
        }
    }

    /// Remembers whether the window now fills the screen. AppKit's autosave doesn't: it keeps
    /// the last windowed frame, so a window left zoomed came back at its old size.
    private func noteFill() {
        // Full screen and miniaturizing change the frame without the user having resized it.
        guard tracksWindowState, let window = window as? CalmWindow,
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

    /// Whichever way full screen happens (the menu, the green button, Ghostty's binding), it
    /// ends in this or `windowDidExitFullScreen`.
    func windowDidEnterFullScreen(_: Notification) {
        if tracksWindowState {
            manager.windowFullScreenDidChange(true)
        }
    }

    func windowDidExitFullScreen(_: Notification) {
        if tracksWindowState {
            manager.windowFullScreenDidChange(false)
        }
    }
}

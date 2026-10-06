import AppKit

/// How narrow the window can get (UIUX.md → Layout): the sidebar and the files column as they are,
/// and room for the terminal beside them, never more than the screen holds.
enum WindowMinimum {
    /// The terminal's least room at the standard interface size. With the sidebar shown that makes
    /// 720 pt, half of a 13-inch MacBook Air's screen (1440 or 1470 pt), so two windows still tile
    /// side by side; and the title strip always has room for the find field and the group's mark.
    static let terminalWidth: CGFloat = 400
    static let height: CGFloat = 320

    /// `sidebar` and `files` are their widths as shown (0 when hidden), `scale` the interface size.
    static func width(sidebar: CGFloat, files: CGFloat, scale: CGFloat, screenWidth: CGFloat?) -> CGFloat {
        let width = sidebar + files + terminalWidth * scale
        guard let screenWidth else { return width }
        return min(width, screenWidth)
    }

    /// `frame` widened to `width` when it is narrower, kept on `screen` by moving it left; nil when
    /// it is wide enough already.
    static func widened(_ frame: NSRect, to width: CGFloat, on screen: NSRect?) -> NSRect? {
        guard frame.width < width else { return nil }
        var frame = frame
        frame.size.width = width
        if let screen, frame.maxX > screen.maxX {
            frame.origin.x = max(screen.minX, screen.maxX - width)
        }
        return frame
    }
}

/// The window's size across launches (FEATURES.md → F1): AppKit saves the windowed frame, and
/// Calm adds whether the window was left filling the screen, or in full screen.
extension MainWindowController {
    /// Sets the window's narrowest to what the sidebar and the files column take now, plus the
    /// terminal's room, and widens a window that is narrower than that: a panel opening, a larger
    /// interface size, or a saved frame from before there was a minimum. Called from inside a
    /// panel's layout animation, the widening moves with the panel.
    func updateMinimumSize() {
        guard let window, let sidebarWidth else { return }
        // Before the window is first on screen it has no screen; the main one is where it opens.
        let screen = (window.screen ?? NSScreen.main)?.visibleFrame
        let width = WindowMinimum.width(
            sidebar: sidebarWidth.constant, files: filesColumn.shownWidth,
            scale: InterfaceScale.shared.factor, screenWidth: screen?.width,
        )
        window.minSize = NSSize(width: width, height: WindowMinimum.height)
        // Full screen has the whole screen already, and can't be resized.
        guard !window.styleMask.contains(.fullScreen),
              let frame = WindowMinimum.widened(window.frame, to: width, on: screen)
        else { return }
        window.setFrame(frame, display: true)
    }

    func windowDidChangeScreen(_: Notification) {
        updateMinimumSize()
    }

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

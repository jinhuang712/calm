import AppKit

/// What double-clicking a window's title bar does, from System Settings → Desktop & Dock
/// (`AppleActionOnDoubleClick`; unset means Zoom).
enum TitleBarDoubleClick: Equatable {
    case zoom, fill, minimize, nothing

    init(setting: String?) {
        switch setting {
        case "Minimize": self = .minimize
        case "None": self = .nothing
        case "Fill": self = .fill
        default: self = .zoom // "Maximize", and the default
        }
    }
}

/// Calm's main window. Calm draws its own content under the transparent title bar (the
/// sidebar, the strip above the terminal), so a double-click there reaches Calm's views, not
/// the title bar, and AppKit never zooms. The window does it instead, the way the user set it.
final class CalmWindow: NSWindow {
    /// The strip at the top that stands in for the title bar (WindowStyle leaves it above the
    /// terminal area): a header row of its own for the session title, below the traffic lights'
    /// line. The sidebar leaves the same room above its search field, so the two start level.
    static let titleStripHeight: CGFloat = 48

    private var frameBeforeFill: NSRect?

    override func sendEvent(_ event: NSEvent) {
        // The second click of a double-click; the first went through as usual (it can start a
        // window drag).
        if event.type == .leftMouseDown, event.clickCount == 2, isInTitleStrip(event), !styleMask.contains(.fullScreen) {
            performTitleBarDoubleClick()
            return
        }
        super.sendEvent(event)
    }

    private func isInTitleStrip(_ event: NSEvent) -> Bool {
        let titleBar = max(Self.titleStripHeight, frame.height - contentLayoutRect.height)
        guard event.locationInWindow.y >= frame.height - titleBar, let frameView = contentView?.superview else { return false }
        // Controls there (the traffic lights, a viewer's buttons) keep their clicks.
        let hit = frameView.hitTest(frameView.convert(event.locationInWindow, from: nil))
        // The title's ⋯ button only answers a hit over itself (SessionTitleHost).
        var view = hit
        while let current = view {
            if current is SessionTitleHost {
                return false
            }
            view = current.superview
        }
        return !(hit is NSControl)
    }

    func performTitleBarDoubleClick() {
        switch TitleBarDoubleClick(setting: UserDefaults.standard.string(forKey: "AppleActionOnDoubleClick")) {
        case .zoom: performZoom(nil)
        case .minimize: performMiniaturize(nil)
        case .fill: fill()
        case .nothing: break
        }
    }

    /// Fill has no public API: the window takes the screen's usable area, and the next
    /// double-click gives it back its size, as macOS does.
    private func fill() {
        guard let screen else { return }
        if let previous = frameBeforeFill, frame.equalTo(screen.visibleFrame) {
            frameBeforeFill = nil
            setFrame(previous, display: true, animate: true)
        } else {
            frameBeforeFill = frame
            setFrame(screen.visibleFrame, display: true, animate: true)
        }
    }

    // MARK: Filled windows

    /// Whether `frame` covers the screen's usable area: what Zoom, Fill and a window manager's
    /// maximize all leave behind. A point of slack, since they round.
    static func isFilled(frame: NSRect, in visibleFrame: NSRect) -> Bool {
        abs(frame.minX - visibleFrame.minX) <= 1 && abs(frame.minY - visibleFrame.minY) <= 1
            && abs(frame.width - visibleFrame.width) <= 1 && abs(frame.height - visibleFrame.height) <= 1
    }

    var isFilled: Bool {
        screen.map { Self.isFilled(frame: frame, in: $0.visibleFrame) } ?? false
    }

    /// Fills the screen again on a relaunch, from the frame the window has now (AppKit's saved,
    /// windowed one; a zoomed window leaves it as it was). A window that opened already filled
    /// has no size for Zoom or Fill to go back to: `zoom` records it for Zoom, and
    /// `frameBeforeFill` for Fill.
    func fillAsLeft() {
        guard !isFilled else { return }
        frameBeforeFill = frame
        zoom(nil)
    }
}

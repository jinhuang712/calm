/// Whether a pane draws frames: only while its layout is the one on screen and its window can
/// be seen. The two change separately (a session switch; the window covered, minimized or on
/// another Space), so they are kept apart. With one flag for both, the window coming back into
/// view woke every hidden session's pane, and each allocated full-size frames: about 2 GB at
/// once with eight sessions open (measured 2026-09-30), and hidden panes rendering until the
/// next session switch.
struct PaneVisibility: Equatable {
    /// The pane's layout is the one on screen (or the session switcher is showing it).
    var isShown = true
    /// The window is at least partly visible.
    var isWindowVisible = true

    var drawsFrames: Bool {
        isShown && isWindowVisible
    }

    /// Applies a change; returns the new `drawsFrames` when it changed, nil when it didn't.
    mutating func update(_ change: (inout Self) -> Void) -> Bool? {
        let before = drawsFrames
        change(&self)
        return drawsFrames == before ? nil : drawsFrames
    }
}

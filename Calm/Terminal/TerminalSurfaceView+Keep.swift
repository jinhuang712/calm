import AppKit
import CalmModel
import GhosttyKit

/// What a full-screen program showed in this pane, for find's whole session (FEATURES.md → F16,
/// DESIGNS.md → Find). The screen is read at most every `keepInterval` while the program draws:
/// after a frame while the pane is shown, and on a timer while it's hidden and its session works
/// (a hidden pane draws no frames, and an agent there still shows lines). Nothing runs at rest or
/// in a plain shell.
@MainActor
final class PaneKeep {
    /// What was kept, in memory only: it goes with the pane.
    fileprivate(set) var keeper = ScreenKeeper()
    /// Whether the pane's session works (the sidebar's *working*), told by the session manager.
    fileprivate(set) var isSessionWorking = false
    fileprivate var isPending = false
    /// Whether the last read found the program's screen (the alternate one).
    fileprivate var isFullScreen = false
    /// Reads put off in a row because the program was halfway through a frame.
    fileprivate var waits = 0
}

extension TerminalSurfaceView {
    /// How often the screen is read while a program draws: enough for an answer streaming in, few
    /// enough to cost little (the perf scenarios `fullscreen` and `fullscreen-unseen` hold it to
    /// their budgets; a read is about 0.5 ms in the Debug build).
    static let keepInterval: TimeInterval = 0.2

    /// What the pane's full-screen programs showed.
    var kept: ScreenKeeper {
        keep.keeper
    }

    /// Whether the pane renders: shown in the layout on screen, in a window that can be seen.
    var drawsFrames: Bool {
        visibility.drawsFrames
    }

    /// A frame was drawn: a full-screen program may have shown something new. (A read of the
    /// screen's kind is a lock and a flag; in a plain shell nothing more happens.)
    func keepAfterFrame() {
        guard let surface, keep.isFullScreen || ghostty_surface_alternate_screen(surface) else { return }
        scheduleKeep(after: Self.keepInterval)
    }

    /// The session started or stopped working; a hidden pane reads its screen only while it works.
    func setSessionWorking(_ working: Bool) {
        guard working != keep.isSessionWorking else { return }
        keep.isSessionWorking = working
        if working, !drawsFrames {
            scheduleKeep(after: Self.keepInterval)
        }
    }

    /// The pane was hidden or shown.
    func keepVisibilityDidChange() {
        if !drawsFrames, keep.isSessionWorking {
            scheduleKeep(after: Self.keepInterval)
        }
    }

    private func scheduleKeep(after delay: TimeInterval) {
        guard !keep.isPending else { return }
        keep.isPending = true
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            MainActor.assumeIsolated { self?.keepScreen() }
        }
    }

    private func keepScreen() {
        keep.isPending = false
        guard let surface else { return }
        guard ghostty_surface_alternate_screen(surface) else {
            // Back to the shell's screen: the program's last view is kept.
            if keep.isFullScreen {
                keep.isFullScreen = false
                keep.keeper.finish()
            }
            return
        }
        // The pty's output reaches the screen a kilobyte at a time, so a big frame is half drawn
        // until the program ends its synchronized update (engine patch 0021); a half-drawn frame
        // would read as a new view. A program that never ends one is read after a few tries.
        if ghostty_surface_synchronized_update(surface), keep.waits < 10 {
            keep.waits += 1
            scheduleKeep(after: 0.02)
            return
        }
        keep.waits = 0
        keep.isFullScreen = true
        let size = ghostty_surface_size(surface)
        let height = Int(size.rows)
        // One read for the screen: soft-wrapped rows come joined (rare on a program's own
        // screen), so the lines are padded to the screen's height, where the keeper compares them.
        var rows = (viewportText() ?? "").split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        rows = Array(rows.prefix(height)) + Array(repeating: "", count: max(0, height - rows.count))
        keep.keeper.see(rows, columns: Int(size.columns), at: Date())
        if !drawsFrames, keep.isSessionWorking {
            scheduleKeep(after: Self.keepInterval)
        }
    }

    /// The shell's screen and its scrollback, which stay behind a full-screen program (engine
    /// patch 0020): the shell's output before the program, for the whole session.
    func primaryScreenText() -> String? {
        guard let surface else { return nil }
        var text = ghostty_text_s()
        let selection = ghostty_selection_s(
            top_left: ghostty_point_s(tag: GHOSTTY_POINT_SCREEN, coord: GHOSTTY_POINT_COORD_TOP_LEFT, x: 0, y: 0),
            bottom_right: ghostty_point_s(tag: GHOSTTY_POINT_SCREEN, coord: GHOSTTY_POINT_COORD_BOTTOM_RIGHT, x: 0, y: 0),
            rectangle: false,
        )
        guard ghostty_surface_read_primary_text(surface, selection, &text) else { return nil }
        defer { ghostty_surface_free_text(surface, &text) }
        guard let pointer = text.text else { return nil }
        return String(bytes: UnsafeRawBufferPointer(start: pointer, count: Int(text.text_len)), encoding: .utf8)
    }
}

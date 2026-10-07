import AppKit
import CalmModel
import GhosttyKit

/// Where the screen is in the scrollback, in rows, as libghostty reports it for a scroll bar.
struct ScrollbackPosition: Equatable {
    let total: Int
    let offset: Int
    let visible: Int

    /// Whether the newest rows are on screen (always, for a full-screen program).
    var isAtBottom: Bool {
        offset + visible >= total
    }
}

/// One pane's find marks (FEATURES.md → F16, FindMarksView): the matches on screen and which one
/// is current. libghostty searches and draws the current match's pill, but tells the app only the
/// count and the current match's number, so the pane finds the matches on screen itself, as the
/// engine matches them (`FindMatcher`), and works out which one the number is (DESIGNS.md → Find).
@MainActor
final class PaneFind {
    /// Called when the marks change, so the overlay can redraw.
    var onChange: (() -> Void)?
    /// The words searched in this pane, while find is open on it with some.
    fileprivate(set) var words: String?
    /// libghostty's current match, counted from the newest (0).
    fileprivate(set) var selected: Int?
    /// The matches on screen, top to bottom, each as its cells, one run per row.
    fileprivate(set) var matches: [[CellRun]] = []
    /// Which of `matches` is the current one: its line gets the band and the edge bar.
    fileprivate(set) var current: Int?
    /// Where the grid starts and where the text's baseline sits in a cell, when the marks were found.
    fileprivate(set) var geometry: (origin: NSPoint, baseline: CGFloat)?
    /// The last change was a step to another match on a still screen, so the band slides there;
    /// any other change (the screen scrolled, output came, new words) places it at once.
    fileprivate(set) var slides = false
    /// Where the screen is in the scrollback (`GHOSTTY_ACTION_SCROLLBAR`).
    fileprivate(set) var position: ScrollbackPosition?
    fileprivate var isRefreshPending = false
    fileprivate var rows: [String] = []
    /// The scroll position's offset last seen, to tell a scroll from output arriving.
    fileprivate var lastOffset: Int?
    /// The background the marks were drawn on: a new appearance redraws them in its colors.
    fileprivate var background: NSColor?
    /// The matches from the top of the screen to the newest row, for the words and position they
    /// were counted at: the screen's own and those below it, when it's scrolled up.
    fileprivate var counted: Counted?

    fileprivate struct Counted {
        let words: String
        let position: ScrollbackPosition?
        let count: Int
    }

    /// Whether the pane showed a full-screen program's screen when find last looked; nil before
    /// a search has looked, so each new one reports it.
    fileprivate var isFullScreen: Bool?
    /// Every line of the scrollback with a match, for the map (TerminalSurfaceView+FindMap).
    var map: FindMap?
    /// Bumped by each scan, so a scan the words have moved past is dropped.
    var mapGeneration = 0
    var isMapScanPending = false
}

extension TerminalSurfaceView {
    /// The colors the pane shows: its own config once libghostty has sent one, else the app's,
    /// which libghostty keeps resolved for the current appearance (as the window's chrome reads it).
    var shownConfig: TerminalConfig? {
        config ?? TerminalEngine.shared.config
    }

    /// How soon after a frame the matches are looked for again: soon enough to keep up with
    /// scrolling, without reading the screen on every frame of fast output.
    private static let findRefreshDelay: TimeInterval = 0.05

    /// A new frame: the text may have moved under the link and find marks.
    func frameDidChange() {
        scheduleLinkScan()
        guard find.words != nil else { return }
        followFindGrid()
        scheduleFindRefresh()
    }

    /// The marks ride with the grid on every frame while smooth scrolling slides it, before the
    /// text is read again (a refresh is too late for a moving screen). Only the grid's position
    /// is read, which is cheap; at rest it doesn't move, and nothing is redrawn.
    private func followFindGrid() {
        guard !find.matches.isEmpty, let geometry = gridGeometry(),
              geometry.origin != find.geometry?.origin || geometry.baseline != find.geometry?.baseline else { return }
        find.geometry = geometry
        find.slides = false
        find.onChange?()
    }

    /// What find marks in this pane (`FindTarget`): the words, or nil for none, and the current match.
    func markFind(_ words: String?, selected: Int?) {
        let isNew = words != find.words
        let moved = selected != find.selected
        if isNew {
            find.rows = []
            find.counted = nil
            find.map = nil
            find.isFullScreen = nil
        }
        find.words = words
        find.selected = selected
        guard words != nil else {
            find.matches = []
            find.current = nil
            find.onChange?()
            return
        }
        if isNew {
            // After a short pause in typing: each scan reads the whole scrollback.
            scheduleMapScan(after: 0.15)
        } else if moved {
            find.onChange?() // the map's current tick, wherever the match is
        }
        scheduleFindRefresh(after: 0)
    }

    func scrollPositionDidChange(_ position: ScrollbackPosition) {
        guard position != find.position else { return }
        let grew = position.total != find.position?.total
        find.position = position
        guard find.words != nil else { return }
        // The screen moved: read its rows at once, so the marks ride with the text from its first frame.
        scheduleFindRefresh(after: position.offset != find.lastOffset ? 0 : Self.findRefreshDelay)
        find.lastOffset = position.offset
        if grew {
            scheduleMapScan(after: 1) // new output: at most a scan a second
        }
        find.onChange?() // the map's box
    }

    /// Forgets where the marks were (the cells moved: a new font size, a pane growing) and looks again.
    func resetFindMarks() {
        guard find.words != nil else { return }
        find.rows = []
        find.matches = []
        find.current = nil
        find.onChange?()
        scheduleFindRefresh()
    }

    private func scheduleFindRefresh(after delay: TimeInterval = findRefreshDelay) {
        guard !find.isRefreshPending else { return }
        find.isRefreshPending = true
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            MainActor.assumeIsolated { self?.refreshFind() }
        }
    }

    private func refreshFind() {
        find.isRefreshPending = false
        guard let words = find.words, window != nil else { return }
        reportFindScreen()
        guard let geometry = gridGeometry() else { return }
        let rows = viewportRows()
        let still = rows == find.rows && geometry.origin == find.geometry?.origin
        var matches = find.matches
        if rows != find.rows {
            find.rows = rows
            let grid = TextGrid(lines: rows)
            matches = lines(of: grid).flatMap { FindMatcher.matches(of: words, in: grid, rows: $0) }
        }
        let current = currentMatch(words: words, among: matches)
        // The marks follow the grid too: smooth scrolling shifts it by pixels.
        let moved = geometry.origin != find.geometry?.origin || geometry.baseline != find.geometry?.baseline
        let background = effectiveBackgroundColor ?? shownConfig?.backgroundColor
        guard matches != find.matches || current != find.current || moved || background != find.background else { return }
        find.slides = still && current != find.current && find.current != nil && current != nil
        find.matches = matches
        find.current = current
        find.geometry = geometry
        find.background = background
        find.onChange?()
    }

    /// Tells find when the pane starts or stops showing a full-screen program's screen (the
    /// alternate one, which keeps no scrollback): its count then says "on screen", and a note
    /// explains when nothing there matches. libghostty reports which screen is shown only when
    /// asked (engine patch 0018), so the pane asks each time it looks at its matches.
    private func reportFindScreen() {
        guard let surface else { return }
        let isFullScreen = ghostty_surface_alternate_screen(surface)
        guard isFullScreen != find.isFullScreen else { return }
        find.isFullScreen = isFullScreen
        host?.surface(self, didFind: .fullScreen(isFullScreen))
    }

    /// Which match on screen is libghostty's current one. Its number counts from the newest match,
    /// so it's the matches from the top of the screen down to the newest row, counted backwards:
    /// at the bottom those are the screen's own; scrolled up, the rows below are read and counted
    /// too (only when the words or the position changed).
    private func currentMatch(words: String, among matches: [[CellRun]]) -> Int? {
        guard let selected = find.selected else { return nil }
        let position = find.position
        let count: Int
        if position?.isAtBottom ?? true {
            count = matches.count
        } else if let counted = find.counted, counted.words == words, counted.position == position {
            count = counted.count
        } else {
            // From the screen's top-left to the scrollback's last row, wrapped lines joined, as the
            // engine reads them. A match can't cross a line's end: the words have none.
            let text = readText(ghostty_selection_s(
                top_left: ghostty_point_s(tag: GHOSTTY_POINT_VIEWPORT, coord: GHOSTTY_POINT_COORD_TOP_LEFT, x: 0, y: 0),
                bottom_right: ghostty_point_s(tag: GHOSTTY_POINT_SCREEN, coord: GHOSTTY_POINT_COORD_BOTTOM_RIGHT, x: 0, y: 0),
                rectangle: false,
            )) ?? ""
            count = FindMatcher.count(of: words, in: text)
            find.counted = PaneFind.Counted(words: words, position: position, count: count)
        }
        let index = count - 1 - selected
        return matches.indices.contains(index) ? index : nil
    }
}

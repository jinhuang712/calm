import AppKit
import CalmModel
import GhosttyKit

/// Find's map (FEATURES.md → F16, FindMapView): every line of the scrollback with a match. Calm
/// searches the scrollback itself, since libghostty tells the app where no match is
/// (DESIGNS.md → Find): one read of all of it, scanned off the main thread.
extension TerminalSurfaceView {
    /// Whether the map shows: matches somewhere, and more log than the screen holds. A full-screen
    /// program's screen has no scrollback, so it never has one.
    var showsFindMap: Bool {
        guard find.words != nil, let map = find.map, !map.lines.isEmpty, let position = find.position else { return false }
        return position.total > position.visible
    }

    /// The map's line holding the current match.
    var findMapCurrentLine: Int? {
        find.selected.flatMap { find.map?.line(holding: $0) }
    }

    func scheduleMapScan(after delay: TimeInterval) {
        guard !find.isMapScanPending else { return }
        find.isMapScanPending = true
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            MainActor.assumeIsolated { self?.scanMap() }
        }
    }

    /// Reads the whole scrollback (libghostty holds the terminal's lock for it: about 6 ms for
    /// 10,000 lines, 24 ms for the 44,000 its default limit keeps) and scans it off the main thread.
    private func scanMap() {
        find.isMapScanPending = false
        guard let words = find.words, let query = find.query, let surface, window != nil else { return }
        let columns = Int(ghostty_surface_size(surface).columns)
        let text = readText(ghostty_selection_s(
            top_left: ghostty_point_s(tag: GHOSTTY_POINT_SCREEN, coord: GHOSTTY_POINT_COORD_TOP_LEFT, x: 0, y: 0),
            bottom_right: ghostty_point_s(tag: GHOSTTY_POINT_SCREEN, coord: GHOSTTY_POINT_COORD_BOTTOM_RIGHT, x: 0, y: 0),
            rectangle: false,
        )) ?? ""
        find.mapGeneration += 1
        let generation = find.mapGeneration
        Task.detached(priority: .utility) { [weak self] in
            let map = FindMap.scan(text, query: query, columns: columns)
            await MainActor.run {
                guard let self else { return }
                let find = self.find
                guard find.mapGeneration == generation, find.words == words else { return }
                // A pattern's count is the pane's own: libghostty searches plain words only.
                if find.isPattern {
                    self.keepPatternMatch(count: map.matches, before: find.map?.matches)
                    self.host?.surface(self, didFind: .counted(map.matches))
                }
                guard map != find.map else { return }
                find.map = map
                find.onChange?()
            }
        }
    }

    /// A click on the map's tick for `line`: its first match becomes the current one, by stepping
    /// there through the engine, which scrolls it into view.
    func goToFindLine(_ line: Int) {
        guard let target = find.map?.selection(of: line) else { return }
        if find.isPattern {
            // A pattern's matches are find's own: it makes the choice and the pane goes there.
            host?.surface(self, didFind: .chose(target))
            return
        }
        // No current match yet: the first step older selects the newest (index 0).
        let steps = target - (find.selected ?? -1)
        let action = steps > 0 ? "navigate_search:next" : "navigate_search:previous"
        for _ in 0 ..< abs(steps) {
            perform(action)
        }
    }
}

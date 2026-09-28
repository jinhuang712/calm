import AppKit
import CalmModel
import GhosttyKit

/// A link under the pointer while ⌘ is held (FEATURES.md → F8): what libghostty would open, and
/// the cells it covers.
struct LinkHover: Equatable {
    /// libghostty's text for it: the matched text, or an OSC 8 link's URL.
    let text: String
    /// Its cells, one run per row; `anchor` is the run under the pointer.
    let runs: [CellRun]
    let anchor: CellRun

    func overlaps(_ match: LinkMatch) -> Bool {
        runs.contains { match.overlaps(row: $0.row, columns: $0.columns) }
    }
}

/// One pane's links: those marked at rest, and the one under ⌘.
@MainActor
final class PaneLinks {
    /// Called when the marks or the hovered link change, so the overlay can redraw.
    var onChange: (() -> Void)?
    /// The links that open, each with its cells' rectangles in the pane (one per row it's on).
    fileprivate(set) var marks: [LinkMatch: [NSRect]] = [:] {
        didSet {
            if marks != oldValue {
                onChange?()
            }
        }
    }

    fileprivate(set) var hovered: LinkHover? {
        didSet {
            if hovered != oldValue {
                onChange?()
            }
        }
    }

    /// Where the pointer is in the pane, while it's over it.
    var pointer: NSPoint?
    fileprivate var rows: [String] = []
    fileprivate var isSettled = false
    fileprivate var isScanPending = false
}

/// Links at rest and under ⌘ (FEATURES.md → F8). libghostty marks a link only while ⌘ is held
/// (its `link` setting can't be set yet), so Calm finds the links in the visible text itself, with
/// libghostty's own pattern (LinkMatcher), and marks each one that opens (LinkMarksView). It looks
/// again only once the text holds still, so marks never trail moving text: rows that change lose
/// their marks at once, and the marks come back when the text rests.
extension TerminalSurfaceView {
    /// How long the text must hold still before its links are marked.
    private static let settleDelay: TimeInterval = 0.3
    /// Enough for any screen; a screen of nothing but paths stops here.
    private static let markLimit = 300

    func scheduleLinkScan(after delay: TimeInterval = 0.1) {
        guard !links.isScanPending else { return }
        links.isScanPending = true
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            MainActor.assumeIsolated { self?.scanLinks() }
        }
    }

    /// Forgets the marks (the cells moved: a new font size, a pane growing) and looks again.
    func resetLinkMarks() {
        links.rows = []
        links.isSettled = false
        links.marks = [:]
        scheduleLinkScan()
    }

    private func scanLinks() {
        links.isScanPending = false
        guard let surface, window != nil, !isHiddenOrHasHiddenAncestor else { return }
        // A program that takes the mouse (vim, htop) gets the clicks, so ⌘-click opens nothing there.
        guard !ghostty_surface_mouse_captured(surface) else {
            links.rows = []
            links.marks = [:]
            return
        }
        let rows = viewportRows()
        guard rows == links.rows else {
            let old = links.rows
            let unchanged = { (run: CellRun) in
                old.indices.contains(run.row) && rows.indices.contains(run.row) && old[run.row] == rows[run.row]
            }
            links.marks = links.marks.filter { $0.key.runs.allSatisfy(unchanged) }
            if let hovered = links.hovered, !hovered.runs.allSatisfy(unchanged) {
                setLinkHover(nil) // the text under it moved
            }
            links.rows = rows
            links.isSettled = false
            scheduleLinkScan(after: Self.settleDelay)
            return
        }
        guard !links.isSettled else { return }
        links.isSettled = true
        links.marks = openableLinks(in: rows)
    }

    /// The links in `rows` that lead somewhere (a URL, or a file that's there), with their rectangles.
    private func openableLinks(in rows: [String]) -> [LinkMatch: [NSRect]] {
        guard let origin = gridOrigin() else { return [:] }
        let grid = TextGrid(lines: rows)
        var opens: [String: Bool] = [:]
        var marks: [LinkMatch: [NSRect]] = [:]
        for line in lines(of: grid) {
            for match in LinkMatcher.matches(in: grid, rows: line) {
                guard marks.count < Self.markLimit else { return marks }
                // The longest text that opens, as ⌘-click tries it.
                for candidate in Link.candidates(for: match.text) {
                    let leads = opens[candidate] ?? (host?.surface(self, resolveLink: candidate) != nil)
                    opens[candidate] = leads
                    if leads {
                        let mark = match.prefix(candidate.count)
                        marks[mark] = mark.runs.compactMap { rect(row: $0.row, columns: $0.columns, origin: origin) }
                        break
                    }
                }
            }
        }
        return marks
    }

    /// The screen's rows grouped into its lines: a line longer than the pane wraps onto the rows
    /// below, and libghostty matches links across that wrap, so Calm does too.
    private func lines(of grid: TextGrid) -> [Range<Int>] {
        guard let surface else { return [] }
        let columns = Int(ghostty_surface_size(surface).columns)
        var lines: [Range<Int>] = []
        var start = 0
        for row in grid.cells.indices {
            // Only a full row can wrap (a wide character that didn't fit leaves the last cell empty).
            let full = grid.cells[row].count >= columns - 1
            if !(full && row + 1 < grid.cells.count && wraps(row, columns: columns)) {
                lines.append(start ..< row + 1)
                start = row + 1
            }
        }
        return lines
    }

    /// Whether `row` goes on in the next row: read as one selection, the two rows have no line
    /// break between them only when the terminal wrapped one line there.
    private func wraps(_ row: Int, columns: Int) -> Bool {
        let text = readText(ghostty_selection_s(
            top_left: ghostty_point_s(tag: GHOSTTY_POINT_VIEWPORT, coord: GHOSTTY_POINT_COORD_EXACT, x: 0, y: UInt32(row)),
            bottom_right: ghostty_point_s(
                tag: GHOSTTY_POINT_VIEWPORT,
                coord: GHOSTTY_POINT_COORD_EXACT,
                x: UInt32(columns - 1),
                y: UInt32(row + 1),
            ),
            rectangle: false,
        ))
        return text.map { !$0.contains("\n") } ?? false
    }

    /// libghostty's MOUSE_OVER_LINK: the ⌘-hovered link's text, or nil when the pointer leaves it.
    /// It arrives while libghostty holds its renderer lock, which reading the screen takes too, so
    /// the rest waits for the next turn of the main loop.
    func linkHoverDidChange(_ text: String?) {
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated { self?.updateLinkHover(text) }
        }
    }

    private func updateLinkHover(_ text: String?) {
        guard let text, !text.isEmpty, let pointer = links.pointer, let cell = cell(at: pointer) else {
            setLinkHover(nil)
            return
        }
        // Where the link starts and ends: libghostty says what it is, not where.
        let grid = TextGrid(lines: viewportRows())
        let line = lines(of: grid).first { $0.contains(cell.row) } ?? cell.row ..< cell.row + 1
        let match = LinkMatcher.matches(in: grid, rows: line).first { $0.covers(row: cell.row, column: cell.column) }
        let under = CellRun(row: cell.row, columns: cell.column ..< cell.column + 1)
        let runs = match?.runs ?? [under]
        setLinkHover(LinkHover(text: text, runs: runs, anchor: runs.first { $0.row == cell.row } ?? under))
    }

    private func setLinkHover(_ hover: LinkHover?) {
        guard hover != links.hovered else { return }
        links.hovered = hover
        host?.surface(self, hoversLink: hover)
    }
}

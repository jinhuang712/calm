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
    /// A link libghostty doesn't know whole, so the pane found it itself and draws its underline and
    /// cursor, and takes its ⌘-click: one a program cut across rows (`HardWrap`), of which
    /// libghostty sees only pieces, or an agent's tag for a pasted image, which it doesn't see at all.
    var isCalmOwned = false
    /// The number in an agent's tag for a pasted image (`[Image #4]`), when that's what this is.
    var pastedImage: Int?

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

    /// The table cell under the pointer while ⌥ is held (Copy Cell, FEATURES.md → F9), in the
    /// pane's coordinates; the same overlay draws it.
    var cellOutline: NSRect? {
        didSet {
            if cellOutline != oldValue {
                onChange?()
            }
        }
    }

    /// The grid cell the outline was last looked up for, so moving within a cell reads nothing.
    var cellOutlineProbe: CellRun?

    /// What an ⌥-drag inside a table cell selects, one rectangle per line, in the pane's
    /// coordinates; drawn by the same overlay, since libghostty never saw the drag.
    var cellSelection: [NSRect] = [] {
        didSet {
            if cellSelection != oldValue {
                onChange?()
            }
        }
    }

    /// Where the pointer is in the pane, while it's over it.
    var pointer: NSPoint?
    /// Whether ⌘ is down, as the last pointer or modifier event said (`NSEvent.modifierFlags` doesn't
    /// follow the events the self-tests send).
    var isCommandDown = false
    /// The cell last checked for a link a program cut across rows, so the pointer moving inside one
    /// cell doesn't read the screen again.
    fileprivate var joinedCheck: CellRun?
    fileprivate var rows: [String] = []
    /// The screen's rows when the hovered link was found, for a program that takes the mouse (its
    /// screen is redrawn while the pointer rests, and libghostty looks again only on the next move).
    fileprivate var hoverRows: [String] = []
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
        // A program that takes the mouse (vim, htop, an agent's full-screen view) has no resting marks:
        // its screen is redrawn too often for them to hold still. ⌘ still opens its links (engine
        // patch 0011), so the hovered one stays only as long as its text does.
        guard !ghostty_surface_mouse_captured(surface) else {
            links.rows = []
            links.marks = [:]
            if let hovered = links.hovered {
                let rows = viewportRows()
                let unchanged = hovered.runs.allSatisfy { run in
                    links.hoverRows.indices.contains(run.row) && rows.indices.contains(run.row)
                        && links.hoverRows[run.row] == rows[run.row]
                }
                if !unchanged {
                    dropLinkHover() // the text under it moved
                }
            }
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
                dropLinkHover() // the text under it moved
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
        let lines = lines(of: grid)
        var opens: [String: Bool] = [:]
        var marks: [LinkMatch: [NSRect]] = [:]
        // A word a program cut across rows comes first: the pieces of it on each row aren't links.
        var joined: [LinkMatch] = []
        for group in joinedRows(in: grid, lines: lines) {
            for match in LinkMatcher.matches(in: grid, rows: group.rows, continuations: group.continuations) where group.crosses(match) {
                guard let mark = openable(match, opens: &opens), group.crosses(mark) else { continue }
                joined.append(mark)
                marks[mark] = mark.runs.compactMap { rect(row: $0.row, columns: $0.columns, origin: origin) }
            }
        }
        for line in lines {
            for match in LinkMatcher.matches(in: grid, rows: line) {
                guard marks.count < Self.markLimit else { return marks }
                guard let mark = openable(match, opens: &opens),
                      !joined.contains(where: { piece in mark.runs.contains { piece.overlaps(row: $0.row, columns: $0.columns) } })
                else { continue }
                marks[mark] = mark.runs.compactMap { rect(row: $0.row, columns: $0.columns, origin: origin) }
            }
        }
        markPastedImageTags(in: grid, lines: lines, origin: origin, marks: &marks)
        return marks
    }

    /// The agent's tags for pasted images whose images are there, added to `marks`.
    private func markPastedImageTags(in grid: TextGrid, lines: [Range<Int>], origin: NSPoint, marks: inout [LinkMatch: [NSRect]]) {
        guard let pattern = host?.pastedImagePattern(for: self) else { return }
        var found: [Int: Bool] = [:]
        for line in lines {
            for tag in LinkMatcher.matches(of: pattern, in: grid, rows: line) {
                guard marks.count < Self.markLimit else { return }
                guard let number = Self.pastedImageNumber(in: tag.text, pattern: pattern) else { continue }
                let isThere = found[number] ?? (host?.surface(self, pastedImage: number) != nil)
                found[number] = isThere
                if isThere {
                    marks[tag] = tag.runs.compactMap { rect(row: $0.row, columns: $0.columns, origin: origin) }
                }
            }
        }
    }

    /// The longest text of `match` that opens, as ⌘-click tries it, cut to those cells; nil when none does.
    private func openable(_ match: LinkMatch, opens: inout [String: Bool]) -> LinkMatch? {
        for candidate in Link.candidates(for: match.text) {
            let leads = opens[candidate] ?? (host?.surface(self, resolveLink: candidate) != nil)
            opens[candidate] = leads
            if leads {
                return match.prefix(candidate.count)
            }
        }
        return nil
    }

    /// The lines a program carried on into the next row by itself (`HardWrap`).
    private func joinedRows(in grid: TextGrid, lines: [Range<Int>]) -> [HardWrap.Joined] {
        guard let surface else { return [] }
        return HardWrap.joined(grid, lines: lines, columns: Int(ghostty_surface_size(surface).columns))
    }

    /// The link under `cell` that a program cut across rows, and leads somewhere. libghostty joins only
    /// what the terminal wrapped, so a click or hover there gets the piece on one row, or nothing.
    private func joinedLink(at cell: (row: Int, column: Int), rows: [String]) -> LinkMatch? {
        let grid = TextGrid(lines: rows)
        var opens: [String: Bool] = [:]
        for group in joinedRows(in: grid, lines: lines(of: grid)) where group.rows.contains(cell.row) {
            for match in LinkMatcher.matches(in: grid, rows: group.rows, continuations: group.continuations) where group.crosses(match) {
                if let mark = openable(match, opens: &opens), group.crosses(mark), mark.covers(row: cell.row, column: cell.column) {
                    return mark
                }
            }
        }
        return nil
    }

    /// The agent's tag for a pasted image under `cell`, with its number; nil unless the image is there.
    private func pastedImageTag(at cell: (row: Int, column: Int), rows: [String]) -> (tag: LinkMatch, number: Int)? {
        guard let pattern = host?.pastedImagePattern(for: self) else { return nil }
        let grid = TextGrid(lines: rows)
        let line = lines(of: grid).first { $0.contains(cell.row) } ?? cell.row ..< cell.row + 1
        let tags = LinkMatcher.matches(of: pattern, in: grid, rows: line)
        guard let tag = tags.first(where: { $0.covers(row: cell.row, column: cell.column) }),
              let number = Self.pastedImageNumber(in: tag.text, pattern: pattern),
              host?.surface(self, pastedImage: number) != nil
        else { return nil }
        return (tag, number)
    }

    private static func pastedImageNumber(in text: String, pattern: NSRegularExpression) -> Int? {
        let range = NSRange(location: 0, length: (text as NSString).length)
        guard let match = pattern.firstMatch(in: text, range: range), match.numberOfRanges > 1 else { return nil }
        let group = match.range(at: 1)
        return group.location == NSNotFound ? nil : Int((text as NSString).substring(with: group))
    }

    /// A link under `cell` that the pane finds itself (`LinkHover.isCalmOwned`).
    private func calmOwnedHover(at cell: (row: Int, column: Int)) -> LinkHover? {
        let rows = viewportRows()
        if let link = joinedLink(at: cell, rows: rows) {
            links.hoverRows = rows
            let anchor = link.runs.first { $0.row == cell.row } ?? link.runs[0]
            return LinkHover(text: link.text, runs: link.runs, anchor: anchor, isCalmOwned: true)
        }
        if let (tag, number) = pastedImageTag(at: cell, rows: rows) {
            links.hoverRows = rows
            let anchor = tag.runs.first { $0.row == cell.row } ?? tag.runs[0]
            return LinkHover(text: tag.text, runs: tag.runs, anchor: anchor, isCalmOwned: true, pastedImage: number)
        }
        return nil
    }

    /// ⌘-click on a link the pane finds itself opens it whole, before libghostty sees the click.
    /// False when the click isn't on one.
    func openCalmOwnedLink(at point: NSPoint) -> Bool {
        guard let cell = cell(at: point) else { return false }
        let rows = viewportRows()
        if let link = joinedLink(at: cell, rows: rows) {
            setLinkHover(nil)
            host?.surface(self, requestsOpenLink: link.text)
            return true
        }
        if let (_, number) = pastedImageTag(at: cell, rows: rows) {
            setLinkHover(nil)
            host?.surface(self, requestsOpenPastedImage: number)
            return true
        }
        return false
    }

    /// Looks for a link the pane finds itself under ⌘ and the pointer, when either moved. Only when
    /// the cell changes, since it reads the screen.
    func refreshJoinedLinkHover() {
        var pointed: (row: Int, column: Int)?
        if links.isCommandDown, let pointer = links.pointer {
            pointed = cell(at: pointer)
        }
        let checked = pointed.map { CellRun(row: $0.row, columns: $0.column ..< $0.column + 1) }
        guard checked != links.joinedCheck else { return }
        links.joinedCheck = checked
        if let pointed, let hover = calmOwnedHover(at: pointed) {
            setLinkHover(hover)
        } else if links.hovered?.isCalmOwned == true {
            setLinkHover(nil)
        }
    }

    /// The screen's rows grouped into its lines: a line longer than the pane wraps onto the rows
    /// below, and libghostty matches links across that wrap, so Calm does too.
    func lines(of grid: TextGrid) -> [Range<Int>] {
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
        guard let pointer = links.pointer, let cell = cell(at: pointer) else {
            setLinkHover(nil)
            return
        }
        // A link a program cut across rows is Calm's whole, wherever libghostty sees a piece of it; an
        // agent's image tag is Calm's alone. Checked first, since libghostty reports nil over both.
        if links.isCommandDown, let owned = calmOwnedHover(at: cell) {
            setLinkHover(owned)
            return
        }
        guard let text, !text.isEmpty else {
            setLinkHover(nil)
            return
        }
        // Where the link starts and ends: libghostty says what it is, not where.
        let rows = viewportRows()
        links.hoverRows = rows
        let grid = TextGrid(lines: rows)
        let line = lines(of: grid).first { $0.contains(cell.row) } ?? cell.row ..< cell.row + 1
        let match = LinkMatcher.matches(in: grid, rows: line).first { $0.covers(row: cell.row, column: cell.column) }
        let under = CellRun(row: cell.row, columns: cell.column ..< cell.column + 1)
        let runs = match?.runs ?? [under]
        setLinkHover(LinkHover(text: text, runs: runs, anchor: runs.first { $0.row == cell.row } ?? under))
    }

    /// The hovered link's text moved: forget it, and look again on the next pointer move.
    private func dropLinkHover() {
        links.joinedCheck = nil
        setLinkHover(nil)
    }

    private func setLinkHover(_ hover: LinkHover?) {
        guard hover != links.hovered else { return }
        let hadHand = links.hovered?.isCalmOwned == true
        links.hovered = hover
        if hadHand != (hover?.isCalmOwned == true) {
            window?.invalidateCursorRects(for: self) // the hand is Calm's to show for a link libghostty doesn't know whole
        }
        host?.surface(self, hoversLink: hover)
    }
}

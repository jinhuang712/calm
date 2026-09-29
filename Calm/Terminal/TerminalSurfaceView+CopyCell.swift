import AppKit
import CalmModel
import GhosttyKit

/// Reading the grid: its text and where its cells are, for Copy Cell, links and tests.
extension TerminalSurfaceView {
    /// Reads text from the screen.
    func readText(_ selection: ghostty_selection_s) -> String? {
        guard let surface else { return nil }
        var text = ghostty_text_s()
        guard ghostty_surface_read_text(surface, selection, &text) else { return nil }
        defer { ghostty_surface_free_text(surface, &text) }
        guard let pointer = text.text else { return nil }
        return String(bytes: UnsafeRawBufferPointer(start: pointer, count: Int(text.text_len)), encoding: .utf8)
    }

    /// The visible screen as text.
    func viewportText() -> String? {
        readText(ghostty_selection_s(
            top_left: ghostty_point_s(tag: GHOSTTY_POINT_VIEWPORT, coord: GHOSTTY_POINT_COORD_TOP_LEFT, x: 0, y: 0),
            bottom_right: ghostty_point_s(tag: GHOSTTY_POINT_VIEWPORT, coord: GHOSTTY_POINT_COORD_BOTTOM_RIGHT, x: 0, y: 0),
            rectangle: false,
        ))
    }

    /// The visible rows exactly as the grid holds them. One read per row: reading the viewport at
    /// once joins soft-wrapped lines, which would shift every row below them.
    func viewportRows() -> [String] {
        guard let surface else { return [] }
        let size = ghostty_surface_size(surface)
        guard size.columns > 0 else { return [] }
        return (0 ..< Int(size.rows)).map { viewportRow($0) ?? "" }
    }

    /// One visible row exactly as the grid holds it.
    func viewportRow(_ row: Int) -> String? {
        guard let surface, row >= 0 else { return nil }
        let size = ghostty_surface_size(surface)
        guard size.columns > 0, row < Int(size.rows) else { return nil }
        return readText(ghostty_selection_s(
            top_left: ghostty_point_s(tag: GHOSTTY_POINT_VIEWPORT, coord: GHOSTTY_POINT_COORD_EXACT, x: 0, y: UInt32(row)),
            bottom_right: ghostty_point_s(
                tag: GHOSTTY_POINT_VIEWPORT,
                coord: GHOSTTY_POINT_COORD_EXACT,
                x: UInt32(size.columns) - 1,
                y: UInt32(row),
            ),
            rectangle: false,
        ))
    }

    /// Where cell (0,0) starts, in points from the view's top left: the padding.
    ///
    /// libghostty reports a selection's left edge exactly, but for its height the text's baseline
    /// (padding + a cell − the font's baseline, which the API doesn't give). The IME point is the
    /// bottom of the cursor's cell (padding + whole cells), so the top padding is the one value
    /// that is a whole number of cells from it and less than a cell above the baseline. Both
    /// include smooth scrolling's pixel shift (the IME point by the fork's patch 0005, the
    /// baseline by Calm's 0007), so this is where the rows are drawn.
    func gridOrigin() -> NSPoint? {
        guard let surface, cellSize.width > 0, cellSize.height > 0 else { return nil }
        var text = ghostty_text_s()
        let origin = ghostty_point_s(tag: GHOSTTY_POINT_VIEWPORT, coord: GHOSTTY_POINT_COORD_EXACT, x: 0, y: 0)
        guard ghostty_surface_read_text(surface, ghostty_selection_s(top_left: origin, bottom_right: origin, rectangle: false), &text)
        else {
            return nil
        }
        defer { ghostty_surface_free_text(surface, &text) }
        var imeX = 0.0, cursorBottom = 0.0, imeWidth = 0.0, imeHeight = 0.0
        ghostty_surface_ime_point(surface, &imeX, &cursorBottom, &imeWidth, &imeHeight)
        let baseline = text.tl_px_y
        let cells = ((cursorBottom - baseline) / cellSize.height - 0.001).rounded(.up)
        return NSPoint(x: text.tl_px_x, y: cursorBottom - cells * cellSize.height)
    }

    /// The grid cell under a point in this view.
    func cell(at point: NSPoint) -> (row: Int, column: Int)? {
        guard let origin = gridOrigin() else { return nil }
        let x = point.x - origin.x
        let y = bounds.height - point.y - origin.y
        guard x >= 0, y >= 0 else { return nil }
        return (Int(y / cellSize.height), Int(x / cellSize.width))
    }

    /// The rectangle of some cells of a row, in this view's coordinates.
    func rect(row: Int, columns: Range<Int>, origin: NSPoint? = nil) -> NSRect? {
        guard let origin = origin ?? gridOrigin() else { return nil }
        let top = origin.y + CGFloat(row) * cellSize.height
        return NSRect(
            x: origin.x + CGFloat(columns.lowerBound) * cellSize.width,
            y: bounds.height - top - cellSize.height,
            width: CGFloat(columns.count) * cellSize.width,
            height: cellSize.height,
        )
    }
}

/// An ⌥-press over a table cell, from the press until it's a click or a drag inside the cell.
enum CellGesture {
    /// Pressed and not yet moved: a click if it's released now.
    case pressed(NSEvent)
    /// Moved: selecting inside `cell` from `anchor`, over the screen as it was when the drag began.
    case selecting(CellDrag)
}

struct CellDrag {
    let press: NSEvent
    let cell: CopyCell.Cell
    let grid: TextGrid
    let anchor: (row: Int, column: Int)

    /// What's selected with the pointer over `focus`.
    func selection(to focus: (row: Int, column: Int)) -> CopyCell.Selection? {
        CopyCell.selection(in: grid, cell: cell, from: anchor, to: focus)
    }
}

/// Copy Cell (FEATURES.md → F9): holding ⌥ over a table an agent drew outlines the cell under the
/// pointer, an ⌥-click copies it and an ⌥-drag selects inside it, instead of across whole rows.
/// The table logic is `CopyCell` (CalmModel); this reads the grid and maps the pointer to a cell.
///
/// The ⌥-press over a cell never reaches libghostty, so a program that takes the mouse (Claude
/// Code's full-screen view) sees neither the click nor the drag. An ⌥-drag that starts outside a
/// table is the terminal's as before (a rectangle, or the program's own selection).
extension TerminalSurfaceView {
    /// How far an ⌥-press over a cell may move and still be a click, in points.
    private static let clickSlop: CGFloat = 3
    /// How long a finished ⌥-drag's selection stays on screen, showing what was copied.
    private static let selectionShown: Duration = .milliseconds(600)

    /// The table cell under a point, or nil outside a drawn table.
    func tableCell(at point: NSPoint) -> CopyCell.Cell? {
        guard let cell = cell(at: point) else { return nil }
        return CopyCell.cell(in: TextGrid(lines: viewportRows()), row: cell.row, column: cell.column)
    }

    /// Copies the table cell under the point; false (and nothing copied) outside a table.
    @discardableResult
    func copyTableCell(at point: NSPoint) -> Bool {
        guard let text = tableCell(at: point)?.text else { return false }
        NSPasteboard.calm.clearContents()
        NSPasteboard.calm.setString(text, forType: .string)
        host?.surfaceDidCopyCell(self, at: point, whole: true)
        return true
    }

    /// ⌥ alone, not with ⌘ (links), ⇧ or ⌃.
    private static func isOptionOnly(_ flags: NSEvent.ModifierFlags) -> Bool {
        flags.intersection([.option, .command, .shift, .control]) == .option
    }

    /// An ⌥-press over a table cell is kept back until it's a click or a drag. Any press puts
    /// away the last ⌥-drag's selection, still showing what it copied.
    func holdsCellPress(_ event: NSEvent) -> Bool {
        links.cellSelection = []
        guard Self.isOptionOnly(event.modifierFlags), tableCell(at: convert(event.locationInWindow, from: nil)) != nil else {
            return false
        }
        cellGesture = .pressed(event)
        return true
    }

    /// A held press that moves becomes a selection inside its cell, and follows the pointer.
    func dragsCellPress(_ event: NSEvent) {
        let now = convert(event.locationInWindow, from: nil)
        switch cellGesture {
        case let .pressed(press):
            let start = convert(press.locationInWindow, from: nil)
            guard hypot(now.x - start.x, now.y - start.y) > Self.clickSlop else { return }
            let grid = TextGrid(lines: viewportRows())
            guard let from = cell(at: start), let cell = CopyCell.cell(in: grid, row: from.row, column: from.column) else {
                cellGesture = nil
                return
            }
            let drag = CellDrag(press: press, cell: cell, grid: grid, anchor: from)
            cellGesture = .selecting(drag)
            links.cellSelection = selectionRects(drag.selection(to: gridPoint(at: now)))
        case let .selecting(drag):
            links.cellSelection = selectionRects(drag.selection(to: gridPoint(at: now)))
        case nil:
            return
        }
    }

    /// The release ends it: a click copies the cell, a drag what it selected. Neither reaches a
    /// program that takes the mouse.
    func releasesCellPress(_ event: NSEvent) -> Bool {
        guard let gesture = cellGesture else { return false }
        cellGesture = nil
        switch gesture {
        case let .pressed(press):
            copyTableCell(at: convert(press.locationInWindow, from: nil))
            releaseTerminalSelection(at: press, event)
        case let .selecting(drag):
            let point = convert(event.locationInWindow, from: nil)
            let selection = drag.selection(to: gridPoint(at: point))
            links.cellSelection = selectionRects(selection)
            if let text = selection?.text {
                NSPasteboard.calm.clearContents()
                NSPasteboard.calm.setString(text, forType: .string)
                host?.surfaceDidCopyCell(self, at: point, whole: text == drag.cell.text)
            }
            releaseTerminalSelection(at: drag.press, event)
            let shown = links.cellSelection
            Task { [weak self] in
                try? await Task.sleep(for: Self.selectionShown)
                if let self, links.cellSelection == shown {
                    links.cellSelection = []
                }
            }
        }
        return true
    }

    /// An older selection of the terminal's would stay highlighted, as if it were what was
    /// copied; a plain click is how the terminal lets go of one (libghostty has no action for it).
    /// Only where no program takes the mouse, which would take the click for its own.
    private func releaseTerminalSelection(at press: NSEvent, _ event: NSEvent) {
        guard let surface, ghostty_surface_has_selection(surface), !ghostty_surface_mouse_captured(surface),
              let plain = NSEvent.mouseEvent(
                  with: .leftMouseDown, location: press.locationInWindow, modifierFlags: [], timestamp: event.timestamp,
                  windowNumber: event.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1,
              )
        else { return }
        sendMousePosition(plain)
        _ = sendMouseButton(GHOSTTY_MOUSE_PRESS, GHOSTTY_MOUSE_LEFT, plain)
        _ = sendMouseButton(GHOSTTY_MOUSE_RELEASE, GHOSTTY_MOUSE_LEFT, plain)
    }

    /// The grid cell under a point, even past the grid's edges (negative above and to the left),
    /// so a drag out of the pane still says which way it went.
    private func gridPoint(at point: NSPoint) -> (row: Int, column: Int) {
        guard let origin = gridOrigin(), cellSize.width > 0, cellSize.height > 0 else { return (0, 0) }
        return (
            Int(((bounds.height - point.y - origin.y) / cellSize.height).rounded(.down)),
            Int(((point.x - origin.x) / cellSize.width).rounded(.down)),
        )
    }

    /// Where a selection's runs are drawn, in this view's coordinates.
    private func selectionRects(_ selection: CopyCell.Selection?) -> [NSRect] {
        guard let selection, let origin = gridOrigin() else { return [] }
        return selection.runs.compactMap { rect(row: $0.row, columns: $0.columns, origin: origin) }
    }

    /// Outlines the cell under the pointer while ⌥ alone is held, and nothing otherwise.
    func updateCellOutline(_ flags: NSEvent.ModifierFlags) {
        guard Self.isOptionOnly(flags), let pointer = links.pointer, let under = cell(at: pointer)
        else {
            links.cellOutlineProbe = nil
            links.cellOutline = nil
            return
        }
        let probe = CellRun(row: under.row, columns: under.column ..< under.column + 1)
        guard probe != links.cellOutlineProbe else { return }
        links.cellOutlineProbe = probe
        guard let cell = CopyCell.cell(in: TextGrid(lines: viewportRows()), row: under.row, column: under.column),
              let origin = gridOrigin(),
              let top = rect(row: cell.rows.lowerBound, columns: cell.columns, origin: origin),
              let bottom = rect(row: cell.rows.upperBound, columns: cell.columns, origin: origin)
        else {
            links.cellOutline = nil
            return
        }
        links.cellOutline = top.union(bottom)
    }

    /// The right-click menu, when the program running doesn't take the mouse itself: Copy and
    /// Paste. It has no Copy Cell: ⌥-click and ⌥-drag do that everywhere (the author's call,
    /// 2026-09-30).
    override func menu(for _: NSEvent) -> NSMenu? {
        let menu = NSMenu()
        if let surface, ghostty_surface_has_selection(surface) {
            menu.addItem(withTitle: "Copy", action: #selector(copy(_:)), keyEquivalent: "")
        }
        menu.addItem(withTitle: "Paste", action: #selector(paste(_:)), keyEquivalent: "")
        return menu
    }
}

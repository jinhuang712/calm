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

/// Copy Cell (FEATURES.md → F9): ⌥-double-click or right-click → Copy Cell copies one cell of a
/// table an agent drew, instead of whole rows. The table logic is `CopyCell` (CalmModel); this
/// reads the grid and maps the click to a cell.
extension TerminalSurfaceView {
    /// The table cell's text under a point, or nil outside a drawn table.
    func tableCellText(at point: NSPoint) -> String? {
        guard let cell = cell(at: point) else { return nil }
        return CopyCell.text(in: TextGrid(lines: viewportRows()), row: cell.row, column: cell.column)
    }

    /// Copies the table cell under the point; false (and nothing copied) outside a table.
    @discardableResult
    func copyTableCell(at point: NSPoint) -> Bool {
        guard let text = tableCellText(at: point) else { return false }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        host?.surfaceDidCopyCell(self, at: point)
        return true
    }

    /// The right-click menu, when the program running doesn't take the mouse itself.
    override func menu(for event: NSEvent) -> NSMenu? {
        let point = convert(event.locationInWindow, from: nil)
        let menu = NSMenu()
        if tableCellText(at: point) != nil {
            let item = NSMenuItem(title: "Copy Cell", action: #selector(copyCellFromMenu(_:)), keyEquivalent: "")
            item.representedObject = NSValue(point: point)
            item.target = self
            menu.addItem(item)
            menu.addItem(.separator())
        }
        if let surface, ghostty_surface_has_selection(surface) {
            menu.addItem(withTitle: "Copy", action: #selector(copy(_:)), keyEquivalent: "")
        }
        menu.addItem(withTitle: "Paste", action: #selector(paste(_:)), keyEquivalent: "")
        return menu
    }

    @objc private func copyCellFromMenu(_ sender: NSMenuItem) {
        guard let point = (sender.representedObject as? NSValue)?.pointValue else { return }
        copyTableCell(at: point)
    }
}

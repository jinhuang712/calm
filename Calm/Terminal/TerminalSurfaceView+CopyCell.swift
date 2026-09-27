import AppKit
import CalmModel
import GhosttyKit

/// Copy Cell (FEATURES.md → F9): ⌥-double-click or right-click → Copy Cell copies one cell of a
/// table an agent drew, instead of whole rows. The table logic is `CopyCell` (CalmModel); this
/// reads the grid and maps the click to a cell.
extension TerminalSurfaceView {
    /// The visible rows exactly as the grid holds them. One read per row: reading the viewport at
    /// once joins soft-wrapped lines, which would shift every row below them.
    func viewportRows() -> [String] {
        guard let surface else { return [] }
        let size = ghostty_surface_size(surface)
        guard size.columns > 0 else { return [] }
        return (0 ..< UInt32(size.rows)).map { row in
            readText(ghostty_selection_s(
                top_left: ghostty_point_s(tag: GHOSTTY_POINT_VIEWPORT, coord: GHOSTTY_POINT_COORD_EXACT, x: 0, y: row),
                bottom_right: ghostty_point_s(
                    tag: GHOSTTY_POINT_VIEWPORT,
                    coord: GHOSTTY_POINT_COORD_EXACT,
                    x: UInt32(size.columns) - 1,
                    y: row,
                ),
                rectangle: false,
            )) ?? ""
        }
    }

    /// The grid cell under a point in this view. libghostty reports a selection's top-left in
    /// points from the top (as Ghostty's own app reads it), so cell (0,0)'s origin gives the padding.
    func cell(at point: NSPoint) -> (row: Int, column: Int)? {
        guard let surface, cellSize.width > 0, cellSize.height > 0 else { return nil }
        var text = ghostty_text_s()
        let origin = ghostty_point_s(tag: GHOSTTY_POINT_VIEWPORT, coord: GHOSTTY_POINT_COORD_EXACT, x: 0, y: 0)
        guard ghostty_surface_read_text(surface, ghostty_selection_s(top_left: origin, bottom_right: origin, rectangle: false), &text)
        else {
            return nil
        }
        let originX = text.tl_px_x
        let originY = text.tl_px_y
        ghostty_surface_free_text(surface, &text)
        let x = point.x - originX
        let y = bounds.height - point.y - originY
        guard x >= 0, y >= 0 else { return nil }
        return (Int(y / cellSize.height), Int(x / cellSize.width))
    }

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

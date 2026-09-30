/// What the split icon's menu holds (UIUX.md → Split panes). The icon only exists inside a split, so
/// its menu is for managing one: leave it, look at one pane, straighten it. Making a split has its
/// own keys (⌘D, ⌘⌥ + an arrow) and the Shell menu, so it isn't here.
public enum SplitMenu {
    public enum Row: Hashable, Sendable {
        case takeOut
        case unsplitAll
        case separator
        /// Zoom Pane, or Show All Panes while one is zoomed.
        case zoom(zoomed: Bool)
        case equalize
    }

    /// Leaving comes first, since it is what you came for; then looking; then straightening.
    /// Unsplit All is left out with two panes, where it would do what Take Out of Split does.
    public static func rows(paneCount: Int, zoomed: Bool) -> [Row] {
        var rows: [Row] = [.takeOut]
        if paneCount > 2 {
            rows.append(.unsplitAll)
        }
        rows.append(contentsOf: [.separator, .zoom(zoomed: zoomed), .equalize])
        return rows
    }
}

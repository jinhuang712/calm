/// When a pane shows its split icon (UIUX.md → Split panes): the small quiet icon in a pane's
/// top right corner that opens the split's menu and can be dragged out of it.
public enum SplitHandle {
    /// Whether the icon is drawn on a pane. Only in a split, where there is something to do; at
    /// rest only on the pane you're in, which is enough to say it exists, and on any pane the
    /// pointer is on; while its menu is open or it is being dragged, `isBusy`, it stays. Never
    /// while a close question stands on a pane: the question has the whole pane to itself.
    public static func isShown(hasSplits: Bool, isFocused: Bool, isPointedAt: Bool, isBusy: Bool, isAsking: Bool) -> Bool {
        guard hasSplits, !isAsking else { return false }
        return isFocused || isPointedAt || isBusy
    }
}

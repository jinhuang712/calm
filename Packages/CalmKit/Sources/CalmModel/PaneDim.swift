/// How much the panes of a split recede, so the one you're typing in is the bright one
/// (UIUX.md → Split panes). The engine draws no such dim, and Calm's is its own: fixed, not read
/// from Ghostty's `unfocused-split-opacity`, whose value in the user's config was tuned for a
/// terminal that draws it.
public enum PaneDim {
    /// What an unfocused pane keeps: the text stays readable while you work in the other one.
    public static let unfocusedOpacity = 0.6
    /// While a pane is being asked about, the others almost go...
    public static let othersWhileAskingOpacity = 0.22
    /// ...and the asked pane steps back a little, so the question stands out on it.
    public static let askedOpacity = 0.5

    /// How opaque the veil over one pane is, in the terminal's own background color: 0 leaves the
    /// pane as it is. A lone pane is never dimmed. `asked` is the pane a close question is on.
    public static func veil(isFocused: Bool, hasSplits: Bool, isAsked: Bool, asking: Bool) -> Double {
        guard hasSplits else { return 0 }
        if asking {
            return 1 - (isAsked ? askedOpacity : othersWhileAskingOpacity)
        }
        return isFocused ? 0 : 1 - unfocusedOpacity
    }
}

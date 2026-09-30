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

    /// The clearing the question stands in: a vignette of the asked pane's own background, all but
    /// solid in the middle, where the words are, and gone at the edges, so the terminal text
    /// behind the words does not show through them. `opacity` is the background's, at `location`
    /// along the radius (0 the center, 1 the edge).
    public static let clearing: [(location: Double, opacity: Double)] = [
        (0, 0.98), (0.5, 0.95), (0.76, 0.6), (1, 0),
    ]

    /// How far the clearing reaches, as fractions of the pane's width and height.
    public static let clearingReach = (width: 0.66, height: 0.56)

    /// A pane being dragged out of the split, while it is over the sidebar: it all but goes, the
    /// way a card you are about to drop somewhere else does.
    public static let leavingOpacity = 0.16

    /// How opaque the veil over one pane is, in the terminal's own background color: 0 leaves the
    /// pane as it is. A lone pane is never dimmed. `asked` is the pane a close question is on;
    /// `isLeaving` the pane being dragged out of the split.
    public static func veil(isFocused: Bool, hasSplits: Bool, isAsked: Bool, asking: Bool, isLeaving: Bool = false) -> Double {
        guard hasSplits else { return 0 }
        if isLeaving {
            return 1 - leavingOpacity
        }
        if asking {
            return 1 - (isAsked ? askedOpacity : othersWhileAskingOpacity)
        }
        return isFocused ? 0 : 1 - unfocusedOpacity
    }
}

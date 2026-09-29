/// What an agent's card shows under its title at each card size (UIUX.md → Session cards).
/// Full is every line; Compact puts the state and the recap on one line; Minimal is the title
/// alone. At the smaller sizes a card that waits for a look (needs you, done, failed) grows a
/// line, so what it asks or did is never cut away, and settles once it's answered or seen.
/// The saved state decides, so a card being restored keeps the size it will have.
public enum SessionCardLayout: Equatable, Sendable {
    /// The title line alone.
    case titleOnly
    /// The recap alone, this many lines.
    case recap(lines: Int)
    /// Full's card: the state on a line of its own, the todo bar, the recap in two lines. (The
    /// worktree line shows at Full whatever the state.)
    case stacked
    /// Compact's card: the state, then the recap, in one run of text of this many lines; the
    /// todo count sits at the end of a one-line run.
    case merged(lines: Int)

    public init(size: CalmSettings.SessionCardSize, state: SessionState) {
        let waits = Self.waitsForALook(state)
        switch (size, state) {
        case (.full, .idle): self = .recap(lines: 1)
        case (.full, _): self = .stacked
        case (.compact, .idle): self = .titleOnly
        case (.compact, _): self = .merged(lines: waits ? 2 : 1)
        case (.minimal, _): self = waits ? .recap(lines: 1) : .titleOnly
        }
    }

    /// The states that wait for the user: a question, or a turn that ended and hasn't been seen.
    public static func waitsForALook(_ state: SessionState) -> Bool {
        switch state {
        case .needsYou, .done, .failed: true
        case .idle, .working: false
        }
    }

    /// Only the title line: the card is as tall as a shell row.
    public var isOneLine: Bool {
        self == .titleOnly
    }
}

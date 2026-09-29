/// Settings → Appearance → Session cards → Shrink to fit (UIUX.md → Session cards): the cards
/// take the largest size, up to the one chosen, at which the sidebar's sessions fit without
/// scrolling. The list steps down a size when what's drawn is taller than its room, and back up
/// when the larger size is expected to fit again.
///
/// Stepping down trusts what was drawn. Stepping up can't draw the larger size first, so it
/// guesses from `SessionCardLayout.nominalHeight`; a size that was drawn and didn't fit is not
/// tried again until the sessions or the room change, so a guess that's a little short can't
/// make the list flip back and forth.
public struct SessionCardFit: Equatable, Sendable {
    public typealias Size = CalmSettings.SessionCardSize

    /// The size the cards are drawn at.
    public private(set) var size: Size
    /// Sizes that were drawn and overflowed, with the contents they overflowed with.
    private var overflowed: [Size: Int] = [:]

    /// Room kept free before growing, so a guess that errs short still fits.
    public static let margin = 8.0

    public init(size: Size = .full) {
        self.size = size
    }

    /// Settles the size for what was just drawn. `measured` is the list's height at `size`,
    /// `room` the height it has, `cards(size)` about how tall the cards would be at a size, and
    /// `contents` anything that identifies the sessions, their states and the room. Returns
    /// whether the size changed.
    @discardableResult
    public mutating func update(largest: Size, measured: Double, room: Double, cards: (Size) -> Double, contents: Int) -> Bool {
        let before = size
        if size.rank < largest.rank {
            // The chosen size went down: start from it.
            size = largest
            overflowed = [:]
        } else if measured > room + 0.5 {
            if let smaller = size.smaller {
                overflowed[size] = contents
                size = smaller
            }
        } else {
            // The largest size that's expected to fit and hasn't just failed to.
            let others = measured - cards(size)
            for candidate in Size.allCases where candidate.rank >= largest.rank && candidate.rank < size.rank {
                let expected: Double = others + cards(candidate)
                if overflowed[candidate] != contents, expected <= room - Self.margin {
                    size = candidate
                    break
                }
            }
        }
        return size != before
    }
}

public extension CalmSettings.SessionCardSize {
    /// Full is 0, and each smaller size one more.
    var rank: Int {
        Self.allCases.firstIndex(of: self) ?? 0
    }

    /// The next size down, if there is one.
    var smaller: Self? {
        let next = rank + 1
        return next < Self.allCases.count ? Self.allCases[next] : nil
    }
}

public extension SessionCardLayout {
    /// About how tall a card is at the standard interface size, measured from the drawn cards
    /// (UIUX.md → Session cards: 111 pt for a working card at Full, 66 at Compact, 40 at
    /// Minimal). A recap counts as long enough to fill its lines, so the guess errs tall and the
    /// sidebar would rather stay a size too small than scroll.
    static func nominalHeight(
        size: CalmSettings.SessionCardSize, state: SessionState, hasRecap: Bool, hasProgress: Bool, hasWorktree: Bool,
    ) -> Double {
        let title = 26.0
        let line = 17.0
        let twoLines = 33.0
        let worktree = size == .full && hasWorktree ? 6 + 16.0 : 0
        switch SessionCardLayout(size: size, state: state) {
        case .titleOnly:
            return 14 + title
        case let .recap(lines):
            let gap = size == .full ? 6.0 : 4
            return 16 + title + (hasRecap ? gap + (lines > 1 ? twoLines : line) : 0) + worktree
        case .stacked:
            return 24 + title + 6 + 16 + (hasProgress ? 6 + 16 : 0) + (hasRecap ? 6 + twoLines : 0) + worktree
        case let .merged(lines):
            return 20 + title + 4 + (lines > 1 && hasRecap ? twoLines : 16)
        }
    }
}

/// Settings → Appearance → Session cards → Shrink to fit (UIUX.md → Session cards): the cards
/// take the largest size, up to the one chosen, at which the sidebar's sessions fit without
/// scrolling. The list steps down a size when what's drawn is taller than its room, and back up
/// when the larger size is expected to fit again.
///
/// Stepping down trusts what was drawn. Stepping up can't draw the larger size first, so it
/// guesses from `SessionCardLayout.nominalHeight`, and three things keep a guess that's a
/// little short from making the list flip back and forth (it did, by 4 to 12 pt, while agents
/// worked and their states kept changing):
/// - each step down measures how short the guess for the larger size was, and later guesses
///   for it add that;
/// - after a step down the cards stay down for `settle` seconds, so a sidebar near the edge
///   doesn't change shape with every state change;
/// - a size drawn taller than the room isn't tried again until the sessions change or the room
///   is as tall as it was drawn, and growing keeps `margin` spare.
///
/// When the room grows past the one the cards stepped down in, what they stepped down for is
/// gone: they don't wait, and a size already drawn with the same sessions goes by its drawn
/// height, without the margin. A launch once laid the sidebar out in the window's saved frame
/// before the window filled the screen again, and Full, stepped down there, never came back in
/// the whole window (998 pt of 1001: less than the margin spare).
public struct SessionCardFit: Equatable, Sendable {
    public typealias Size = CalmSettings.SessionCardSize

    /// The size the cards are drawn at.
    public private(set) var size: Size
    /// How tall each size was last drawn, with the contents it was drawn with.
    private var drawn: [Size: Drawn] = [:]
    /// How much taller each size came out than the guess for it, as last measured.
    private var shortfall: [Size: Double] = [:]
    /// A step down whose smaller size hasn't been measured yet: from that, how short the guess
    /// for the larger one would have been.
    private var stepDown: StepDown?
    /// When the cards last stepped down.
    public private(set) var steppedDownAt: Double?
    /// The room the cards last stepped down in.
    private var steppedDownIn: Double?

    private struct Drawn: Equatable, Sendable {
        let height: Double
        let contents: Int
    }

    private struct StepDown: Equatable, Sendable {
        let from: Size
        let measured: Double
        let contents: Int
    }

    /// Room kept free before growing.
    public static let margin = 16.0
    /// Seconds after a step down before the cards may step back up.
    public static let settle = 30.0

    public init(size: Size = .full) {
        self.size = size
    }

    /// Settles the size for what was just drawn. `measured` is the list's height at `size`,
    /// `room` the height it has, `cards(size)` about how tall the cards would be at a size,
    /// `contents` anything that identifies the sessions and what their cards hold (not the room,
    /// which is `room`), and `now` a clock in seconds. Returns whether the size changed.
    @discardableResult
    public mutating func update(
        largest: Size, measured: Double, room: Double, cards: (Size) -> Double, contents: Int, now: Double,
    ) -> Bool {
        let before = size
        learn(measured: measured, cards: cards, contents: contents)
        drawn[size] = Drawn(height: measured, contents: contents)
        if size.rank < largest.rank {
            // The chosen size went down: start from it.
            size = largest
        } else if measured > room + 0.5 {
            if let smaller = size.smaller {
                stepDown = StepDown(from: size, measured: measured, contents: contents)
                steppedDownAt = now
                steppedDownIn = room
                size = smaller
            }
        } else {
            grow(largest: largest, measured: measured, room: room, cards: cards, contents: contents, now: now)
        }
        return size != before
    }

    /// While the cards are staying down after a step down, when they may step up again.
    public func growsAgain(after now: Double) -> Double? {
        guard let steppedDownAt, now - steppedDownAt < Self.settle else { return nil }
        return steppedDownAt + Self.settle
    }

    /// Steps up to the largest size, up to `largest`, that's expected to fit.
    private mutating func grow(
        largest: Size, measured: Double, room: Double, cards: (Size) -> Double, contents: Int, now: Double,
    ) {
        let roomGrew = steppedDownIn.map { room > $0 + 0.5 } ?? false
        guard roomGrew || growsAgain(after: now) == nil else { return }
        let others = measured - cards(size)
        for candidate in Size.allCases where candidate.rank >= largest.rank && candidate.rank < size.rank {
            if let seen = drawn[candidate], seen.contents == contents {
                // Drawn with these sessions and taller than the room: it won't fit now either.
                if seen.height > room + 0.5 {
                    continue
                }
                // Only with more room than the cards stepped down in: in the same room it goes by
                // the guess and its margin, because a recap growing a line changes a card without
                // changing `contents`, and near the edge the cards would flip back and forth.
                if roomGrew {
                    size = candidate
                    return
                }
            }
            if others + cards(candidate) + (shortfall[candidate] ?? 0) <= room - Self.margin {
                size = candidate
                return
            }
        }
    }

    /// The first measurement after a step down: the larger size as drawn, against what the guess
    /// from here would have said for it. Only for the same sessions: a card that changed in
    /// between would count as the guess's fault, and could keep the cards small for good.
    private mutating func learn(measured: Double, cards: (Size) -> Double, contents: Int) {
        guard let step = stepDown, step.from.rank < size.rank else { return }
        stepDown = nil
        guard step.contents == contents else { return }
        let guess = measured - cards(size) + cards(step.from)
        shortfall[step.from] = max(0, step.measured - guess)
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

/// Settings → Appearance → Session cards → Shrink to fit (specs/UIUX.md → Session cards): the cards
/// take the largest step, from the size chosen down, at which the sidebar's sessions fit without
/// scrolling. The list steps down when what's drawn is taller than its room, and back up when the
/// larger step is expected to fit again. A step is a size for every card, or a `CardFold`, which
/// takes the quiet cards down before the busy ones.
///
/// Stepping down trusts what was drawn. Stepping up can't draw the larger step first, so it
/// guesses from `SessionCardLayout.nominalHeight`, and three things keep a guess that's a
/// little short from making the list flip back and forth (it did, by 4 to 12 pt, while agents
/// worked and their states kept changing):
/// - each step down measures how short the guess for the larger step was, and later guesses
///   for it add that;
/// - after a step down the cards stay down for `CardFit.settle` seconds, so a sidebar near the
///   edge doesn't change shape with every state change;
/// - a step drawn taller than the room isn't tried again until the sessions change or the room
///   is as tall as it was drawn, and growing keeps `CardFit.margin` spare.
///
/// When the room grows past the one the cards stepped down in, what they stepped down for is
/// gone: they don't wait, and a step already drawn with the same sessions goes by its drawn
/// height, without the margin. A launch once laid the sidebar out in the window's saved frame
/// before the window filled the screen again, and Full, stepped down there, never came back in
/// the whole window (998 pt of 1001: less than the margin spare).
public struct SessionCardFit<Step: CardFitStep>: Equatable, Sendable {
    public typealias Size = CalmSettings.SessionCardSize

    /// The step the cards are drawn at.
    public private(set) var step: Step
    /// How tall each step was last drawn, with the contents it was drawn with.
    private var drawn: [Step: Drawn] = [:]
    /// How much taller each step came out than the guess for it, as last measured.
    private var shortfall: [Step: Double] = [:]
    /// A step down whose smaller step hasn't been measured yet: from that, how short the guess
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
        let from: Step
        let measured: Double
        let contents: Int
    }

    public init(step: Step) {
        self.step = step
    }

    /// Settles the step for what was just drawn. `measured` is the list's height at `step`,
    /// `room` the height it has, `cards(step)` about how tall the cards would be at a step,
    /// `contents` anything that identifies the sessions and what their cards hold (not the room,
    /// which is `room`), and `now` a clock in seconds. Returns whether the step changed.
    @discardableResult
    public mutating func update(
        largest: Size, measured: Double, room: Double, cards: (Step) -> Double, contents: Int, now: Double,
    ) -> Bool {
        let before = step
        let steps = Step.steps(from: largest)
        learn(steps: steps, measured: measured, cards: cards, contents: contents)
        drawn[step] = Drawn(height: measured, contents: contents)
        guard let index = steps.firstIndex(of: step) else {
            // The chosen size went down: start from it.
            step = steps[0]
            return true
        }
        if measured > room + 0.5 {
            if index + 1 < steps.count {
                stepDown = StepDown(from: step, measured: measured, contents: contents)
                steppedDownAt = now
                steppedDownIn = room
                step = steps[index + 1]
            }
        } else {
            grow(larger: steps[..<index], measured: measured, room: room, cards: cards, contents: contents, now: now)
        }
        return step != before
    }

    /// While the cards are staying down after a step down, when they may step up again.
    public func growsAgain(after now: Double) -> Double? {
        guard let steppedDownAt, now - steppedDownAt < CardFit.settle else { return nil }
        return steppedDownAt + CardFit.settle
    }

    /// Steps up to the largest of `larger` (largest first) that's expected to fit.
    private mutating func grow(
        larger: ArraySlice<Step>, measured: Double, room: Double, cards: (Step) -> Double, contents: Int, now: Double,
    ) {
        let roomGrew = steppedDownIn.map { room > $0 + 0.5 } ?? false
        guard roomGrew || growsAgain(after: now) == nil else { return }
        let others = measured - cards(step)
        for candidate in larger {
            if let seen = drawn[candidate], seen.contents == contents {
                // Drawn with these sessions and taller than the room: it won't fit now either.
                if seen.height > room + 0.5 {
                    continue
                }
                // Only with more room than the cards stepped down in: in the same room it goes by
                // the guess and its margin, because a recap growing a line changes a card without
                // changing `contents`, and near the edge the cards would flip back and forth.
                if roomGrew {
                    step = candidate
                    return
                }
            }
            if others + cards(candidate) + (shortfall[candidate] ?? 0) <= room - CardFit.margin {
                step = candidate
                return
            }
        }
    }

    /// The first measurement after a step down: the larger step as drawn, against what the guess
    /// from here would have said for it. Only for the same sessions: a card that changed in
    /// between would count as the guess's fault, and could keep the cards small for good.
    private mutating func learn(steps: [Step], measured: Double, cards: (Step) -> Double, contents: Int) {
        guard let down = stepDown, let from = steps.firstIndex(of: down.from), let at = steps.firstIndex(of: step),
              from < at
        else { return }
        stepDown = nil
        guard down.contents == contents else { return }
        let guess = measured - cards(step) + cards(down.from)
        shortfall[down.from] = max(0, down.measured - guess)
    }
}

/// What shrink to fit steps down through: one size for every card (`SessionCardSize`), or a fold
/// that takes the quiet cards down first (`CardFold`).
public protocol CardFitStep: Hashable, Sendable {
    /// The steps from the chosen size down, largest first.
    static func steps(from largest: CalmSettings.SessionCardSize) -> [Self]
}

/// The numbers shrink to fit keeps the cards steady with.
public enum CardFit {
    /// Room kept free before growing.
    public static let margin = 16.0
    /// Seconds after a step down before the cards may step back up.
    public static let settle = 30.0
}

extension CalmSettings.SessionCardSize: CardFitStep {
    /// The chosen size and every smaller one.
    public static func steps(from largest: Self) -> [Self] {
        allCases.filter { $0.rank >= largest.rank }
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
    /// (specs/UIUX.md → Session cards: 111 pt for a working card at Full, 66 at Compact, 40 at
    /// Minimal). A recap counts as long enough to fill its lines, so the guess errs tall and the
    /// sidebar would rather stay a size too small than scroll.
    static func nominalHeight(
        size: CalmSettings.SessionCardSize, state: SessionState, hasRecap: Bool, hasProgress: Bool, hasWorktree: Bool,
        shellsRunning: Bool = false, isPinned: Bool = false,
    ) -> Double {
        // A pinned card names its project on a line above the title, at every size.
        let projectLine = isPinned ? (size == .full ? 6 : 4) + 16.0 : 0
        return projectLine + unpinnedHeight(
            size: size, state: state, hasRecap: hasRecap, hasProgress: hasProgress, hasWorktree: hasWorktree, shellsRunning: shellsRunning,
        )
    }

    private static func unpinnedHeight(
        size: CalmSettings.SessionCardSize, state: SessionState, hasRecap: Bool, hasProgress: Bool, hasWorktree: Bool, shellsRunning: Bool,
    ) -> Double {
        let title = 26.0
        let line = 17.0
        let twoLines = 33.0
        let worktree = size == .full && hasWorktree ? 6 + 16.0 : 0
        switch SessionCardLayout(size: size, state: state, shellsRunning: shellsRunning) {
        case .titleOnly:
            return 14 + title
        case let .recap(lines):
            let gap = size == .full ? 6.0 : 4
            // An idle card's line also holds the shells, so it shows with no recap.
            let hasLine = hasRecap || (state == .idle && shellsRunning)
            return 16 + title + (hasLine ? gap + (lines > 1 ? twoLines : line) : 0) + worktree
        case .stacked:
            return 24 + title + 6 + 16 + (hasProgress ? 6 + 16 : 0) + (hasRecap ? 6 + twoLines : 0) + worktree
        case let .merged(lines):
            return 20 + title + 4 + (lines > 1 && hasRecap ? twoLines : 16)
        }
    }
}

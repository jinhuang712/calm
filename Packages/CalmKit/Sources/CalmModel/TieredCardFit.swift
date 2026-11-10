/// Shrink to fit with pinned cards kept whole (specs/FEATURES.md → F2). The cards below fold as
/// `SessionCardFit` decides, and the list scrolls if that isn't enough. Pinned cards fold only
/// when Pinned alone is taller than the sidebar, because then the list can't show them all. Both
/// fold a step at a time (`CardFold`): the quiet cards first, the busy ones last.
public struct TieredCardFit: Equatable, Sendable {
    public typealias Size = CalmSettings.SessionCardSize

    private var others: SessionCardFit<CardFold>
    public private(set) var pinnedFold: CardFold

    /// The fold of the cards that are not pinned.
    public var otherFold: CardFold {
        others.step
    }

    public init(size: Size = .full) {
        others = SessionCardFit(step: CardFold(size))
        pinnedFold = CardFold(size)
    }

    /// Settles both folds for what was just drawn. As `SessionCardFit.update`, with `cards` taking
    /// the fold of the other cards and of the pinned ones, and `pinnedHeight(fold)` about how tall
    /// Pinned would be at a fold. Returns whether a fold changed. After a change in Pinned the
    /// list comes out at another height, and the next measurement settles the others.
    @discardableResult
    public mutating func update(
        largest: Size, measured: Double, room: Double, cards: (_ others: CardFold, _ pinned: CardFold) -> Double,
        pinnedHeight: (CardFold) -> Double, contents: Int, now: Double,
    ) -> Bool {
        let fitted = Self.pinnedFold(largest: largest, room: room, height: pinnedHeight)
        if fitted != pinnedFold {
            pinnedFold = fitted
            return true
        }
        let pinned = pinnedFold
        return others.update(
            largest: largest, measured: measured, room: room, cards: { cards($0, pinned) }, contents: contents, now: now,
        )
    }

    /// The largest fold, from `largest` down, at which Pinned fits, else the smallest.
    private static func pinnedFold(largest: Size, room: Double, height: (CardFold) -> Double) -> CardFold {
        let steps = CardFold.steps(from: largest)
        return steps.first { height($0) <= room - CardFit.margin } ?? steps[steps.count - 1]
    }

    /// While the cards below are staying down after a step down, when they may step up again.
    public func growsAgain(after now: Double) -> Double? {
        others.growsAgain(after: now)
    }
}

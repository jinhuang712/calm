/// Shrink to fit with pinned cards kept whole (specs/FEATURES.md → F2). The cards below fold as
/// `SessionCardFit` decides, and the list scrolls if that isn't enough. Pinned cards fold only
/// when Pinned alone is taller than the sidebar, because then the list can't show them all. Both
/// fold a step at a time (`CardFold`): the quiet cards first, the busy ones last.
///
/// Pinned isn't measured on its own, so its fit goes by the guess for it, through the same
/// `SessionCardFit` as the others: it steps down when the guess is taller than the room, grows
/// with `CardFit.margin` spare, and waits `CardFit.settle` seconds after a step down. With one
/// line for both ways and no wait, Pinned near the edge folded and grew back each time a card in
/// it changed state (66 times in three hours in the author's trace).
public struct TieredCardFit: Equatable, Sendable {
    public typealias Size = CalmSettings.SessionCardSize

    private var others: SessionCardFit<CardFold>
    private var pinned: SessionCardFit<CardFold>

    /// The fold of the cards that are not pinned.
    public var otherFold: CardFold {
        others.step
    }

    /// The fold of the pinned cards.
    public var pinnedFold: CardFold {
        pinned.step
    }

    public init(size: Size = .full) {
        others = SessionCardFit(step: CardFold(size))
        pinned = SessionCardFit(step: CardFold(size))
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
        if fitPinned(largest: largest, room: room, height: pinnedHeight, contents: contents, now: now) {
            return true
        }
        let fold = pinnedFold
        return others.update(
            largest: largest, measured: measured, room: room, cards: { cards($0, fold) }, contents: contents, now: now,
        )
    }

    /// Steps Pinned until its guess settles: nothing is drawn in between, and a step that leaves
    /// the list as tall (no idle card to fold) brings no measurement to take the next one.
    private mutating func fitPinned(
        largest: Size, room: Double, height: (CardFold) -> Double, contents: Int, now: Double,
    ) -> Bool {
        var changed = false
        for _ in CardFold.steps(from: largest).indices {
            let moved = pinned.update(
                largest: largest, measured: height(pinned.step), room: room, cards: height, contents: contents, now: now,
            )
            guard moved else { break }
            changed = true
        }
        return changed
    }

    /// While either group is staying down after a step down, when the first may step up again.
    public func growsAgain(after now: Double) -> Double? {
        [others.growsAgain(after: now), pinned.growsAgain(after: now)].compactMap(\.self).min()
    }
}

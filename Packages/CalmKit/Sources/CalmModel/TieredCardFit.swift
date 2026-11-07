/// Shrink to fit with pinned cards last (specs/FEATURES.md → F2): the other cards step down to
/// their smallest, and only then the pinned ones. On the way back up the pinned ones go first.
/// Two `SessionCardFit`s, one for each kind of card, with only one moving at a time, so each
/// keeps its own drawn heights and its guard against flipping.
public struct TieredCardFit: Equatable, Sendable {
    public typealias Size = CalmSettings.SessionCardSize

    private var others: SessionCardFit
    private var pinned: SessionCardFit

    /// The size of the cards that are not pinned.
    public var otherSize: Size {
        others.size
    }

    public var pinnedSize: Size {
        pinned.size
    }

    public init(size: Size = .full) {
        others = SessionCardFit(size: size)
        pinned = SessionCardFit(size: size)
    }

    /// Settles both sizes for what was just drawn. As `SessionCardFit.update`, with `cards` taking
    /// the size of the other cards and of the pinned ones. Returns whether a size changed.
    ///
    /// A step that leaves the list as tall as it was brings no new measurement, because the sidebar
    /// measures when the height changes. So what was measured still holds, and the next step is
    /// taken now. Idle cards are as tall at Compact as at Minimal, and without this the pinned
    /// cards waited for the next unrelated change, such as closing a session, to step down.
    @discardableResult
    public mutating func update(
        largest: Size, measured: Double, room: Double, cards: (_ others: Size, _ pinned: Size) -> Double, contents: Int, now: Double,
    ) -> Bool {
        var changed = false
        // Each pass moves a size one step, so five passes reach Minimal from Full for both.
        for _ in 0 ..< 5 {
            let before = cards(others.size, pinned.size)
            guard step(largest: largest, measured: measured, room: room, cards: cards, contents: contents, now: now) else { break }
            changed = true
            guard cards(others.size, pinned.size) == before else { break }
        }
        return changed
    }

    private mutating func step(
        largest: Size, measured: Double, room: Double, cards: (_ others: Size, _ pinned: Size) -> Double, contents: Int, now: Double,
    ) -> Bool {
        let overflows = measured > room + 0.5
        if pinned.size != largest || (overflows && others.size.smaller == nil) {
            let others = others.size
            return pinned.update(
                largest: largest, measured: measured, room: room, cards: { cards(others, $0) }, contents: contents, now: now,
            )
        }
        let pinned = pinned.size
        return others.update(
            largest: largest, measured: measured, room: room, cards: { cards($0, pinned) }, contents: contents, now: now,
        )
    }

    /// While cards are staying down after a step down, when the first may step up again.
    public func growsAgain(after now: Double) -> Double? {
        [others.growsAgain(after: now), pinned.growsAgain(after: now)].compactMap(\.self).min()
    }
}

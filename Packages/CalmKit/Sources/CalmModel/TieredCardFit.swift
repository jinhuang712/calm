/// Shrink to fit with pinned cards kept whole (specs/FEATURES.md → F2). The cards below step down as
/// `SessionCardFit` decides, and the list scrolls if that isn't enough. Pinned cards shrink only
/// when Pinned alone is taller than the sidebar, because then the list can't show them all.
public struct TieredCardFit: Equatable, Sendable {
    public typealias Size = CalmSettings.SessionCardSize

    private var others: SessionCardFit
    public private(set) var pinnedSize: Size

    /// The size of the cards that are not pinned.
    public var otherSize: Size {
        others.size
    }

    public init(size: Size = .full) {
        others = SessionCardFit(size: size)
        pinnedSize = size
    }

    /// Settles both sizes for what was just drawn. As `SessionCardFit.update`, with `cards` taking
    /// the size of the other cards and of the pinned ones, and `pinnedHeight(size)` about how tall
    /// Pinned would be at a size. Returns whether a size changed. After a change in Pinned the
    /// list comes out at another height, and the next measurement settles the others.
    @discardableResult
    public mutating func update(
        largest: Size, measured: Double, room: Double, cards: (_ others: Size, _ pinned: Size) -> Double,
        pinnedHeight: (Size) -> Double, contents: Int, now: Double,
    ) -> Bool {
        let fitted = Self.pinnedSize(largest: largest, room: room, height: pinnedHeight)
        if fitted != pinnedSize {
            pinnedSize = fitted
            return true
        }
        let pinned = pinnedSize
        return others.update(
            largest: largest, measured: measured, room: room, cards: { cards($0, pinned) }, contents: contents, now: now,
        )
    }

    /// The largest size, up to `largest`, at which Pinned fits, else the smallest.
    private static func pinnedSize(largest: Size, room: Double, height: (Size) -> Double) -> Size {
        let sizes = Size.allCases.filter { $0.rank >= largest.rank }
        return sizes.first { height($0) <= room - SessionCardFit.margin } ?? sizes.last ?? largest
    }

    /// While the cards below are staying down after a step down, when they may step up again.
    public func growsAgain(after now: Double) -> Double? {
        others.growsAgain(after: now)
    }
}

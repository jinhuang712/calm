import CalmModel
import Testing

struct TieredCardFitTests {
    typealias Size = CalmSettings.SessionCardSize

    private static func height(_ size: Size) -> Double {
        switch size {
        case .full: 100
        case .compact: 60
        case .minimal: 40
        }
    }

    /// Two pinned cards.
    private static func pinned(_ size: Size) -> Double {
        2 * height(size)
    }

    /// Six other cards under them, as a list with no other rows would draw them.
    private static func list(_ others: Size, _ pinned: Size) -> Double {
        6 * height(others) + Self.pinned(pinned)
    }

    /// Draws and settles until nothing moves, the way the sidebar measures after each change.
    private func settle(_ fit: inout TieredCardFit, in room: Double, largest: Size = .full, at now: Double) {
        for _ in 0 ..< 8 {
            fit.update(
                largest: largest, measured: Self.list(fit.otherSize, fit.pinnedSize), room: room, cards: Self.list,
                pinnedHeight: Self.pinned, contents: 1, now: now,
            )
        }
    }

    @Test func `the other cards shrink, and pinned ones keep their size while the list scrolls`() {
        var fit = TieredCardFit()
        settle(&fit, in: 300, at: 0)
        #expect(fit.otherSize == .minimal)
        #expect(fit.pinnedSize == .full)
    }

    @Test func `pinned cards shrink only when Pinned alone is taller than the sidebar`() {
        var fit = TieredCardFit()
        settle(&fit, in: 150, at: 0)
        #expect(fit.pinnedSize == .compact)
        settle(&fit, in: 90, at: 0)
        #expect(fit.pinnedSize == .minimal)
    }

    @Test func `pinned cards keep the smallest size when nothing fits`() {
        var fit = TieredCardFit()
        settle(&fit, in: 10, at: 0)
        #expect(fit.pinnedSize == .minimal)
    }

    @Test func `with more room pinned cards grow back at once, and the others after their wait`() {
        var fit = TieredCardFit()
        settle(&fit, in: 90, at: 0)

        settle(&fit, in: 2000, at: 1)
        #expect(fit.pinnedSize == .full)

        settle(&fit, in: 2000, at: 200)
        #expect(fit.otherSize == .full)
    }

    @Test func `the chosen size is the largest for both`() {
        var fit = TieredCardFit()
        settle(&fit, in: 2000, largest: .compact, at: 0)
        #expect(fit.otherSize == .compact)
        #expect(fit.pinnedSize == .compact)
    }

    @Test func `with Minimal chosen nothing can step down`() {
        var fit = TieredCardFit(size: .minimal)
        settle(&fit, in: 10, largest: .minimal, at: 0)
        #expect(fit.otherSize == .minimal)
        #expect(fit.pinnedSize == .minimal)
    }

    @Test func `the cards below wait to grow as before`() {
        var fit = TieredCardFit()
        settle(&fit, in: 300, at: 0)
        #expect(fit.growsAgain(after: 1) == SessionCardFit.settle)
        #expect(fit.growsAgain(after: SessionCardFit.settle + 1) == nil)
    }
}

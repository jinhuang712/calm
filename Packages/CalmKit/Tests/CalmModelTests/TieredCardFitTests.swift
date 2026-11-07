import CalmModel
import Testing

struct TieredCardFitTests {
    typealias Size = CalmSettings.SessionCardSize

    /// Six other cards and two pinned ones, as a list with no other rows would draw them.
    private static func list(_ others: Size, _ pinned: Size) -> Double {
        func height(_ size: Size) -> Double {
            switch size {
            case .full: 100
            case .compact: 60
            case .minimal: 40
            }
        }
        return 6 * height(others) + 2 * height(pinned)
    }

    /// Draws and settles until nothing moves, the way the sidebar measures after each change.
    private func settle(_ fit: inout TieredCardFit, in room: Double, largest: Size = .full, at now: Double) {
        for _ in 0 ..< 8 {
            let measured = Self.list(fit.otherSize, fit.pinnedSize)
            fit.update(largest: largest, measured: measured, room: room, cards: Self.list, contents: 1, now: now)
        }
    }

    @Test func `the other cards shrink first, and pinned ones keep their size while that is enough`() {
        var fit = TieredCardFit()
        settle(&fit, in: 440, at: 0)
        #expect(fit.otherSize == .minimal)
        #expect(fit.pinnedSize == .full)
    }

    @Test func `pinned cards shrink once the others are at their smallest`() {
        var fit = TieredCardFit()
        settle(&fit, in: 300, at: 0)
        #expect(fit.otherSize == .minimal)
        #expect(fit.pinnedSize == .minimal)
    }

    @Test func `pinned cards stop at the first size that fits`() {
        var fit = TieredCardFit()
        settle(&fit, in: 365, at: 0)
        #expect(fit.otherSize == .minimal)
        #expect(fit.pinnedSize == .compact)
    }

    @Test func `with more room pinned cards grow back first`() {
        var fit = TieredCardFit()
        settle(&fit, in: 300, at: 0)

        settle(&fit, in: 480, at: 100)
        #expect(fit.pinnedSize == .full)
        #expect(fit.otherSize == .minimal)

        settle(&fit, in: 2000, at: 200)
        #expect(fit.pinnedSize == .full)
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

    @Test func `a pinned step down waits to grow like any other`() {
        var fit = TieredCardFit()
        settle(&fit, in: 300, at: 0)
        #expect(fit.growsAgain(after: 1) == SessionCardFit.settle)
        #expect(fit.growsAgain(after: SessionCardFit.settle + 1) == nil)
    }
}

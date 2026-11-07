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

    /// Idle cards are one line at Compact and at Minimal, so that step draws the same list and
    /// no new measurement follows it. The sidebar measures only when the list's height changes.
    @Test func `a step that changes no height goes straight on to the next one`() {
        func idle(_ others: Size, _ pinned: Size) -> Double {
            func other(_ size: Size) -> Double {
                size == .full ? 65 : 40
            }
            func card(_ size: Size) -> Double {
                switch size {
                case .full: 100
                case .compact: 60
                case .minimal: 40
                }
            }
            return 6 * other(others) + 2 * card(pinned)
        }
        var fit = TieredCardFit()
        var drawn = idle(fit.otherSize, fit.pinnedSize)
        // As the sidebar does it: a new measurement only when the height changed.
        for _ in 0 ..< 8 {
            fit.update(largest: .full, measured: drawn, room: 300, cards: idle, contents: 1, now: 0)
            let now = idle(fit.otherSize, fit.pinnedSize)
            if now == drawn {
                break
            }
            drawn = now
        }
        #expect(fit.otherSize == .minimal)
        #expect(fit.pinnedSize == .minimal)
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

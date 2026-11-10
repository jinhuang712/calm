import CalmModel
import Testing

struct TieredCardFitTests {
    typealias Size = CalmSettings.SessionCardSize

    /// A busy card is 100, 60 and 40 tall; a quiet one 60 at Full and 40 below, as idle cards go.
    private static func height(_ size: Size, quiet: Bool) -> Double {
        switch size {
        case .full: quiet ? 60 : 100
        case .compact: quiet ? 40 : 60
        case .minimal: 40
        }
    }

    /// `busy` busy cards and `quiet` quiet ones at a fold.
    private static func cards(_ fold: CardFold, busy: Int, quiet: Int) -> Double {
        Double(busy) * height(fold.busy, quiet: false) + Double(quiet) * height(fold.quiet, quiet: true)
    }

    /// Two pinned cards: one busy, one quiet. 160, 140, 100 and 80 tall down the steps from Full.
    private static func pinned(_ fold: CardFold) -> Double {
        cards(fold, busy: 1, quiet: 1)
    }

    /// Six other cards under them, three of each, as a list with no other rows would draw them.
    private static func list(_ others: CardFold, _ pinned: CardFold) -> Double {
        cards(others, busy: 3, quiet: 3) + Self.pinned(pinned)
    }

    /// Draws and settles until nothing moves, the way the sidebar measures after each change.
    private func settle(_ fit: inout TieredCardFit, in room: Double, largest: Size = .full, at now: Double) {
        for _ in 0 ..< 8 {
            fit.update(
                largest: largest, measured: Self.list(fit.otherFold, fit.pinnedFold), room: room, cards: Self.list,
                pinnedHeight: Self.pinned, contents: 1, now: now,
            )
        }
    }

    @Test func `the other cards fold, and pinned ones stay whole while the list scrolls`() {
        var fit = TieredCardFit()
        settle(&fit, in: 300, at: 0)
        #expect(fit.otherFold == CardFold(.minimal))
        #expect(fit.pinnedFold == CardFold(.full))
    }

    @Test func `idle cards fold before the busy ones`() {
        // Full is 640 tall; with the quiet cards folded it's 580.
        var fit = TieredCardFit()
        settle(&fit, in: 600, at: 0)
        #expect(fit.otherFold == CardFold(quiet: .compact, busy: .full))
        #expect(fit.pinnedFold == CardFold(.full))
    }

    @Test func `pinned cards fold only when Pinned alone is taller than the sidebar, idle ones first`() {
        var fit = TieredCardFit()
        settle(&fit, in: 170, at: 0)
        #expect(fit.pinnedFold == CardFold(quiet: .compact, busy: .full))
        settle(&fit, in: 120, at: 0)
        #expect(fit.pinnedFold == CardFold(.compact))
        settle(&fit, in: 90, at: 0)
        #expect(fit.pinnedFold == CardFold(.minimal))
    }

    @Test func `pinned cards keep the smallest fold when nothing fits`() {
        var fit = TieredCardFit()
        settle(&fit, in: 10, at: 0)
        #expect(fit.pinnedFold == CardFold(.minimal))
    }

    @Test func `with more room pinned cards grow back at once, and the others after their wait`() {
        var fit = TieredCardFit()
        settle(&fit, in: 90, at: 0)

        settle(&fit, in: 2000, at: 1)
        #expect(fit.pinnedFold == CardFold(.full))

        settle(&fit, in: 2000, at: 200)
        #expect(fit.otherFold == CardFold(.full))
    }

    @Test func `the chosen size is the largest for both`() {
        var fit = TieredCardFit()
        settle(&fit, in: 2000, largest: .compact, at: 0)
        #expect(fit.otherFold == CardFold(.compact))
        #expect(fit.pinnedFold == CardFold(.compact))
    }

    @Test func `with Minimal chosen nothing can step down`() {
        var fit = TieredCardFit(size: .minimal)
        settle(&fit, in: 10, largest: .minimal, at: 0)
        #expect(fit.otherFold == CardFold(.minimal))
        #expect(fit.pinnedFold == CardFold(.minimal))
    }

    @Test func `the cards below wait to grow as before`() {
        var fit = TieredCardFit()
        settle(&fit, in: 300, at: 0)
        #expect(fit.growsAgain(after: 1) == CardFit.settle)
        #expect(fit.growsAgain(after: CardFit.settle + 1) == nil)
    }
}

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
        settle(&fit, in: 160, at: 0)
        #expect(fit.pinnedFold == CardFold(.full))
        settle(&fit, in: 150, at: 0)
        #expect(fit.pinnedFold == CardFold(quiet: .compact, busy: .full))
        settle(&fit, in: 120, at: 0)
        #expect(fit.pinnedFold == CardFold(.compact))
        settle(&fit, in: 90, at: 0)
        #expect(fit.pinnedFold == CardFold(.minimal))
    }

    @Test func `pinned cards fold as far as they need in one update`() {
        // Busy cards only: folding the quiet ones leaves Pinned as tall, and draws nothing new
        // to measure, so the next step must come in the same update.
        var fit = TieredCardFit()
        fit.update(
            largest: .full, measured: 0, room: 70, cards: { _, _ in 0 },
            pinnedHeight: { Self.cards($0, busy: 1, quiet: 0) }, contents: 1, now: 0,
        )
        #expect(fit.pinnedFold == CardFold(.compact))
    }

    @Test func `at the edge, a pinned card a little taller or shorter doesn't fold Pinned`() {
        // Pinned 160 tall, then 150, in 170. With one line both ways (fits with 16 spare) it
        // folded at 160 and grew back at 150, each time a recap changed.
        var fit = TieredCardFit()
        var changes = 0
        for tick in 0 ..< 20 {
            let pinned: (CardFold) -> Double = { Self.pinned($0) - (tick.isMultiple(of: 2) ? 0 : 10) }
            let before = fit.pinnedFold
            fit.update(
                largest: .full, measured: 1000, room: 170, cards: { _, _ in 1000 }, pinnedHeight: pinned,
                contents: tick, now: Double(tick) * 20,
            )
            changes += fit.pinnedFold == before ? 0 : 1
        }
        #expect(changes == 0)
        #expect(fit.pinnedFold == CardFold(.full))
    }

    @Test func `a pinned card going between working and idle folds Pinned at most once a wait`() {
        // A second busy card in Pinned while it works (260 at Full, 160 without it) in 170, its
        // state changing every 2 s for two minutes. Without the wait Pinned changed every time.
        var fit = TieredCardFit()
        var changes = 0
        for tick in 0 ..< 60 {
            let working = tick.isMultiple(of: 2)
            let pinned: (CardFold) -> Double = { Self.pinned($0) + (working ? Self.height($0.busy, quiet: false) : 0) }
            let before = fit.pinnedFold
            fit.update(
                largest: .full, measured: 1000, room: 170, cards: { _, _ in 1000 }, pinnedHeight: pinned,
                contents: tick, now: Double(tick) * 2,
            )
            changes += fit.pinnedFold == before ? 0 : 1
        }
        // Down at 0; the idle card's line back at 30, 62 and 94, and gone 2 s after each.
        #expect(changes == 7)
    }

    @Test func `pinned cards wait after a step down before growing again`() {
        var fit = TieredCardFit()
        let heavy: (CardFold) -> Double = { Self.pinned($0) + 100 }
        fit.update(largest: .full, measured: 0, room: 200, cards: { _, _ in 0 }, pinnedHeight: heavy, contents: 1, now: 0)
        #expect(fit.pinnedFold != CardFold(.full))
        #expect(fit.growsAgain(after: 1) == CardFit.settle)
        // The heavy card left: Full fits with room to spare, but not before the wait is over.
        fit.update(largest: .full, measured: 0, room: 200, cards: { _, _ in 0 }, pinnedHeight: Self.pinned, contents: 2, now: 10)
        #expect(fit.pinnedFold != CardFold(.full))
        fit.update(
            largest: .full, measured: 0, room: 200, cards: { _, _ in 0 }, pinnedHeight: Self.pinned, contents: 2, now: CardFit.settle,
        )
        #expect(fit.pinnedFold == CardFold(.full))
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

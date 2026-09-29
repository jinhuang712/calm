import CalmModel
import Testing

struct SessionCardFitTests {
    /// Ten working cards with recaps, as the guess sees them.
    private static func cards(_ size: CalmSettings.SessionCardSize) -> Double {
        10 * SessionCardLayout.nominalHeight(size: size, state: .working, hasRecap: true, hasProgress: false, hasWorktree: false)
    }

    @Test func `the guessed heights are the drawn ones`() {
        func height(_ size: CalmSettings.SessionCardSize, _ state: SessionState, progress: Bool = false, worktree: Bool = false) -> Double {
            SessionCardLayout.nominalHeight(size: size, state: state, hasRecap: true, hasProgress: progress, hasWorktree: worktree)
        }
        #expect(height(.full, .working) == 111)
        #expect(height(.full, .working, progress: true) == 133)
        #expect(height(.full, .idle) == 65)
        #expect(height(.compact, .working) == 66)
        #expect(height(.compact, .needsYou) == 83)
        #expect(height(.compact, .idle) == 40)
        #expect(height(.minimal, .working) == 40)
        #expect(height(.minimal, .done) == 63)
        // The worktree line is Full's alone.
        #expect(height(.full, .working, worktree: true) == 133)
        #expect(height(.compact, .working, worktree: true) == 66)
    }

    @Test func `too many sessions step the cards down one size at a time`() {
        var fit = SessionCardFit(size: .full)
        do {
            let changed = fit.update(largest: .full, measured: 1200, room: 700, cards: Self.cards, contents: 1)
            #expect(changed)
        }
        #expect(fit.size == .compact)
        do {
            let changed = fit.update(largest: .full, measured: 750, room: 700, cards: Self.cards, contents: 1)
            #expect(changed)
        }
        #expect(fit.size == .minimal)
        // Minimal is as small as it goes: the list scrolls.
        do {
            let changed = fit.update(largest: .full, measured: 720, room: 700, cards: Self.cards, contents: 1)
            #expect(!changed)
        }
        #expect(fit.size == .minimal)
    }

    @Test func `fewer sessions bring the larger size back`() {
        var fit = SessionCardFit(size: .full)
        fit.update(largest: .full, measured: 1200, room: 700, cards: Self.cards, contents: 1)
        #expect(fit.size == .compact)
        // Sessions closed: at Compact the list is 400 tall, so Full (400 - 660 + 1110 = 850) doesn't
        // fit yet...
        do {
            let changed = fit.update(largest: .full, measured: 400, room: 700, cards: Self.cards, contents: 2)
            #expect(!changed)
        }
        // ...until the room grows.
        do {
            let changed = fit.update(largest: .full, measured: 400, room: 900, cards: Self.cards, contents: 3)
            #expect(changed)
        }
        #expect(fit.size == .full)
    }

    @Test func `it jumps back up past a size when there's room for the largest`() {
        var fit = SessionCardFit(size: .minimal)
        do {
            let changed = fit.update(largest: .full, measured: 450, room: 2000, cards: Self.cards, contents: 1)
            #expect(changed)
        }
        #expect(fit.size == .full)
    }

    @Test func `a size that didn't fit isn't tried again for the same sessions`() {
        var fit = SessionCardFit(size: .full)
        // The guess said Full would fit, but drawn it's taller than the room.
        fit.update(largest: .full, measured: 900, room: 800, cards: Self.cards, contents: 7)
        #expect(fit.size == .compact)
        // At Compact the guess for Full (450 - 660 + 1110 = 900) is over the room anyway; with a
        // guess that says it fits, the same contents still don't go back.
        let short: (CalmSettings.SessionCardSize) -> Double = { _ in 0 }
        do {
            let changed = fit.update(largest: .full, measured: 450, room: 800, cards: short, contents: 7)
            #expect(!changed)
        }
        #expect(fit.size == .compact)
        // Different sessions (or room) try it again.
        do {
            let changed = fit.update(largest: .full, measured: 450, room: 800, cards: short, contents: 8)
            #expect(changed)
        }
        #expect(fit.size == .full)
    }

    @Test func `it never goes above the size chosen`() {
        var fit = SessionCardFit(size: .full)
        do {
            let changed = fit.update(largest: .compact, measured: 300, room: 2000, cards: Self.cards, contents: 1)
            #expect(changed)
        }
        #expect(fit.size == .compact)
        do {
            let changed = fit.update(largest: .compact, measured: 300, room: 2000, cards: Self.cards, contents: 1)
            #expect(!changed)
        }
        #expect(fit.size == .compact)
        // A larger choice lets it grow again.
        do {
            let changed = fit.update(largest: .full, measured: 300, room: 2000, cards: Self.cards, contents: 1)
            #expect(changed)
        }
        #expect(fit.size == .full)
    }

    @Test func `sizes know their order`() {
        #expect(CalmSettings.SessionCardSize.full.smaller == .compact)
        #expect(CalmSettings.SessionCardSize.compact.smaller == .minimal)
        #expect(CalmSettings.SessionCardSize.minimal.smaller == nil)
        #expect(CalmSettings.SessionCardSize.full.rank < CalmSettings.SessionCardSize.minimal.rank)
    }
}

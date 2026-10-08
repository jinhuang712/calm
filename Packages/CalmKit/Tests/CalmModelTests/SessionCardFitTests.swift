import CalmModel
import Testing

struct SessionCardFitTests {
    typealias Size = CalmSettings.SessionCardSize

    /// Ten working cards with recaps, as the guess sees them.
    private static func cards(_ size: Size) -> Double {
        10 * SessionCardLayout.nominalHeight(size: size, state: .working, hasRecap: true, hasProgress: false, hasWorktree: false)
    }

    /// One update; whether the size changed.
    private func step(
        _ fit: inout SessionCardFit, _ measured: Double, in room: Double, contents: Int, at now: Double,
        largest: Size = .full, cards: (Size) -> Double = Self.cards,
    ) -> Bool {
        fit.update(largest: largest, measured: measured, room: room, cards: cards, contents: contents, now: now)
    }

    @Test func `the guessed heights are the drawn ones`() {
        func height(_ size: Size, _ state: SessionState, progress: Bool = false, worktree: Bool = false) -> Double {
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

    @Test func `an idle card whose agent left shells running is guessed with its line`() {
        func height(_ size: Size, recap: Bool) -> Double {
            SessionCardLayout.nominalHeight(
                size: size, state: .idle, hasRecap: recap, hasProgress: false, hasWorktree: false, shellsRunning: true,
            )
        }
        #expect(height(.compact, recap: true) == 66)
        #expect(height(.full, recap: true) == 65)
        // The shells alone still make Full's line.
        #expect(height(.full, recap: false) == 65)
        #expect(height(.minimal, recap: true) == 40)
    }

    @Test func `too many sessions step the cards down one size at a time`() {
        var fit = SessionCardFit(size: .full)
        #expect(step(&fit, 1200, in: 700, contents: 1, at: 0))
        #expect(fit.size == .compact)
        #expect(step(&fit, 750, in: 700, contents: 1, at: 0.1))
        #expect(fit.size == .minimal)
        // Minimal is as small as it goes: the list scrolls.
        #expect(!step(&fit, 720, in: 700, contents: 1, at: 0.2))
        #expect(fit.size == .minimal)
    }

    @Test func `fewer sessions bring the larger size back`() {
        var fit = SessionCardFit(size: .full)
        _ = step(&fit, 1200, in: 800, contents: 1, at: 0)
        // Compact fits (750); drawn at once, it also tells how good the guess for Full was
        // (750 - 660 + 1110 = 1200: exact).
        #expect(!step(&fit, 750, in: 800, contents: 1, at: 0.1))
        #expect(fit.size == .compact)
        // Sessions closed: Compact is 400, so Full would be 850, over the room less the margin...
        #expect(!step(&fit, 400, in: 800, contents: 2, at: 40))
        // ...until the room grows.
        #expect(step(&fit, 400, in: 900, contents: 3, at: 41))
        #expect(fit.size == .full)
    }

    @Test func `after a step down the cards stay down a while`() {
        var fit = SessionCardFit(size: .full)
        _ = step(&fit, 900, in: 800, contents: 1, at: 100)
        #expect(fit.size == .compact)
        // Room right away (sessions closed: Full would be 750), but the sidebar doesn't change shape again yet.
        #expect(!step(&fit, 300, in: 800, contents: 2, at: 110))
        #expect(fit.growsAgain(after: 110) == 100 + SessionCardFit.settle)
        #expect(step(&fit, 300, in: 800, contents: 2, at: 100 + SessionCardFit.settle))
        #expect(fit.size == .full)
        #expect(fit.growsAgain(after: 200) == nil)
    }

    @Test func `a first layout in a smaller room doesn't keep the cards down`() {
        // The author's restart: the sidebar was laid out once in the window's saved frame (592 pt
        // of room) before the window filled the screen again (1001). Full is 998 there: it fit
        // before the restart, and came back as Compact for good.
        var fit = SessionCardFit(size: .full)
        _ = step(&fit, 998, in: 592, contents: 1, at: 0)
        _ = step(&fit, 738, in: 592, contents: 1, at: 0.01)
        #expect(fit.size == .minimal)
        #expect(step(&fit, 560, in: 1001, contents: 1, at: 0.05))
        #expect(fit.size == .full)
        #expect(!step(&fit, 998, in: 1001, contents: 1, at: 0.1))
    }

    @Test func `the window growing ends the wait after a step down`() {
        var fit = SessionCardFit(size: .full)
        _ = step(&fit, 900, in: 800, contents: 1, at: 0)
        _ = step(&fit, 450, in: 800, contents: 1, at: 0.1)
        // Other sessions, so nothing was drawn with them: the guess (900) and its margin decide.
        #expect(!step(&fit, 450, in: 910, contents: 2, at: 1))
        #expect(step(&fit, 450, in: 920, contents: 2, at: 2))
        #expect(fit.size == .full)
    }

    @Test func `the window growing back brings the size it had`() {
        var fit = SessionCardFit(size: .full)
        #expect(!step(&fit, 998, in: 1001, contents: 1, at: 0))
        // Made shorter, then as tall again: Full was drawn 998 tall with these sessions, and
        // 998 fits in 1001 whatever the margin says.
        #expect(step(&fit, 998, in: 900, contents: 1, at: 10))
        _ = step(&fit, 600, in: 900, contents: 1, at: 10.1)
        #expect(!step(&fit, 600, in: 990, contents: 1, at: 11))
        #expect(step(&fit, 600, in: 1001, contents: 1, at: 12))
        #expect(fit.size == .full)
    }

    @Test func `in the same room a size that fit before still keeps the margin`() {
        // Full fit by 3 pt, then an agent's card grew and it didn't; when the card is as it was,
        // the cards stay down: a recap a line longer would take them over again.
        let cards: (Size) -> Double = { $0 == .full ? 700 : $0 == .compact ? 400 : 300 }
        var fit = SessionCardFit(size: .full)
        #expect(!step(&fit, 998, in: 1001, contents: 1, at: 0, cards: cards))
        #expect(step(&fit, 1010, in: 1001, contents: 2, at: 1, cards: cards))
        _ = step(&fit, 710, in: 1001, contents: 2, at: 1.1, cards: cards)
        #expect(!step(&fit, 698, in: 1001, contents: 1, at: 60, cards: cards))
        #expect(fit.size == .compact)
    }

    @Test func `a guess that came out short is corrected the next time`() {
        // What the author's sidebar did: Full drew 1005 pt in 1001, and from Compact (664) the guess
        // for it was 985, 20 pt short, so it kept going back to Full and over.
        let cards: (Size) -> Double = { $0 == .full ? 700 : $0 == .compact ? 379 : 300 }
        var fit = SessionCardFit(size: .full)
        _ = step(&fit, 1005, in: 1001, contents: 1, at: 0, cards: cards)
        #expect(fit.size == .compact)
        _ = step(&fit, 664, in: 1001, contents: 1, at: 0.1, cards: cards)
        // An agent's state changed: without the correction, 985 would fit in 1001 - 16.
        #expect(!step(&fit, 664, in: 1001, contents: 2, at: 60, cards: cards))
        #expect(fit.size == .compact)
        // With real room (1005 + 16 spare) Full comes back.
        #expect(step(&fit, 664, in: 1030, contents: 3, at: 61, cards: cards))
        #expect(fit.size == .full)
    }

    @Test func `at the edge, sessions changing every few seconds don't make the cards flip`() {
        // The author's sidebar for a minute: Full draws 1005 pt in 1001, Compact 664, and the guess
        // for Full from Compact says 985; an agent's state changes every 2 s, no card's height does.
        // Before the fix this went Full, Compact, Full, Compact... at every change.
        let drawn: [Size: Double] = [.full: 1005, .compact: 664, .minimal: 500]
        let cards: (Size) -> Double = { $0 == .full ? 700 : $0 == .compact ? 379 : 300 }
        var fit = SessionCardFit(size: .full)
        var changes = 0
        var now = 0.0
        for tick in 0 ..< 30 {
            // The size just drawn is measured at once, then again at each state change.
            if step(&fit, drawn[fit.size] ?? 0, in: 1001, contents: tick, at: now, cards: cards) {
                changes += 1
                _ = step(&fit, drawn[fit.size] ?? 0, in: 1001, contents: tick, at: now + 0.05, cards: cards)
            }
            now += 2
        }
        #expect(changes == 1)
        #expect(fit.size == .compact)
    }

    @Test func `it doesn't learn from a step down when the sessions changed in between`() {
        var fit = SessionCardFit(size: .full)
        _ = step(&fit, 1200, in: 800, contents: 1, at: 0)
        // Sessions closed before Compact was measured: 1200 against a guess of 850 says nothing
        // about the guess, and learning it would keep Full away for good.
        _ = step(&fit, 400, in: 800, contents: 2, at: 0.1)
        #expect(step(&fit, 400, in: 900, contents: 3, at: 40))
        #expect(fit.size == .full)
    }

    @Test func `a size that didn't fit isn't tried again for the same sessions`() {
        var fit = SessionCardFit(size: .full)
        // The guess said Full would fit, but drawn it's taller than the room.
        _ = step(&fit, 900, in: 800, contents: 7, at: 0)
        #expect(fit.size == .compact)
        // Compact drawn: the guess for Full from here (450 - 660 + 1110 = 900) was exact.
        _ = step(&fit, 450, in: 800, contents: 7, at: 0.1)
        // Long after, with a guess that says it fits, the same contents still don't go back.
        let short: (Size) -> Double = { _ in 0 }
        #expect(!step(&fit, 450, in: 800, contents: 7, at: 100, cards: short))
        #expect(fit.size == .compact)
        // More room, but less than Full was drawn at: still not.
        #expect(!step(&fit, 450, in: 880, contents: 7, at: 100.5, cards: short))
        // Different sessions try it again.
        #expect(step(&fit, 450, in: 800, contents: 8, at: 101, cards: short))
        #expect(fit.size == .full)
    }

    @Test func `a size that didn't fit fits once the room is as tall as it was drawn`() {
        var fit = SessionCardFit(size: .full)
        _ = step(&fit, 900, in: 800, contents: 7, at: 0)
        _ = step(&fit, 450, in: 800, contents: 7, at: 0.1)
        #expect(step(&fit, 450, in: 900, contents: 7, at: 100))
        #expect(fit.size == .full)
    }

    @Test func `it jumps back up past a size when there's room for the largest`() {
        var fit = SessionCardFit(size: .minimal)
        #expect(step(&fit, 450, in: 2000, contents: 1, at: 0))
        #expect(fit.size == .full)
    }

    @Test func `it never goes above the size chosen`() {
        var fit = SessionCardFit(size: .full)
        #expect(step(&fit, 300, in: 2000, contents: 1, at: 0, largest: .compact))
        #expect(fit.size == .compact)
        #expect(!step(&fit, 300, in: 2000, contents: 1, at: 1, largest: .compact))
        #expect(fit.size == .compact)
        // A larger choice lets it grow again.
        #expect(step(&fit, 300, in: 2000, contents: 1, at: 2))
        #expect(fit.size == .full)
    }

    @Test func `sizes know their order`() {
        #expect(Size.full.smaller == .compact)
        #expect(Size.compact.smaller == .minimal)
        #expect(Size.minimal.smaller == nil)
        #expect(Size.full.rank < Size.minimal.rank)
    }
}

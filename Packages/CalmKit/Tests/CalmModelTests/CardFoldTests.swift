import CalmModel
import Testing

struct CardFoldTests {
    @Test func `from Full the idle cards fold first, then the busy ones, then all go Minimal`() {
        #expect(CardFold.steps(from: .full) == [
            CardFold(.full), CardFold(quiet: .compact, busy: .full), CardFold(.compact), CardFold(.minimal),
        ])
    }

    @Test func `below Full an idle card is one line already, so every card steps together`() {
        #expect(CardFold.steps(from: .compact) == [CardFold(.compact), CardFold(.minimal)])
        #expect(CardFold.steps(from: .minimal) == [CardFold(.minimal)])
    }

    @Test func `only an idle card with nothing running is quiet`() {
        let fold = CardFold(quiet: .compact, busy: .full)
        #expect(fold.size(state: .idle, shellsRunning: false) == .compact)
        #expect(fold.size(state: .idle, shellsRunning: true) == .full)
        for state in [SessionState.working, .needsYou, .done, .failed] {
            #expect(fold.size(state: state, shellsRunning: false) == .full)
        }
    }

    @Test func `the trace names the fold`() {
        #expect(CardFold(.full).description == "full")
        #expect(CardFold(quiet: .compact, busy: .full).description == "full (idle compact)")
    }
}

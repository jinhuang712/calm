import CalmModel
import Testing

struct SessionCardLayoutTests {
    @Test func `full is today's card`() {
        #expect(SessionCardLayout(size: .full, state: .idle) == .recap(lines: 1))
        for state in [SessionState.working, .needsYou, .done, .failed] {
            #expect(SessionCardLayout(size: .full, state: state) == .stacked)
        }
    }

    @Test func `compact puts the state and the recap on one line, and idle is the title alone`() {
        #expect(SessionCardLayout(size: .compact, state: .idle) == .titleOnly)
        #expect(SessionCardLayout(size: .compact, state: .working) == .merged(lines: 1))
    }

    @Test func `minimal is the title alone unless the card waits for a look`() {
        #expect(SessionCardLayout(size: .minimal, state: .idle) == .titleOnly)
        #expect(SessionCardLayout(size: .minimal, state: .working) == .titleOnly)
    }

    @Test func `a card that waits for a look grows a line at the smaller sizes`() {
        for state in [SessionState.needsYou, .done, .failed] {
            #expect(SessionCardLayout(size: .compact, state: state) == .merged(lines: 2))
            #expect(SessionCardLayout(size: .minimal, state: state) == .recap(lines: 1))
        }
    }

    @Test func `it settles once the agent works again or the card is seen`() {
        // Answering puts needs you back to work; leaving a done or failed card makes it idle.
        #expect(SessionCardLayout(size: .compact, state: .needsYou) != SessionCardLayout(size: .compact, state: .working))
        for state in [SessionState.done, .failed] {
            #expect(SessionCardLayout(size: .minimal, state: state.afterVisit()).isOneLine)
        }
    }

    @Test func `working and idle never wait for a look`() {
        #expect(SessionCardLayout.waitsForALook(.working) == false)
        #expect(SessionCardLayout.waitsForALook(.idle) == false)
        #expect(SessionCardLayout.waitsForALook(.needsYou))
    }
}

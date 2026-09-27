@testable import CalmModel
import Testing

struct SessionStateTests {
    @Test func `only needs you may interrupt`() {
        let interrupting = SessionState.allCases.filter(\.mayInterrupt)
        #expect(interrupting == [.needsYou])
    }

    @Test(arguments: [
        (SessionState.done, SessionState.idle),
        (.failed, .idle),
        (.idle, .idle),
        (.working, .working),
        (.needsYou, .needsYou),
    ])
    func `visit settles finished states`(before: SessionState, after: SessionState) {
        #expect(before.afterVisit() == after)
    }
}

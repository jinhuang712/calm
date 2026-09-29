import CalmModel
import Foundation
import Testing

struct NoSessionContentTests {
    private let project = UUID()

    private func session(_ state: SessionState, at seconds: TimeInterval = 0) -> Session {
        var session = Session(projectID: project, workingDirectory: "/tmp", state: state)
        session.lastReport = StatusReport(state: state, source: .hook, date: Date(timeIntervalSince1970: seconds))
        return session
    }

    private func waiting(_ content: NoSessionContent) -> NoSessionContent.Waiting? {
        if case let .waiting(waiting) = content {
            return waiting
        }
        return nil
    }

    @Test func `a session that waits for a look puts it in the middle`() {
        let done = session(.done)
        let content = NoSessionContent.choose(sessions: [session(.working), done, session(.idle)], current: nil, searched: false)
        #expect(waiting(content)?.sessionIDs == [done.id])
        #expect(waiting(content)?.stillWorking == 1)
    }

    @Test func `with nothing waiting the page is the search and lists`() {
        let sessions = [session(.working), session(.idle)]
        #expect(NoSessionContent.choose(sessions: sessions, current: nil, searched: false) == .lists)
    }

    @Test func `needs you, done and failed all wait; working and idle don't`() {
        for state in [SessionState.needsYou, .done, .failed] {
            #expect(waiting(NoSessionContent.choose(sessions: [session(state)], current: nil, searched: false)) != nil)
        }
        for state in [SessionState.working, .idle] {
            #expect(NoSessionContent.choose(sessions: [session(state)], current: nil, searched: false) == .lists)
        }
    }

    @Test func `questions come first, then finished turns, each newest first`() {
        let oldDone = session(.done, at: 10)
        let newDone = session(.done, at: 30)
        let oldAsk = session(.needsYou, at: 5)
        let newFailed = session(.failed, at: 40)
        let content = NoSessionContent.choose(sessions: [oldDone, newDone, oldAsk, newFailed], current: nil, searched: false)
        #expect(waiting(content)?.sessionIDs == [oldAsk.id, newFailed.id, newDone.id])
        #expect(waiting(content)?.moreWaiting == 1)
    }

    @Test func `once the user has searched, a session finishing keeps the lists`() {
        let sessions = [session(.done)]
        #expect(NoSessionContent.choose(sessions: sessions, current: .lists, searched: true) == .lists)
        // Not searched yet: the page moves to what's waiting.
        #expect(waiting(NoSessionContent.choose(sessions: sessions, current: .lists, searched: false)) != nil)
    }

    @Test func `the last waiting session going makes it the lists`() {
        let before = NoSessionContent.choose(sessions: [session(.done)], current: nil, searched: false)
        #expect(NoSessionContent.choose(sessions: [session(.idle)], current: before, searched: false) == .lists)
    }

    @Test func `the card the keys are on stays chosen while it's there, else the first`() {
        let (first, second, gone) = (UUID(), UUID(), UUID())
        let waiting = NoSessionContent.Waiting(sessionIDs: [first, second], moreWaiting: 0, stillWorking: 0)
        #expect(waiting.keeping(second) == second)
        #expect(waiting.keeping(gone) == first)
        #expect(waiting.keeping(nil) == first)
    }

    @Test func `the arrow keys move through the cards and stop at either end`() {
        let (first, second) = (UUID(), UUID())
        let waiting = NoSessionContent.Waiting(sessionIDs: [first, second], moreWaiting: 0, stillWorking: 0)
        #expect(waiting.step(from: first, by: 1) == second)
        #expect(waiting.step(from: second, by: 1) == second)
        #expect(waiting.step(from: first, by: -1) == first)
        #expect(waiting.step(from: nil, by: 1) == first)
    }

    @Test func `the footnote counts what isn't shown and what still works`() {
        #expect(NoSessionContent.Waiting(sessionIDs: [], moreWaiting: 2, stillWorking: 5).footnote == "2 more waiting · 5 still working")
        #expect(NoSessionContent.Waiting(sessionIDs: [], moreWaiting: 0, stillWorking: 1).footnote == "1 still working")
        #expect(NoSessionContent.Waiting(sessionIDs: [], moreWaiting: 1, stillWorking: 0).footnote == "1 more waiting")
        #expect(NoSessionContent.Waiting(sessionIDs: [], moreWaiting: 0, stillWorking: 0).footnote == nil)
    }
}

@testable import CalmModel
import Testing

struct GroupSummaryTests {
    /// The line as marks and numbers: "working×3" for three rings, "working 4" for a ring and a 4.
    private func line(_ states: [SessionState]) -> [String] {
        GroupSummary(states).runs.map { run in
            run.showsCount ? "\(run.state) \(run.count)" : "\(run.state)×\(run.marks)"
        }
    }

    @Test func `working agents show in a folded group`() {
        // The report that started it: three agents working, and the line said "5 sessions".
        #expect(line([.idle, .working, .working, .working, .idle]) == ["working×3"])
    }

    @Test func `up to three get a mark each, four or more one mark and the number`() {
        #expect(line([.working]) == ["working×1"])
        #expect(line(Array(repeating: .working, count: 3)) == ["working×3"])
        #expect(line(Array(repeating: .working, count: 4)) == ["working 4"])
        #expect(line(Array(repeating: .working, count: 12)) == ["working 12"])
    }

    @Test func `the most urgent state comes first`() {
        let states: [SessionState] = [.working, .done, .idle, .failed, .needsYou, .working]
        #expect(line(states) == ["needsYou×1", "failed×1", "done×1", "working×2"])
    }

    @Test func `idle sessions show only when nothing else is going on`() {
        #expect(line([.idle, .done]) == ["done×1"])
        #expect(line([.idle, .idle]) == ["idle×2"])
        #expect(line(Array(repeating: .idle, count: 7)) == ["idle 7"])
    }

    @Test func `an empty group has nothing to say`() {
        #expect(GroupSummary([]).runs.isEmpty)
        #expect(GroupSummary([]).tally.isEmpty)
    }

    @Test func `the words count every state, idle included`() {
        let tally = GroupSummary([.idle, .working, .working, .working, .idle]).tally
        #expect(tally == [.init(state: .working, count: 3), .init(state: .idle, count: 2)])
    }

    @Test func `only needs you tints the line`() {
        #expect(GroupSummary([.working, .needsYou]).needsYou)
        for state in SessionState.allCases where state != .needsYou {
            #expect(!GroupSummary([state, state]).needsYou)
        }
    }
}

@testable import Calm
import CalmModel
import Testing

struct SessionCardTests {
    @Test func `time since last activity is short`() {
        #expect(RelativeTimeText.format(5) == "now")
        #expect(RelativeTimeText.format(125) == "2m")
        #expect(RelativeTimeText.format(3 * 3600 + 5) == "3h")
        #expect(RelativeTimeText.format(4 * 86400) == "4d")
    }

    @Test func `every state has a label and every agent a letter mark`() {
        #expect(SessionState.needsYou.label == "Needs you")
        for state in SessionState.allCases {
            #expect(!state.label.isEmpty)
        }
        for agent in AgentKind.allCases {
            #expect(agent.monogram.count == 1)
        }
    }
}

@testable import Calm
import CalmModel
import Foundation
import Testing

struct SessionCardTests {
    @Test func `time since last activity is short`() {
        #expect(RelativeTimeText.format(5) == "now")
        #expect(RelativeTimeText.format(125) == "2m")
        #expect(RelativeTimeText.format(3 * 3600 + 5) == "3h")
        #expect(RelativeTimeText.format(4 * 86400) == "4d")
    }

    @MainActor @Test func `working says how long, unless the agent names its step`() {
        var session = Session(projectID: UUID(), workingDirectory: "/tmp", state: .working)
        let start = Date(timeIntervalSince1970: 1000)
        session.stateSince = start
        let card = SessionCard(session: session, agent: .claudeCode, isSelected: false, style: .derived(from: .black))
        #expect(card.workingLine(at: start + 20) == "Working")
        #expect(card.workingLine(at: start + 4 * 60 + 5) == "Working · 4m")
        #expect(card.workingLine(at: start + 2 * 3600) == "Working · 2h")
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

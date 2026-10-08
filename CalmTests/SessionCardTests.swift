import AppKit
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

    @MainActor @Test func `working says what the agent is doing, and its todo keeps a line of its own`() {
        var session = Session(projectID: UUID(), workingDirectory: "/tmp", state: .working)
        session.stateSince = Date(timeIntervalSinceNow: -10 * 60)
        let style = SidebarStyle.derived(from: .black)
        let live = LiveLineBox()
        func line() -> String {
            SessionCard(session: session, agent: .claudeCode, isSelected: false, style: style, live: live).workingLine
        }
        // An agent whose hooks don't say.
        #expect(line() == "Working")
        live.set(LiveLine(thinkingAt: Date(timeIntervalSinceNow: -60)))
        #expect(line() == "Thinking")
        session.agent = AgentRun(kind: .claudeCode, processID: 0)
        session.agent?.tail = TranscriptTail(step: "Adding tests", progress: TodoProgress(done: 2, total: 5))
        // The todo isn't on the line any more: it's the quiet line under it.
        #expect(line() == "Thinking")
        #expect(session.todoLine == "2 of 5 · Adding tests")
    }

    @MainActor @Test func `only minimal cards color the time, and never while restoring`() {
        let style = SidebarStyle.derived(from: .black)
        func card(_ state: SessionState, _ size: CalmSettings.SessionCardSize, restoring: Bool = false) -> SessionCard {
            let session = Session(projectID: UUID(), workingDirectory: "/tmp", state: state)
            return SessionCard(session: session, agent: .claudeCode, isSelected: false, style: style, size: size, isConfirming: restoring)
        }
        #expect(card(.needsYou, .minimal).timeColor == style.attention)
        #expect(card(.working, .minimal).timeColor == style.working)
        #expect(card(.needsYou, .compact).timeColor == nil)
        #expect(card(.needsYou, .full).timeColor == nil)
        #expect(card(.needsYou, .minimal, restoring: true).timeColor == nil)
        #expect(card(.idle, .minimal).timeColor == nil)
    }

    @MainActor @Test func `the selected card wears one ring in every state, and no other card does`() {
        let style = SidebarStyle.derived(from: .black)
        for state in SessionState.allCases {
            let session = Session(projectID: UUID(), workingDirectory: "/tmp", state: state)
            let selected = SessionCard(session: session, agent: .claudeCode, isSelected: true, style: style)
            let other = SessionCard(session: session, agent: .claudeCode, isSelected: false, style: style)
            #expect(selected.border == style.selectionEdge)
            #expect(other.border != style.selectionEdge)
        }
    }

    @MainActor @Test func `the ring around the selected card is stronger with Increase Contrast`() {
        let style = SidebarStyle.derived(from: .black)
        let ring = NSColor(style.selectionEdge).alphaComponent
        let contrasted = NSColor(style.contrasted(true).selectionEdge).alphaComponent
        #expect(ring > 0.2)
        #expect(contrasted > ring)
    }

    @MainActor @Test func `a state's own edge stays far fainter than the selection ring`() {
        let style = SidebarStyle.derived(from: .black)
        let ring = NSColor(style.selectionEdge).alphaComponent
        for state in [SessionState.needsYou, .working, .done] {
            let session = Session(projectID: UUID(), workingDirectory: "/tmp", state: state)
            let card = SessionCard(session: session, agent: .claudeCode, isSelected: false, style: style)
            #expect(NSColor(card.border).alphaComponent < ring / 3)
        }
    }

    @Test func `the selected surface is lifted lighter in both themes`() {
        for background in [NSColor.black, NSColor.white] {
            let lift = NSColor(SidebarStyle.derived(from: background).selectionLift).usingColorSpace(.sRGB)
            #expect(lift?.brightnessComponent == 1)
            #expect((lift?.alphaComponent ?? 0) > 0)
        }
    }

    @Test func `the shrink to fit line names the size the cards come back to`() {
        #expect(SessionCardsPicker.fitNote(.full) == "Cards step down from Full when the sessions don't fit, and back when there's room.")
        #expect(SessionCardsPicker.fitNote(.compact).contains("from Compact"))
        // Nothing smaller than Minimal: the line says so instead of promising a step.
        #expect(!SessionCardsPicker.fitNote(.minimal).contains("step down from"))
    }

    @Test func `a finished turn says how many shells it left running`() {
        #expect(SessionCard.shellsLine(0) == nil)
        #expect(SessionCard.shellsLine(-1) == nil)
        #expect(SessionCard.shellsLine(1) == "1 shell running")
        #expect(SessionCard.shellsLine(2) == "2 shells running")
    }

    @Test func `a long title glides at reading pace, never in a jolt`() {
        #expect(ScrollingTitle.scrollDuration(overflow: 4) == 0.6)
        #expect(ScrollingTitle.scrollDuration(overflow: 80) == 2)
        #expect(ScrollingTitle.scrollDuration(overflow: 200) == 5)
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

    @Test func `a folded group's line says itself in words`() {
        #expect(GroupSummary([.idle, .working, .working, .working, .idle]).words == "3 working, 2 idle")
        #expect(GroupSummary([.done, .needsYou]).words == "1 needs you, 1 done")
        #expect(GroupSummary([]).words == "No sessions")
    }
}

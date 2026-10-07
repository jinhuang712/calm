@testable import Calm
import CalmAgents
import CalmModel
import Foundation
import Testing

/// What the Calm-drawn session menu holds, how its keys move, and where it opens
/// (UIUX.md → Session cards → The session menu).
@MainActor
struct SessionMenuTests {
    private let home = Project(path: "/tmp/app", kind: .directory)
    private let other = Project(path: "/tmp/web", name: "web")

    private func running(_ kind: AgentKind = .claudeCode, state: SessionState = .idle) -> Session {
        var session = Session(projectID: home.id, workingDirectory: "/tmp/app")
        session.agent = AgentRun(kind: kind, processID: 4242)
        session.agent?.agentSessionID = "abc"
        session.state = state
        return session
    }

    private func menu(
        _ session: Session, phase: RestartPhase? = nil, update: AgentUpdate? = nil, version: String? = "2.1.291", front: Bool = true,
    ) -> SessionMenuContent {
        .make(for: session, phase: phase, update: update, runningVersion: version, projects: [home, other], isFront: front)
    }

    @Test func `a running Claude Code gets its name, version and three tiles, then the rows`() {
        let content = menu(running())
        #expect(content.header == .init(agent: .claudeCode, version: "2.1.291"))
        #expect(content.tiles.map(\.title) == ["Restart", "Fork", "Fork"])
        #expect(content.tiles.map(\.detail) == ["now", "new split", "new tab"])
        #expect(content.groups.map(\.label) == [nil, "COPY", nil, nil])
        #expect(content.rows.map(\.title) == [
            "Rename…", "Session ID", "Resume Command", "Folder Path", "Open in Finder", "Move to Project", "Close Session",
        ])
        #expect(content.projects.map(\.name) == ["web"])
    }

    @Test func `the restart tile says what choosing it does now`() {
        #expect(menu(running(state: .working)).tiles[0].detail == "after turn")
        #expect(menu(running(state: .needsYou)).tiles[0].name == "Restart Claude Code After This Turn")
        let waiting = menu(running(state: .working), phase: .afterTurn).tiles[0]
        #expect(waiting.title == "Don't Restart")
        #expect(waiting.action == .cancelRestart)
        let underway = menu(running(), phase: .restarting).tiles[0]
        #expect(underway.title == "Restarting…")
        #expect(underway.action == nil)
    }

    @Test func `a newer version waiting puts Restart in amber with the version`() {
        let tile = menu(running(), update: AgentUpdate(installed: "2.1.292", running: "2.1.291")).tiles[0]
        #expect(tile.amber)
        #expect(tile.detail == "↑ 2.1.292")
        #expect(menu(running(), update: AgentUpdate(installed: nil, running: nil)).tiles[0].detail == "↑ new version")
        // Mid-turn the detail says when; the amber still says why.
        let busy = menu(running(state: .working), update: AgentUpdate(installed: "2.1.292", running: nil)).tiles[0]
        #expect(busy.detail == "after turn")
        #expect(busy.amber)
    }

    @Test func `an agent that exited offers Resume in Restart's place`() {
        var session = Session(projectID: home.id, workingDirectory: "/tmp/app")
        session.lastConversation = AgentConversation(kind: .claudeCode, agentSessionID: "abc", transcriptPath: nil)
        let content = menu(session)
        #expect(content.tiles.map(\.title) == ["Resume", "Fork", "Fork"])
        #expect(content.header == .init(agent: .claudeCode, version: nil))
    }

    @Test func `an agent Calm can't restart keeps its fork tiles`() {
        let content = menu(running(.codex))
        #expect(content.tiles.map(\.title) == ["Fork", "Fork"])
        #expect(content.header?.agent == .codex)
    }

    @Test func `a plain shell has no header or tiles, and one copy without a label`() {
        let content = menu(Session(projectID: home.id, workingDirectory: "/tmp/app"))
        #expect(content.header == nil)
        #expect(content.tiles.isEmpty)
        #expect(content.rows.map(\.title) == ["Rename…", "Copy Folder Path", "Open in Finder", "Move to Project", "Close Session"])
        #expect(content.groups.allSatisfy { $0.label == nil })
    }

    @Test func `a scratch session is kept as a project, and has no folder to give`() {
        var session = Session(projectID: home.id, workingDirectory: "/tmp/scratch")
        session.scratchFolder = "/tmp/scratch"
        #expect(menu(session).rows.map(\.title) == ["Rename…", "Keep as Project…", "Close Session"])
    }

    @Test func `⌘W shows only where it closes this session`() {
        #expect(menu(running(), front: true).rows.last?.key == "⌘W")
        #expect(menu(running(), front: false).rows.last?.key == nil)
    }

    // MARK: Keys

    @Test func `the tiles are a row, and the rows a column`() {
        let content = menu(running())
        #expect(content.next(from: nil, key: .down) == 0)
        #expect(content.next(from: 0, key: .right) == 1)
        #expect(content.next(from: 2, key: .right) == 2)
        #expect(content.next(from: 1, key: .left) == 0)
        #expect(content.next(from: 1, key: .down) == 3)
        #expect(content.next(from: 3, key: .up, lastTile: 1) == 1)
        #expect(content.next(from: 4, key: .up) == 3)
        #expect(content.next(from: content.itemCount - 1, key: .down) == content.itemCount - 1)
        #expect(content.next(from: nil, key: .up) == content.itemCount - 1)
    }

    @Test func `a letter jumps to the next item starting with it`() {
        let content = menu(running())
        #expect(content.item(startingWith: "f", after: nil) == 1)
        #expect(content.item(startingWith: "f", after: 1) == 2)
        #expect(content.item(startingWith: "f", after: 2) == 6)
        #expect(content.item(startingWith: "z", after: nil) == nil)
    }

    @Test func `the move row opens the projects list, and has no action of its own`() throws {
        let content = menu(running())
        let move = try #require(content.rows.firstIndex { $0.title == "Move to Project" }) + content.tiles.count
        #expect(content.opensProjects(at: move))
        #expect(content.action(at: move) == nil)
        #expect(content.action(at: 0) == .restart)
    }

    // MARK: Placement

    @Test func `under the button the menu's right edge is the button's`() {
        let origin = SessionMenuOverlay.origin(
            for: .below(CGRect(x: 900, y: 10, width: 30, height: 26)),
            size: CGSize(width: 288, height: 400),
            in: CGSize(width: 1200, height: 760),
        )
        #expect(origin == CGPoint(x: 642, y: 40))
    }

    @Test func `at the pointer it opens below, or above when there's no room`() {
        let size = CGSize(width: 288, height: 400)
        let bounds = CGSize(width: 1200, height: 760)
        #expect(SessionMenuOverlay.origin(for: .point(CGPoint(x: 100, y: 120)), size: size, in: bounds) == CGPoint(x: 102, y: 122))
        #expect(SessionMenuOverlay.origin(for: .point(CGPoint(x: 100, y: 700)), size: size, in: bounds) == CGPoint(x: 102, y: 298))
        // Near the right edge it moves in, never past the window.
        #expect(SessionMenuOverlay.origin(for: .point(CGPoint(x: 1150, y: 120)), size: size, in: bounds).x == CGFloat(904))
    }

    @Test func `the projects list opens to the right, or the left at the window's edge`() {
        let row = CGRect(x: 7, y: 300, width: 274, height: 28)
        let list = CGSize(width: 200, height: 100)
        let bounds = CGSize(width: 1200, height: 760)
        #expect(SessionMenuOverlay.projectsOrigin(
            menu: CGPoint(x: 100, y: 50),
            menuSize: CGSize(width: 288, height: 400),
            row: row,
            size: list,
            in: bounds,
        ).x == 392)
        #expect(SessionMenuOverlay.projectsOrigin(
            menu: CGPoint(x: 900, y: 50),
            menuSize: CGSize(width: 288, height: 400),
            row: row,
            size: list,
            in: bounds,
        ).x == 696)
    }
}

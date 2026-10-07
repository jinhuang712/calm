import CalmAgents
import CalmModel
import Foundation

/// What the session menu holds for one session (UIUX.md → Session cards → The session menu),
/// worked out once when it opens: the agent's actions as tiles under its name, then the rest as
/// rows in groups. The ⋯ button and a right-click on a card open the same menu. Only what applies
/// is there: the agent's actions where its agent has the command, the copies and the folder where
/// there is something to give (`SessionActionSet`, which ⌘P reads too).
struct SessionMenuContent: Equatable {
    enum Action: Hashable {
        case restart, cancelRestart, resume, forkSplit, forkTab
        case rename, copy(SessionCopy), openFolder, keepScratch, moveTo(Project.ID), followFolder, close
    }

    /// The agent the tiles belong to, and the version running, when its path names one.
    struct Header: Equatable {
        var agent: AgentKind
        var version: String?
    }

    /// An agent action: a verb, then what it does now ("Restart" over "after turn").
    struct Tile: Equatable {
        /// Nil while it can't be chosen (a restart under way).
        var action: Action?
        var title: String
        var detail: String
        var symbol: String
        /// A newer version is installed: the tile wears the update hint's amber.
        var amber = false
        /// The whole name, for the tooltip and VoiceOver: what ⌘P calls the same action.
        var name: String
    }

    struct Row: Equatable {
        var action: Action?
        var title: String
        var symbol: String
        /// The key that does it, only where it means this session (⌘W closes the one in front).
        var key: String?
        /// Opens the list of projects beside the menu.
        var opensProjects = false
    }

    struct Group: Equatable {
        /// A small-caps label over the group ("COPY"), like the sidebar's group headers.
        var label: String?
        var rows: [Row]
    }

    var header: Header?
    var tiles: [Tile] = []
    var groups: [Group] = []
    /// Where Move to Project can move it.
    var projects: [Project] = []

    /// The rows in order, after the tiles: what ↑ ↓ step through.
    var rows: [Row] {
        groups.flatMap(\.rows)
    }

    var itemCount: Int {
        tiles.count + rows.count
    }

    /// The title of the item at `index` (tiles first, then rows), for type-to-select and logs.
    func title(at index: Int) -> String? {
        if index < tiles.count {
            return tiles[index].title
        }
        let rows = rows
        return rows.indices.contains(index - tiles.count) ? rows[index - tiles.count].title : nil
    }

    func action(at index: Int) -> Action? {
        if index < tiles.count {
            return tiles[index].action
        }
        let rows = rows
        return rows.indices.contains(index - tiles.count) ? rows[index - tiles.count].action : nil
    }

    func opensProjects(at index: Int) -> Bool {
        let rows = rows
        return index >= tiles.count && rows.indices.contains(index - tiles.count) && rows[index - tiles.count].opensProjects
    }
}

extension SessionMenuContent {
    /// The menu for `session`. `phase` and `update` are the restart and the version news the
    /// title strip shows too; `isFront` says whether ⌘W would close this session.
    @MainActor
    static func make(
        for session: Session, phase: RestartPhase?, update: AgentUpdate?, runningVersion: String?, projects: [Project], isFront: Bool,
    ) -> SessionMenuContent {
        let available = SessionActionSet(session)
        var content = SessionMenuContent()

        if let kind = available.restarts {
            content.tiles.append(restartTile(kind, state: session.state, phase: phase, update: update))
        } else if let kind = available.resumes {
            content.tiles.append(Tile(
                action: .resume, title: "Resume", detail: "in this shell", symbol: "arrow.uturn.forward",
                name: "Resume \(kind.displayName) Conversation",
            ))
        }
        if available.forks {
            content.tiles.append(Tile(
                action: .forkSplit,
                title: "Fork",
                detail: "new split",
                symbol: "rectangle.split.2x1",
                name: "Fork into New Split",
            ))
            content.tiles.append(Tile(
                action: .forkTab,
                title: "Fork",
                detail: "new tab",
                symbol: "plus.square.on.square",
                name: "Fork into New Tab",
            ))
        }
        if !content.tiles.isEmpty, let kind = session.agent?.kind ?? session.resumableConversation?.kind {
            content.header = Header(agent: kind, version: session.agent == nil ? nil : runningVersion)
        }

        content.groups.append(Group(rows: [Row(action: .rename, title: "Rename…", symbol: "pencil")]))

        // The agent's copies make a group of their own; a plain shell's one copy needs no label.
        if available.copies.contains(where: { $0 != .folderPath }) {
            content.groups.append(Group(label: "COPY", rows: available.copies.map { copy in
                Row(action: .copy(copy), title: copy.shortTitle, symbol: copy.symbol)
            }))
        } else if available.copies.contains(.folderPath) {
            content.groups.append(Group(rows: [Row(
                action: .copy(.folderPath),
                title: SessionCopy.folderPath.menuTitle,
                symbol: "doc.on.doc",
            )]))
        }

        var place: [Row] = []
        if available.opensFolder {
            place.append(Row(action: .openFolder, title: "Open in Finder", symbol: "arrow.up.forward.square"))
        }
        if available.keepsAsProject {
            place.append(Row(action: .keepScratch, title: "Keep as Project…", symbol: "folder.badge.plus"))
        } else {
            content.projects = projects.filter { $0.kind == .project && $0.id != session.projectID }
            if !content.projects.isEmpty {
                place.append(Row(action: nil, title: "Move to Project", symbol: "square.grid.2x2", opensProjects: true))
            }
            if session.isPinned, projects.contains(where: { $0.id == session.projectID && $0.kind == .project }) {
                place.append(Row(action: .followFolder, title: "Let It Follow Its Folder", symbol: "folder"))
            }
        }
        if !place.isEmpty {
            content.groups.append(Group(rows: place))
        }

        content.groups.append(Group(rows: [Row(action: .close, title: "Close Session", symbol: "xmark", key: isFront ? "⌘W" : nil)]))
        return content
    }

    /// Restart's tile says what choosing it does now; the amber says a newer version waits.
    private static func restartTile(_ kind: AgentKind, state: SessionState, phase: RestartPhase?, update: AgentUpdate?) -> Tile {
        let name = SessionActionSet.restartTitle(kind, state: state, pending: phase == .afterTurn)
        switch phase {
        case .restarting:
            return Tile(
                action: nil,
                title: "Restarting…",
                detail: "one moment",
                symbol: "arrow.clockwise",
                name: "Restarting \(kind.displayName)",
            )
        case .afterTurn:
            return Tile(
                action: .cancelRestart,
                title: "Don't Restart",
                detail: "waiting on turn",
                symbol: "clock.arrow.circlepath",
                name: name,
            )
        case nil:
            let detail = SessionManager.isMidTurn(state) ? "after turn" : update.map { "↑ " + ($0.installed ?? "new version") } ?? "now"
            return Tile(action: .restart, title: "Restart", detail: detail, symbol: "arrow.clockwise", amber: update != nil, name: name)
        }
    }
}

// MARK: Keys

extension SessionMenuContent {
    enum Key {
        case up, down, left, right
    }

    /// Where a key moves the highlight. The tiles are one row: ← → move along them, ↓ leaves them
    /// for the first row, and ↑ from the first row comes back to the tile it left. The rows stop at
    /// either end, as a menu does.
    func next(from index: Int?, key: Key, lastTile: Int = 0) -> Int? {
        guard itemCount > 0 else { return nil }
        let tileCount = tiles.count
        guard let index else {
            switch key {
            case .down, .right, .left: return 0
            case .up: return itemCount - 1
            }
        }
        let inTiles = index < tileCount
        switch key {
        case .left:
            return inTiles ? max(index - 1, 0) : index
        case .right:
            return inTiles ? min(index + 1, tileCount - 1) : index
        case .down:
            return inTiles ? (rows.isEmpty ? index : tileCount) : min(index + 1, itemCount - 1)
        case .up:
            if inTiles {
                return index
            }
            return index == tileCount && tileCount > 0 ? min(lastTile, tileCount - 1) : max(index - 1, 0)
        }
    }

    /// Type-to-select: the next item after `index` whose title starts with `letter`, wrapping.
    func item(startingWith letter: Character, after index: Int?) -> Int? {
        guard itemCount > 0 else { return nil }
        let wanted = String(letter).lowercased()
        let start = (index ?? -1) + 1
        for offset in 0 ..< itemCount {
            let candidate = (start + offset) % itemCount
            if title(at: candidate)?.lowercased().hasPrefix(wanted) == true {
                return candidate
            }
        }
        return nil
    }
}

extension SessionCopy {
    /// The row's words under the COPY label, which already says "Copy".
    var shortTitle: String {
        switch self {
        case .sessionID: "Session ID"
        case .resumeCommand: "Resume Command"
        case .folderPath: "Folder Path"
        }
    }

    var symbol: String {
        switch self {
        case .sessionID: "number"
        case .resumeCommand: "apple.terminal"
        case .folderPath: "doc.on.doc"
        }
    }
}

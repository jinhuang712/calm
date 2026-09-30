import CalmAgents
import CalmModel
import Foundation

/// One row of the ⌘P palette (FEATURES.md → Command palette): what it does, and what to call it.
struct PaletteCommand: Identifiable {
    let id: String
    let title: String
    /// One line on what it does: shown under the list while the row is selected, and found by
    /// typing it (as typed, after every title match).
    var detail = ""
    /// The key that already does it, for the keys only Calm has: the palette teaches them.
    var trailing = ""
    let run: @MainActor () -> Void

    init(id: String, title: String, detail: String = "", trailing: String = "", run: @escaping @MainActor () -> Void) {
        self.id = id
        self.title = title
        self.detail = detail
        self.trailing = trailing
        self.run = run
    }

    /// One of Calm's own rows, with its description.
    init(_ row: PaletteRow, title: String, trailing: String = "", run: @escaping @MainActor () -> Void) {
        self.init(id: row.rawValue, title: title, detail: row.help, trailing: trailing, run: run)
    }
}

/// Calm's own rows, one case each, so that every one has its description: `help` switches over all
/// of them, and a new row without one doesn't compile. The raw value is the row's id. Ghostty's
/// two rows bring the description Ghostty gives them.
enum PaletteRow: String, CaseIterable {
    case forkSplit = "fork-split"
    case forkTab = "fork-tab"
    case resume
    case copyLastReply = "copy-last-reply"
    case copySessionID = "copy-sessionID"
    case copyResumeCommand = "copy-resumeCommand"
    case openTranscript = "open-transcript"
    case markDoneSeen = "mark-done-seen"
    case rename
    case keepScratch = "keep-scratch"
    case jumpWaiting = "jump-waiting"
    case unsplit
    case fileTree = "file-tree"
    case welcome
    case foldAll = "fold-all"
    case unfoldAll = "unfold-all"
    case openFolder = "open-folder"
    case copyFolderPath = "copy-folder-path"
    case randomizeTheme = "randomize-theme"
    case restart
    case agents
    case dumpLogs = "dump-logs"

    /// What the row does, in one short line, in the words of the sidebar and the docs.
    var help: String {
        switch self {
        case .forkSplit: "Start a copy of this conversation in a new split beside it."
        case .forkTab: "Start a copy of this conversation in a new session."
        case .resume: "Pick the conversation that ended here back up, in this shell."
        case .copyLastReply: "Copy the agent's latest message, Markdown and all."
        case .copySessionID: "Copy the agent's own id for this conversation."
        case .copyResumeCommand: "Copy the command that resumes this conversation."
        case .openTranscript: "Open the conversation's file in your editor."
        case .markDoneSeen: "Clear the finished sessions you haven't opened yet."
        case .rename: "Give this session a name of your own."
        case .keepScratch: "Move this scratch folder somewhere and make it a project."
        case .jumpWaiting: "Go to the session that has waited longest for you."
        case .unsplit: "Give each pane a session of its own. Nothing closes."
        case .fileTree: "Show or hide the project's files beside the terminal."
        case .welcome: "Choose no session, to see what waits or to search. Nothing closes."
        case .foldAll: "Collapse every group in the sidebar."
        case .unfoldAll: "Expand every group in the sidebar."
        case .openFolder: "Open this session's folder in Finder."
        case .copyFolderPath: "Copy this session's folder path."
        case .randomizeTheme: "Switch to another Calm theme, chosen by chance."
        case .restart: "Quit and reopen Calm. Your shells keep running."
        case .agents: "Open Settings where agents are connected."
        case .dumpLogs: "Save a diagnostics file for a bug report, and show it in Finder."
        }
    }

    /// The row that copies what `copy` names.
    init(copy: SessionCopy) {
        switch copy {
        case .sessionID: self = .copySessionID
        case .resumeCommand: self = .copyResumeCommand
        case .folderPath: self = .copyFolderPath
        }
    }
}

/// What the session rows call beyond the card menu's own (`SidebarActions`).
struct PaletteSessionActions {
    let rename: @MainActor () -> Void
    let copyLastReply: @MainActor (Session.ID) -> Void
    let openTranscript: @MainActor (Session.ID) -> Void
}

/// The focused session's rows, kept by category so the palette can place each where it belongs.
struct SessionRows {
    var agent: [PaletteCommand] = []
    var session: [PaletteCommand] = []
    var folder: [PaletteCommand] = []
}

extension PaletteCommand {
    /// What the focused session's right-click menu offers, as rows, from the same
    /// `SessionActionSet`, and the two the menu doesn't have (Copy Last Reply, Open Transcript).
    @MainActor
    static func session(_ session: Session, menu: SidebarActions, palette: PaletteSessionActions) -> SessionRows {
        let available = SessionActionSet(session)
        let id = session.id
        var rows = SessionRows()
        if available.forks {
            rows.agent.append(PaletteCommand(.forkSplit, title: "Fork Conversation into New Split") { menu.fork(id, .split) })
            rows.agent.append(PaletteCommand(.forkTab, title: "Fork Conversation into New Tab") { menu.fork(id, .tab) })
        }
        if let kind = available.resumes {
            rows.agent.append(PaletteCommand(.resume, title: "Resume \(kind.displayName) Conversation") { menu.resume(id) })
        }
        if available.transcriptFile != nil {
            rows.agent.append(PaletteCommand(.copyLastReply, title: "Copy Last Reply") { palette.copyLastReply(id) })
        }
        for copy in available.copies where copy != .folderPath {
            rows.agent.append(PaletteCommand(PaletteRow(copy: copy), title: copy.menuTitle) { menu.copy(id, copy) })
        }
        if available.transcriptFile != nil {
            rows.agent.append(PaletteCommand(.openTranscript, title: "Open Transcript") { palette.openTranscript(id) })
        }

        rows.session.append(PaletteCommand(.rename, title: "Rename Session", run: palette.rename))
        if available.keepsAsProject {
            rows.session.append(PaletteCommand(.keepScratch, title: "Keep Scratch Session as Project…") { menu.keepScratch(id) })
        }

        if available.opensFolder {
            rows.folder.append(PaletteCommand(.openFolder, title: "Open Folder in Finder") { menu.openFolder(id) })
        }
        if available.copies.contains(.folderPath) {
            rows.folder.append(PaletteCommand(.copyFolderPath, title: SessionCopy.folderPath.menuTitle) {
                menu.copy(id, .folderPath)
            })
        }
        return rows
    }
}

/// Ranks commands for a query: every query character must appear in order in the title; earlier
/// and denser matches rank higher. A description matches only as typed, after every title match:
/// scattered letters find almost any sentence ("split" found "Toggle whether mouse events are
/// reported to terminal applications").
enum CommandMatcher {
    static func filter(_ commands: [PaletteCommand], query: String) -> [PaletteCommand] {
        let needle = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !needle.isEmpty else { return commands }
        return commands
            .compactMap { command -> (PaletteCommand, Int)? in
                if let score = score(needle, in: command.title.lowercased()) {
                    return (command, score)
                }
                let detail = command.detail.lowercased()
                if let range = detail.range(of: needle) {
                    return (command, 1000 + detail.distance(from: detail.startIndex, to: range.lowerBound))
                }
                return nil
            }
            .sorted { $0.1 < $1.1 }
            .map(\.0)
    }

    /// Lower is better; nil when `needle` isn't a subsequence of `haystack`.
    static func score(_ needle: String, in haystack: String) -> Int? {
        if let range = haystack.range(of: needle) {
            return haystack.distance(from: haystack.startIndex, to: range.lowerBound)
        }
        var score = 100
        var index = haystack.startIndex
        var last: String.Index?
        for character in needle {
            guard let found = haystack[index...].firstIndex(of: character) else { return nil }
            if let last {
                score += haystack.distance(from: last, to: found)
            }
            last = found
            index = haystack.index(after: found)
        }
        return score
    }
}

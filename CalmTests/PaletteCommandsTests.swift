@testable import Calm
import CalmAgents
import CalmModel
import Foundation
import GhosttyKit
import SwiftUI
import Testing

/// What the ⌘P palette offers: Ghostty's entries only from an allowlist, and Calm's own rows by
/// the same rules as the session card's menu.
@MainActor
struct PaletteCommandsTests {
    /// Calm's defaults alone, so the result doesn't depend on the machine's own Ghostty config.
    private func defaultConfig() throws -> TerminalConfig {
        GhosttyRuntime.initializeProcess()
        let file = FileManager.default.temporaryDirectory.appending(path: "calm-palette-\(UUID().uuidString).ghostty")
        defer { try? FileManager.default.removeItem(at: file) }
        let defaults = CalmDefaults.contents(reduceMotion: false, cursorShader: nil, smoothScroll: true)
        try defaults.write(to: file, atomically: true, encoding: .utf8)
        let raw = try #require(ghostty_config_new())
        file.path.withCString { ghostty_config_load_file(raw, $0) }
        ghostty_config_finalize(raw)
        return TerminalConfig(owning: raw)
    }

    /// Fails if a Ghostty release renames one of the two, which would drop it from the palette.
    @Test func `only the two allowed Ghostty entries are offered`() throws {
        let commands = try defaultConfig().commands
        #expect(commands.map(\.action) == TerminalConfig.paletteActions)
        #expect(commands.map(\.title) == ["Reset Terminal", "Toggle Mouse Reporting"])
    }

    // MARK: Session rows

    private struct Calls {
        var renamed = 0
        var forks: [(UUID, MainWindowController.ForkDestination)] = []
        var kept: [UUID] = []
        var lastReplies: [UUID] = []
        var transcripts: [UUID] = []
        var folders: [UUID] = []
    }

    private func rows(for session: Session, calls: Box<Calls> = Box(Calls())) -> SessionRows {
        let menu = SidebarActions(
            rename: { _, _ in }, resume: { _ in }, fork: { calls.value.forks.append(($0, $1)) }, newScratchSession: {},
            showFooter: { _ in }, search: {}, newSessionIn: { _ in }, addProjects: { _ in }, makeProject: { _ in },
            removeProject: { _ in }, move: { _, _ in }, followFolder: { _ in }, keepScratch: { calls.value.kept.append($0) },
            copy: { _, _ in }, openFolder: { calls.value.folders.append($0) },
        )
        let palette = PaletteSessionActions(
            rename: { calls.value.renamed += 1 },
            copyLastReply: { calls.value.lastReplies.append($0) },
            openTranscript: { calls.value.transcripts.append($0) },
        )
        return PaletteCommand.session(session, menu: menu, palette: palette)
    }

    /// A session whose agent's conversation is `kind`'s, its transcript a file that exists (or not).
    private func conversation(_ kind: AgentKind = .claudeCode, transcript: URL?, running: Bool = false) -> Session {
        var session = Session(projectID: UUID(), workingDirectory: "/tmp/app")
        let path = transcript?.path
        if running {
            session.agent = AgentRun(kind: kind, processID: 0)
            session.agent?.agentSessionID = "abc"
            session.agent?.transcriptPath = path
        } else {
            session.lastConversation = AgentConversation(kind: kind, agentSessionID: "abc", transcriptPath: path)
        }
        return session
    }

    private func transcriptFile() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "calm-palette-\(UUID().uuidString).jsonl")
        try Data("{}\n".utf8).write(to: url)
        return url
    }

    @Test func `a plain shell can be renamed, and its folder opened and copied`() {
        let shown = rows(for: Session(projectID: UUID(), workingDirectory: "/tmp/app"))
        #expect(shown.agent.isEmpty)
        #expect(shown.session.map(\.title) == ["Rename Session"])
        #expect(shown.folder.map(\.title) == ["Open Folder in Finder", "Copy Folder Path"])
    }

    @Test func `a scratch session can be kept, and shows no folder`() {
        var session = Session(projectID: UUID(), workingDirectory: "/tmp/scratch")
        session.scratchFolder = "/tmp/scratch"
        let shown = rows(for: session)
        #expect(shown.session.map(\.title) == ["Rename Session", "Keep Scratch Session as Project…"])
        #expect(shown.folder.isEmpty)
    }

    @Test func `an ended conversation can be resumed, forked, copied and opened`() throws {
        let file = try transcriptFile()
        defer { try? FileManager.default.removeItem(at: file) }
        let shown = rows(for: conversation(transcript: file))
        #expect(shown.agent.map(\.title) == [
            "Fork Conversation into New Split", "Fork Conversation into New Tab", "Resume Claude Code Conversation",
            "Copy Last Reply", "Copy Session ID", "Copy Resume Command", "Open Transcript",
        ])
    }

    @Test func `a running agent's conversation can be forked but not resumed`() throws {
        let file = try transcriptFile()
        defer { try? FileManager.default.removeItem(at: file) }
        let titles = rows(for: conversation(transcript: file, running: true)).agent.map(\.title)
        #expect(!titles.contains { $0.hasPrefix("Resume") })
        #expect(titles.contains("Fork Conversation into New Tab"))
        #expect(titles.contains("Copy Last Reply"))
    }

    @Test func `no transcript file means no reply to copy and nothing to open`() {
        let gone = FileManager.default.temporaryDirectory.appending(path: "calm-palette-gone.jsonl")
        for session in [conversation(transcript: nil), conversation(transcript: gone)] {
            let titles = rows(for: session).agent.map(\.title)
            #expect(!titles.contains("Copy Last Reply"))
            #expect(!titles.contains("Open Transcript"))
            #expect(titles.contains("Copy Session ID"))
        }
    }

    @Test func `an OpenCode session keeps a database, so it has no transcript to open`() throws {
        let file = try transcriptFile()
        defer { try? FileManager.default.removeItem(at: file) }
        let titles = rows(for: conversation(.openCode, transcript: file)).agent.map(\.title)
        #expect(!titles.contains("Copy Last Reply"))
        #expect(!titles.contains("Open Transcript"))
    }

    @Test func `a row does what the card's menu item does`() throws {
        let file = try transcriptFile()
        defer { try? FileManager.default.removeItem(at: file) }
        let session = conversation(transcript: file)
        let calls = Box(Calls())
        let shown = rows(for: session, calls: calls)
        try #require(shown.agent.first { $0.id == "fork-tab" }).run()
        try #require(shown.agent.first { $0.id == "copy-last-reply" }).run()
        try #require(shown.agent.first { $0.id == "open-transcript" }).run()
        try #require(shown.session.first { $0.id == "rename" }).run()
        try #require(shown.folder.first { $0.id == "open-folder" }).run()
        #expect(calls.value.forks.count == 1)
        #expect(calls.value.forks.first?.0 == session.id)
        #expect(calls.value.forks.first?.1 == .tab)
        #expect(calls.value.lastReplies == [session.id])
        #expect(calls.value.transcripts == [session.id])
        #expect(calls.value.renamed == 1)
        #expect(calls.value.folders == [session.id])

        var scratch = Session(projectID: UUID(), workingDirectory: "/tmp/scratch")
        scratch.scratchFolder = "/tmp/scratch"
        try #require(rows(for: scratch, calls: calls).session.first { $0.id == "keep-scratch" }).run()
        #expect(calls.value.kept == [scratch.id])
    }

    // MARK: Descriptions

    @Test func `every one of Calm's rows has a short description of its own`() {
        let lines = PaletteRow.allCases.map(\.help)
        #expect(lines.count == 22)
        #expect(Set(lines).count == lines.count)
        for row in PaletteRow.allCases {
            // One line in the footer, at the largest interface size too: about 70 characters fit.
            #expect(!row.help.isEmpty, "\(row) has none")
            #expect(row.help.count <= 70, "\(row): \(row.help.count) characters")
            #expect(row.help.hasSuffix("."), "\(row)")
        }
    }

    @Test func `a row's id is its case's raw value, and ids are unique`() {
        let ids = PaletteRow.allCases.map(\.rawValue)
        #expect(Set(ids).count == ids.count)
        #expect(PaletteCommand(.forkTab, title: "x") {}.id == "fork-tab")
        #expect(PaletteCommand(.forkTab, title: "x") {}.detail == PaletteRow.forkTab.help)
    }

    @Test func `the session rows all carry their description`() throws {
        let file = try transcriptFile()
        defer { try? FileManager.default.removeItem(at: file) }
        var scratch = Session(projectID: UUID(), workingDirectory: "/tmp/scratch")
        scratch.scratchFolder = "/tmp/scratch"
        let sessions = [
            conversation(transcript: file),
            conversation(transcript: file, running: true),
            scratch,
            Session(projectID: UUID(), workingDirectory: "/tmp/app"),
        ]
        for session in sessions {
            let shown = rows(for: session)
            let all = shown.agent + shown.session + shown.folder
            #expect(!all.isEmpty)
            #expect(all.allSatisfy { !$0.detail.isEmpty })
        }
    }

    @Test func `each copy has its own row`() {
        #expect(PaletteRow(copy: .sessionID) == .copySessionID)
        #expect(PaletteRow(copy: .resumeCommand) == .copyResumeCommand)
        #expect(PaletteRow(copy: .folderPath) == .copyFolderPath)
    }

    @Test func `typing a word of the description finds the row`() {
        let reply = PaletteCommand(.copyLastReply, title: "Copy Last Reply") {}
        let tree = PaletteCommand(.fileTree, title: "Show File Tree") {}
        #expect(CommandMatcher.filter([tree, reply], query: "markdown").map(\.id) == ["copy-last-reply"])
        #expect(CommandMatcher.filter([tree, reply], query: "beside the terminal").map(\.id) == ["file-tree"])
    }

    // MARK: Randomize Theme

    private func choice(_ id: String) -> ThemePickerModel.Choice {
        let preview = ThemePickerModel.Preview(
            background: .black, foreground: .white, sidebar: .gray, hues: Array(repeating: .red, count: 6), cursor: .white, accent: .blue,
        )
        return ThemePickerModel.Choice(id: id, name: id.capitalized, light: preview, dark: preview)
    }

    @Test func `randomizing never lands on the theme in force, or on the user's Ghostty colors`() {
        let choices = ["ghostty", "calm", "dusk", "forest"].map(choice)
        var generator = SystemRandomNumberGenerator()
        for _ in 0 ..< 60 {
            let picked = ThemePickerModel.randomChoice(among: choices, excluding: "calm", using: &generator)
            #expect(picked != nil)
            #expect(picked?.id != "calm")
            #expect(picked?.id != "ghostty")
        }
    }

    @Test func `randomizing from Ghostty's colors picks one of Calm's`() {
        var generator = SystemRandomNumberGenerator()
        let picked = ThemePickerModel.randomChoice(among: ["ghostty", "calm", "dusk"].map(choice), excluding: "ghostty", using: &generator)
        #expect(["calm", "dusk"].contains(picked?.id))
    }

    @Test func `with no other theme there is nothing to land on`() {
        var generator = SystemRandomNumberGenerator()
        #expect(ThemePickerModel.randomChoice(among: ["calm"].map(choice), excluding: "calm", using: &generator) == nil)
        #expect(ThemePickerModel.randomChoice(among: [], excluding: "calm", using: &generator) == nil)
    }
}

/// A value the closures above can change.
private final class Box<Value> {
    var value: Value
    init(_ value: Value) {
        self.value = value
    }
}

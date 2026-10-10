import CalmAgents
import CalmControl
import CalmModel
import CalmSearch
import Foundation

/// `calm show <conversation> [--prompts] [--all] [--json]`: everything Calm knows about one
/// conversation (CLI.md), from the search index, its transcript and, while Calm runs, the session
/// it is open in. Works without Calm. Each part degrades to nothing: a transcript that is gone
/// gives no recap or branch, an agent with no reader gives no tasks.
enum ShowCommand {
    static let usage = "calm show <conversation> [--prompts] [--all] [--json]"

    static func run(_ words: [String]) -> Never {
        var detail = ConversationReport.Detail.summary
        var json = false
        var id: String?
        for word in words {
            switch word {
            case "--prompts": detail = .prompts
            case "--all": detail = .all
            case "--json": json = true
            default:
                guard !word.hasPrefix("--"), id == nil else { fail(usage, code: 64) }
                id = word
            }
        }
        guard let id else { fail(usage, code: 64) }
        guard let index = try? SearchIndex() else { fail("couldn't open the search index") }
        var lookup = index.conversation(id: id)
        if case .failure(.none) = lookup {
            // A conversation newer than the index: bring it up to date once.
            index.update()
            lookup = index.conversation(id: id)
        }
        let conversation: IndexedConversation
        switch lookup {
        case let .success(found):
            conversation = found
        case .failure(.none):
            fail("no conversation with the id '\(id)': `calm search` shows conversations and their ids")
        case let .failure(.several(ids)):
            fail("the ids of several conversations start with '\(id)': \(ids.joined(separator: ", "))")
        }
        let report = report(for: conversation)
        if json {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            print((try? encoder.encode(report)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}")
        } else {
            let home = FileManager.default.homeDirectoryForCurrentUser.path
            print(report.text(detail, now: .now, width: terminalWidth(), home: home))
        }
        exit(0)
    }

    private static func report(for conversation: IndexedConversation) -> ConversationReport {
        let result = conversation.result
        let adapter = Agents.adapter(for: result.agent)
        let home = FileManager.default.homeDirectoryForCurrentUser
        // An agent's own database holds every conversation: its path is `<database>#<id>`, and
        // its reader takes the database and the id (OpenCode). One file per conversation otherwise.
        let parts = result.transcriptPath.split(separator: "#", maxSplits: 1).map(String.init)
        let inDatabase = parts.count == 2
        let file = URL(filePath: parts.first ?? result.transcriptPath)
        let fileThere = !result.transcriptDeleted && !conversation.fromHistory && FileManager.default.fileExists(atPath: file.path)
        let tail = fileThere ? Agents.transcriptReader(for: result.agent)?
            .readTail(of: file, agentSessionID: result.agentSessionID, home: home) : nil
        let tasks: String? = tail.flatMap { tail in
            guard let progress = tail.progress else { return nil }
            return "\(progress.done)/\(progress.total)" + (tail.step.map { " · \($0)" } ?? "")
        }
        // A conversation that can still be resumed: its transcript is there. With ⌘N's options, as
        // ⌘K resumes it: the transcript doesn't say how the agent was started.
        let resumable = !result.transcriptDeleted && !conversation.fromHistory
        let found = AgentConversation(kind: result.agent, agentSessionID: result.agentSessionID, transcriptPath: result.transcriptPath)
        let settings = CalmSettings.load()
        var report = ConversationReport(
            id: result.agentSessionID ?? "",
            title: result.title,
            agent: result.agent.displayName,
            folder: result.directory,
            branch: fileThere ? adapter?.branch(of: file) : nil,
            started: fileThere && !inDatabase ? startDate(of: file) : nil,
            lastActive: result.lastActive.timeIntervalSince1970,
            // The agent's own summary only: the start of its last reply would repeat Last reply.
            recap: tail?.summary,
            tasks: tasks,
            resume: resumable ? adapter?.resumeCommand(for: found, settings: settings) : nil,
            fork: resumable ? adapter?.forkCommand(for: found, settings: settings) : nil,
            transcript: result.transcriptPath,
            transcriptGone: result.transcriptDeleted,
            fromHistory: conversation.fromHistory,
            messages: conversation.messages.map { ConversationReport.Message(fromUser: $0.role == .user, text: $0.text) },
        )
        // Open in a session now: only the running Calm knows. Never started for this.
        if let id = result.agentSessionID, let response = try? ControlClient.send(ControlRequest(cmd: .list), timeout: 2),
           let session = response.sessions?.first(where: { $0.conversation == id }) {
            report.openIn = TraceLog.shortID(session.id) ?? session.id
            report.openState = session.state
        }
        return report
    }

    /// When the transcript file was made: when the conversation started, for the agents that
    /// write one file per conversation.
    private static func startDate(of file: URL) -> Double? {
        ((try? FileManager.default.attributesOfItem(atPath: file.path))?[.creationDate] as? Date)?.timeIntervalSince1970
    }

    private static func terminalWidth() -> Int {
        var size = winsize()
        guard isatty(STDOUT_FILENO) == 1, ioctl(STDOUT_FILENO, TIOCGWINSZ, &size) == 0, size.ws_col > 20 else { return 100 }
        return Int(size.ws_col)
    }
}

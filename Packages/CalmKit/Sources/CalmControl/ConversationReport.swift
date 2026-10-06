import Foundation

/// What `calm show` prints for one conversation (CLI.md → `calm show`). The CLI gathers it from
/// the search index, the transcript and the running Calm; this lays it out, so the layout is
/// tested. A part with nothing in it is left out, not printed empty.
public struct ConversationReport: Codable, Sendable, Equatable {
    public struct Message: Codable, Sendable, Equatable {
        public var fromUser: Bool
        public var text: String

        public init(fromUser: Bool, text: String) {
            self.fromUser = fromUser
            self.text = text
        }
    }

    public enum Detail: Sendable {
        /// Everything on one screen: the last three prompts, the last reply.
        case summary
        /// Every prompt, numbered, in place of the last three.
        case prompts
        /// The whole conversation, every prompt and reply in order.
        case all
    }

    public var id: String
    public var title: String
    public var agent: String
    public var folder: String?
    public var branch: String?
    /// Seconds since 1970.
    public var started: Double?
    public var lastActive: Double
    /// Open in a session of the running Calm: that session's short id and state.
    public var openIn: String?
    public var openState: String?
    public var recap: String?
    /// The todo list: "4/5 · Opening the PR".
    public var tasks: String?
    public var resume: String?
    public var fork: String?
    public var transcript: String
    public var transcriptGone: Bool
    /// Known only from the agent's prompt history: its prompts, not its replies.
    public var fromHistory: Bool
    public var messages: [Message]

    public init(
        id: String, title: String, agent: String, folder: String? = nil, branch: String? = nil, started: Double? = nil,
        lastActive: Double, openIn: String? = nil, openState: String? = nil, recap: String? = nil, tasks: String? = nil,
        resume: String? = nil, fork: String? = nil, transcript: String, transcriptGone: Bool = false, fromHistory: Bool = false,
        messages: [Message],
    ) {
        self.id = id
        self.title = title
        self.agent = agent
        self.folder = folder
        self.branch = branch
        self.started = started
        self.lastActive = lastActive
        self.openIn = openIn
        self.openState = openState
        self.recap = recap
        self.tasks = tasks
        self.resume = resume
        self.fork = fork
        self.transcript = transcript
        self.transcriptGone = transcriptGone
        self.fromHistory = fromHistory
        self.messages = messages
    }

    private var prompts: [String] {
        messages.filter(\.fromUser).map(\.text)
    }

    private var replies: [String] {
        messages.filter { !$0.fromUser }.map(\.text)
    }

    public func text(_ detail: Detail = .summary, now: Date, width: Int = 100, home: String? = nil) -> String {
        var blocks = [header(now: now, home: home)]
        switch detail {
        case .all:
            blocks += messages.map { message in
                (message.fromUser ? "You" : agent) + "\n" + Self.indented(message.text)
            }
        case .summary, .prompts:
            if let asked = prompts.first {
                blocks.append("Asked\n" + Self.indented(asked))
            }
            blocks += promptsBlock(all: detail == .prompts, width: width).map { [$0] } ?? []
            if let recap {
                blocks.append("Recap\n" + Self.indented(recap))
            }
            if let tasks {
                blocks.append("Tasks  \(tasks)")
            }
            if let reply = replies.last {
                blocks.append("Last reply\n" + Self.indented(reply))
            }
        }
        blocks.append(footer(home: home))
        return blocks.joined(separator: "\n\n")
    }

    private func header(now: Date, home: String?) -> String {
        var lines = ["\(title) · \(agent)"]
        let place = [folder.map { Self.abbreviated($0, home: home) }, branch.map { "on \($0)" }].compactMap(\.self)
        if !place.isEmpty {
            lines.append(place.joined(separator: " · "))
        }
        var when = started.map { ["Started \(Doctor.ago(now.timeIntervalSince1970 - $0))"] } ?? []
        when.append("last active \(Doctor.ago(now.timeIntervalSince1970 - lastActive))")
        when.append("\(Self.count(prompts.count, "prompt")), \(Self.count(replies.count, "reply", "replies"))")
        lines.append(when.joined(separator: " · ").capitalizedFirst)
        if let openIn {
            lines.append("Open in session \(openIn)" + (openState.map { " · \($0)" } ?? ""))
        }
        if fromHistory {
            lines.append("Only its prompts are known: the agent deleted its transcript.")
        }
        return lines.joined(separator: "\n")
    }

    /// The last three prompts, or every one, numbered as in the conversation; one line each.
    private func promptsBlock(all: Bool, width: Int) -> String? {
        let numbered = Array(prompts.enumerated()).dropFirst(all ? 0 : max(prompts.count - 3, 1))
        guard !numbered.isEmpty else { return nil }
        let digits = String(prompts.count).count
        let lines = numbered.map { index, text in
            let number = String(index + 1).leftPadded(to: digits)
            return "  \(number)  " + Self.oneLine(text, width: all ? Int.max : width - digits - 4)
        }
        return (all ? "Prompts" : "Recent prompts") + "\n" + lines.joined(separator: "\n")
    }

    private func footer(home: String?) -> String {
        var rows: [(String, String)] = []
        if let resume {
            rows.append(("Resume", resume))
        }
        if let fork {
            rows.append(("Fork", fork))
        }
        rows.append(("Transcript", Self.abbreviated(transcript, home: home) + (transcriptGone ? " (deleted)" : "")))
        rows.append(("Id", id))
        let width = rows.map(\.0.count).max() ?? 0
        return rows.map { "\($0.0.padding(toLength: width, withPad: " ", startingAt: 0))  \($0.1)" }.joined(separator: "\n")
    }

    static func indented(_ text: String) -> String {
        text.split(separator: "\n", omittingEmptySubsequences: false).map { "  " + $0 }.joined(separator: "\n")
    }

    static func oneLine(_ text: String, width: Int) -> String {
        let flat = text.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }.joined(separator: " ")
        guard flat.count > width, width > 1 else { return flat }
        return String(flat.prefix(width - 1)) + "…"
    }

    static func abbreviated(_ path: String, home: String?) -> String {
        guard let home, path == home || path.hasPrefix(home + "/") else { return path }
        return "~" + path.dropFirst(home.count)
    }

    static func count(_ number: Int, _ one: String, _ many: String? = nil) -> String {
        "\(number) \(number == 1 ? one : many ?? one + "s")"
    }
}

private extension String {
    var capitalizedFirst: String {
        prefix(1).uppercased() + dropFirst()
    }

    func leftPadded(to width: Int) -> String {
        String(repeating: " ", count: max(width - count, 0)) + self
    }
}

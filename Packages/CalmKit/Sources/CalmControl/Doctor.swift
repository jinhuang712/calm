import Foundation

/// What `calm doctor` checks (CLI.md → `calm doctor`). The CLI gathers the facts; the verdicts are
/// made here from them alone, so each is testable. It only reports: nothing is changed.
public enum Doctor {
    public struct Check: Codable, Sendable, Equatable {
        public enum Verdict: String, Codable, Sendable {
            case ok
            case problem
            /// Worth knowing, not wrong (an agent left unconnected is the user's choice).
            case note
        }

        public var verdict: Verdict
        public var text: String
        /// What to do about a problem.
        public var hint: String?

        public init(_ verdict: Verdict, _ text: String, hint: String? = nil) {
            self.verdict = verdict
            self.text = text
            self.hint = hint
        }
    }

    /// How Calm answered `info`.
    public enum Answer: Sendable, Equatable {
        case answered(ControlResponse.AppInfo)
        case notRunning(socket: String)
        /// Connected, but no reply in time, or one that couldn't be read.
        case silent(String)
        /// It answered with an error: an older Calm doesn't know `info`.
        case refused(String)
    }

    /// How an agent reports to Calm, as Settings → Agents sees it.
    public enum AgentLink: Sendable, Equatable {
        /// Calm's own plugin, loaded in its shells (Claude Code): whether Calm wrote it, and
        /// whether config.toml turned it off.
        case plugin(written: Bool, on: Bool)
        /// The agent's own notifications and transcript (Codex).
        case notifications
        /// Files added with the user's consent (pi, OpenCode).
        case files(FilesState)
        case hint(String)
    }

    public enum FilesState: Sendable, Equatable {
        case connected
        /// Connected with a file from an older Calm; the next launch rewrites it.
        case outdated
        case notConnected
        /// A file Calm didn't write is where Calm's would go.
        case conflict(String)
    }

    public struct Agent: Sendable, Equatable {
        public var name: String
        public var link: AgentLink

        public init(name: String, link: AgentLink) {
            self.name = name
            self.link = link
        }
    }

    public struct Facts: Sendable {
        public var answer: Answer
        /// When the answering Calm's process started.
        public var started: Date?
        /// Every process running that Calm's executable.
        public var copies: [Int32]
        /// That app's version on disk, and when its executable was written (an install).
        public var installedVersion: String?
        public var installedAt: Date?
        /// This CLI: its version, the app it sits in (nil outside one), and the first `calm` on
        /// `PATH` with links resolved (nil when there's none).
        public var cliVersion: String
        public var cliApp: String?
        public var pathCalm: String?
        /// The agents whose config folder is there.
        public var agents: [Agent]
        /// Inside a Calm session: its id.
        public var sessionID: String?
        /// Whether this shell loads Calm's Claude Code plugin; nil when that doesn't apply.
        public var claudePluginInShell: Bool?
        public var now: Date

        public init(
            answer: Answer,
            started: Date? = nil,
            copies: [Int32] = [],
            installedVersion: String? = nil,
            installedAt: Date? = nil,
            cliVersion: String,
            cliApp: String? = nil,
            pathCalm: String? = nil,
            agents: [Agent] = [],
            sessionID: String? = nil,
            claudePluginInShell: Bool? = nil,
            now: Date = Date(),
        ) {
            self.answer = answer
            self.started = started
            self.copies = copies
            self.installedVersion = installedVersion
            self.installedAt = installedAt
            self.cliVersion = cliVersion
            self.cliApp = cliApp
            self.pathCalm = pathCalm
            self.agents = agents
            self.sessionID = sessionID
            self.claudePluginInShell = claudePluginInShell
            self.now = now
        }
    }

    public static func checks(_ facts: Facts) -> [Check] {
        var checks = calm(facts)
        checks += cli(facts)
        checks += facts.agents.map(agent)
        checks += session(facts)
        return checks
    }

    // MARK: Calm

    private static func calm(_ facts: Facts) -> [Check] {
        let restart = "Calm → Restart Calm"
        switch facts.answer {
        case let .notRunning(socket):
            return [Check(.problem, "Calm isn't running (no socket at \(socket)).", hint: "Open Calm.")]
        case let .silent(reason):
            return [Check(
                .problem, "Calm doesn't answer on its socket (\(reason)).",
                hint: "A Calm that is stuck, or a dead socket: \(restart).",
            )]
        case let .refused(reason):
            return [Check(
                .problem, "The Calm answering is older than this calm: \(reason)",
                hint: "\(restart) starts the one installed.",
            )]
        case let .answered(info):
            let since = facts.started.map { ", running since \(clock($0, now: facts.now))" } ?? ""
            var checks = [Check(.ok, "Calm \(info.version) answers on its socket (process \(info.processID)\(since)).")]
            if facts.copies.count > 1 {
                let pids = facts.copies.map(String.init).joined(separator: ", ")
                checks.append(Check(
                    .problem, "\(facts.copies.count) copies of Calm are running from \(info.bundlePath) (processes \(pids)).",
                    hint: "Only one can have the socket. Quit the others, then \(restart).",
                ))
            }
            if let installed = facts.installedAt, let started = facts.started, installed.timeIntervalSince(started) > 1 {
                checks.append(Check(
                    .problem,
                    "A newer Calm was installed at \(clock(installed, now: facts.now)), after this one started.",
                    hint: "\(restart): until then its shells can lose access to Documents, Desktop and Downloads.",
                ))
            } else if let version = facts.installedVersion, version != info.version {
                checks.append(Check(.problem, "Calm \(info.version) is running; \(version) is installed.", hint: restart))
            } else {
                checks.append(Check(.ok, "It runs the build on disk in \(info.bundlePath)."))
            }
            return checks
        }
    }

    // MARK: The CLI

    private static func cli(_ facts: Facts) -> [Check] {
        var checks: [Check] = []
        let running: String? = if case let .answered(info) = facts.answer {
            info.bundlePath
        } else {
            nil
        }
        if let app = facts.cliApp, let running, app != running {
            checks.append(Check(
                .problem, "This calm comes with \(app), but the Calm answering runs from \(running).",
                hint: "Run the calm in \(running)/Contents/Resources/bin, or open \(app).",
            ))
        } else if case let .answered(info) = facts.answer, info.version != facts.cliVersion {
            checks.append(Check(
                .problem, "This calm is \(facts.cliVersion), the Calm answering is \(info.version).",
                hint: "./install.sh installs the two together.",
            ))
        } else if let app = facts.cliApp {
            let whose = running == nil ? "comes with \(app)" : "belongs to the Calm answering"
            checks.append(Check(.ok, "This calm (\(facts.cliVersion)) \(whose)."))
        } else {
            checks.append(Check(.note, "This calm isn't inside an app (a development build?)."))
        }
        guard let onPath = facts.pathCalm else {
            // A Calm from the download has no install.sh to link it, so say how.
            let app = running ?? facts.cliApp ?? "/Applications/Calm.app"
            let link = "mkdir -p ~/.local/bin && ln -sf '\(app)/Contents/Resources/bin/calm' ~/.local/bin/calm"
            checks.append(Check(
                .note, "No calm on PATH. Calm's own shells have $CALM_CLI.",
                hint: "For other terminals: \(link) (./install.sh does this).",
            ))
            return checks
        }
        // Whose calm it should be: the running Calm's, else this calm's app; with neither known
        // there is nothing to compare.
        guard let expected = running ?? facts.cliApp else {
            checks.append(Check(.note, "The calm on PATH is \(onPath)."))
            return checks
        }
        if CalmLaunch.app(containing: URL(filePath: onPath))?.path != expected {
            checks.append(Check(
                .problem, "The calm on PATH (\(onPath)) isn't this Calm's (\(expected)).",
                hint: "./install.sh links the right one into ~/.local/bin.",
            ))
        } else {
            checks.append(Check(.ok, "The calm on PATH is this Calm's."))
        }
        return checks
    }

    // MARK: Agents

    private static func agent(_ agent: Agent) -> Check {
        let name = agent.name
        switch agent.link {
        case .plugin(_, on: false):
            return Check(.note, "\(name): its hooks are off (hooks = false under [agents.claude-code] in config.toml).")
        case .plugin(written: false, on: true):
            return Check(
                .problem, "\(name): Calm's plugin isn't there (\(pluginFolderName)).",
                hint: "Calm writes it at launch: Calm → Restart Calm.",
            )
        case .plugin(written: true, on: true):
            return Check(.ok, "\(name): reports through Calm's plugin, in Calm's shells.")
        case .notifications:
            return Check(.note, "\(name): reports through its own notifications and transcript; no hooks, by design.")
        case .files(.connected):
            return Check(.ok, "\(name): connected.")
        case .files(.outdated):
            return Check(.note, "\(name): connected, with a file from an older Calm; Calm rewrites it at its next launch.")
        case .files(.notConnected):
            return Check(.note, "\(name): not connected (Settings → Agents).")
        case let .files(.conflict(path)):
            return Check(
                .problem, "\(name): a file Calm didn't write is in the way (~/\(path)).",
                hint: "Move it aside, then Connect in Settings → Agents.",
            )
        case let .hint(text):
            return Check(.note, "\(name): \(text)")
        }
    }

    private static let pluginFolderName = "~/Library/Application Support/Calm/agents/claude-code"

    // MARK: This session

    private static func session(_ facts: Facts) -> [Check] {
        guard let id = facts.sessionID else { return [] }
        let short = TraceLog.shortID(id) ?? id
        var checks: [Check] = []
        if case let .answered(info) = facts.answer {
            if let session = info.session {
                let agent = session.agent.map { ", \($0)" } ?? ""
                let report = session.reportedAt.map { date in
                    let age = facts.now.timeIntervalSince1970 - date
                    return ", last reported by \(session.reportSource == "hook" ? "a hook" : "the terminal") \(ago(age))"
                } ?? ", nothing reported yet"
                checks.append(Check(.ok, "This session (\(short)): \(session.state)\(agent)\(report)."))
            } else {
                checks.append(Check(
                    .problem, "The Calm answering doesn't know this session (\(short)).",
                    hint: "This shell outlived its session, or belongs to another Calm: open a new session.",
                ))
            }
        }
        if facts.claudePluginInShell == false {
            checks.append(Check(
                .problem, "This shell doesn't load Calm's Claude Code plugin, so Claude here won't report.",
                hint: "Open a new session (CLAUDE_CODE_PLUGIN_DIRS was changed, or the shell started before the hooks were on).",
            ))
        }
        return checks
    }

    // MARK: Text

    /// ✓, ✗ and ·, one check per line, with what to do under each problem.
    public static func text(_ checks: [Check]) -> String {
        checks.map { check in
            let mark = switch check.verdict {
            case .ok: "✓"
            case .problem: "✗"
            case .note: "·"
            }
            let hint = check.hint.map { "\n    \($0)" } ?? ""
            return "\(mark) \(check.text)\(hint)"
        }.joined(separator: "\n")
    }

    /// `--json`: the checks, with `v` so a script can tell when the shape changes.
    public static func json(_ checks: [Check]) -> String {
        struct Output: Encodable {
            let v = 1
            let checks: [Check]
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return (try? encoder.encode(Output(checks: checks))).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
    }

    /// "10:02", or with the day when it isn't today.
    static func clock(_ date: Date, now: Date) -> String {
        let calendar = Calendar.current
        let style = calendar.isDate(date, inSameDayAs: now)
            ? Date.FormatStyle().hour(.twoDigits(amPM: .omitted)).minute(.twoDigits)
            : Date.FormatStyle().month(.abbreviated).day().hour(.twoDigits(amPM: .omitted)).minute(.twoDigits)
        return date.formatted(style)
    }

    /// "4 s ago", "12 min ago", "3 h ago", "2 d ago".
    static func ago(_ seconds: Double) -> String {
        let seconds = max(seconds, 0)
        if seconds < 60 {
            return "\(Int(seconds)) s ago"
        }
        if seconds < 3600 {
            return "\(Int(seconds / 60)) min ago"
        }
        if seconds < 86400 {
            return "\(Int(seconds / 3600)) h ago"
        }
        return "\(Int(seconds / 86400)) d ago"
    }
}

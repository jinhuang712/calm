import Foundation

/// What an agent is doing this moment, in a few words for its working card: "Reading
/// SessionCard.swift" (UIUX.md → Session cards). The adapter that hears the agent's hook picks
/// the words; the card only shows them.
public struct AgentActivity: Hashable, Sendable {
    public var words: String
    /// What several at once add up to, `#` standing for how many: "Reading # files". Nil when
    /// they don't add up, and the latest says it.
    public var group: String?

    public init(_ words: String, group: String? = nil) {
        self.words = words
        self.group = group
    }
}

/// What an agent's hook says about the working line: a step began (a tool call), a step ended,
/// or a prompt came in and the agent is thinking.
public enum ActivityChange: Hashable, Sendable {
    case began(AgentActivity)
    case ended
    case thinking

    /// What the line says before a turn's first step, and once the agent has been quiet a while.
    public static let thinkingWords = "Thinking"

    /// How `calm hook` passes it to the app: "began" with the words and group, "ended", "thinking".
    public var reportName: String {
        switch self {
        case .began: "began"
        case .ended: "ended"
        case .thinking: "thinking"
        }
    }

    public init?(reportName: String, words: String?, group: String?) {
        switch reportName {
        case "began":
            guard let words, !words.isEmpty else { return nil }
            self = .began(AgentActivity(words, group: group))
        case "ended": self = .ended
        case "thinking": self = .thinking
        default: return nil
        }
    }
}

/// The working line's words over time: live, but never flashing (UIUX.md → Session cards).
///
/// - Words show at once when the line has held its last ones for `hold`; others that come
///   sooner wait for that, and the latest waiting wins, so a burst of parallel calls shows once.
/// - Steps of one group a burst apart add up: three files read at once say "Reading 3 files".
/// - Once every step has ended and nothing has followed for `quiet`, the agent is thinking, and
///   the line says so. A step still running (a test run sends nothing until it ends) never
///   reads as quiet.
///
/// A value, read at a moment: the card shows `words(at:)` and wakes at `nextChange(after:)`.
public struct LiveLine: Hashable, Sendable {
    /// How long words stay before others replace them.
    public static let hold: TimeInterval = 2
    /// How long after the last step ends, with nothing after it, the line says "Thinking".
    /// Longer than most gaps between Claude's tool calls (2 to 15 s in the author's turns), so
    /// it marks a real pause: a long think, or a long reply being written.
    public static let quiet: TimeInterval = 15

    public private(set) var shown: String
    public private(set) var shownAt: Date
    /// Words waiting for the hold to pass.
    private var waiting: String?
    /// The burst so far: steps of one group, each less than `hold` after the one before.
    private var burstGroup: String?
    private var burstWords: [String] = []
    private var lastStep: Date
    /// Steps begun and not yet ended (parallel tool calls run together).
    private var running = 0
    /// When the last running step ended; nil while any runs, and while thinking.
    private var endedAt: Date?

    /// A line that starts with the agent thinking (a prompt came in).
    public init(thinkingAt date: Date) {
        shown = ActivityChange.thinkingWords
        shownAt = date
        lastStep = date
    }

    /// The line after `change`, at `date`.
    public mutating func apply(_ change: ActivityChange, at date: Date) {
        settle(at: date)
        switch change {
        case let .began(activity):
            begin(activity, at: date)
        case .ended:
            running = max(running - 1, 0)
            if running == 0 {
                endedAt = endedAt ?? date
            }
        case .thinking:
            running = 0
            endedAt = nil
            burstGroup = nil
            burstWords = []
            propose(ActivityChange.thinkingWords, at: date)
        }
    }

    /// Whatever asked has been answered (*needs you* is over): a step it stopped, a denied
    /// tool call, never ends, so none counts as running any more.
    public mutating func resume(at date: Date) {
        settle(at: date)
        running = 0
        endedAt = endedAt ?? date
    }

    /// What has come due by `date`: words that waited out the hold, then "Thinking".
    public mutating func settle(at date: Date) {
        if let waiting, shownAt.addingTimeInterval(Self.hold) <= date {
            show(waiting, at: shownAt.addingTimeInterval(Self.hold))
        }
        if waiting == nil, shown != ActivityChange.thinkingWords, let endedAt, endedAt.addingTimeInterval(Self.quiet) <= date {
            show(ActivityChange.thinkingWords, at: max(endedAt.addingTimeInterval(Self.quiet), shownAt))
        }
    }

    /// The words at `date`.
    public func words(at date: Date) -> String {
        var line = self
        line.settle(at: date)
        return line.shown
    }

    /// When the words change next with nothing new from the agent: the hold's end, or the quiet's.
    public func nextChange(after date: Date) -> Date? {
        var line = self
        line.settle(at: date)
        if line.waiting != nil {
            return line.shownAt.addingTimeInterval(Self.hold)
        }
        if let endedAt = line.endedAt, line.shown != ActivityChange.thinkingWords {
            return endedAt.addingTimeInterval(Self.quiet)
        }
        return nil
    }

    private mutating func begin(_ activity: AgentActivity, at date: Date) {
        if let group = activity.group, group == burstGroup, date.timeIntervalSince(lastStep) < Self.hold {
            if !burstWords.contains(activity.words) {
                burstWords.append(activity.words)
            }
        } else {
            burstGroup = activity.group
            burstWords = [activity.words]
        }
        lastStep = date
        running += 1
        endedAt = nil
        let words = burstWords.count > 1
            ? (burstGroup ?? activity.words).replacingOccurrences(of: "#", with: String(burstWords.count))
            : activity.words
        propose(words, at: date)
    }

    /// Shows `words` now if the hold allows, else lets them wait.
    private mutating func propose(_ words: String, at date: Date) {
        if date.timeIntervalSince(shownAt) >= Self.hold {
            show(words, at: date)
        } else {
            waiting = words == shown ? nil : words
        }
    }

    private mutating func show(_ words: String, at date: Date) {
        shown = words
        shownAt = date
        waiting = nil
    }

    /// The line after a report moved a session from `previous` to `state`, with what its hook
    /// said (`change`). A turn starting from rest starts the line over, one that ends clears it,
    /// and an answered question resumes it (the turn's rule, `Workspace.noteTurn`); the hook's
    /// change counts only while the agent works. One heard mid-turn with no line yet (Calm
    /// started after the prompt) starts one.
    public static func after(
        _ line: LiveLine?, from previous: SessionState?, to state: SessionState, change: ActivityChange?, at date: Date,
    ) -> LiveLine? {
        var line = line
        if previous != state {
            switch (previous, state) {
            case (.needsYou, .working) where change != .thinking:
                line?.resume(at: date)
            case (_, .needsYou):
                break
            default:
                line = nil
            }
        }
        guard state == .working, let change else { return line }
        if line == nil {
            switch change {
            case .thinking:
                return LiveLine(thinkingAt: date)
            case .began:
                var started = LiveLine(thinkingAt: .distantPast)
                started.apply(change, at: date)
                return started
            case .ended:
                return nil
            }
        }
        line?.apply(change, at: date)
        return line
    }
}

public extension Session {
    /// What the corner's time counts from: a working agent's turn from its start, else the
    /// latest report (UIUX.md → Session cards).
    var cornerDate: Date? {
        if state == .working, let turnStartedAt {
            return turnStartedAt
        }
        return lastReport?.date ?? agent?.startedAt
    }

    /// The quiet line under the working line while the agent keeps a todo list: "3 of 5 · Adding
    /// a regression test", or "3 of 5" between todos (the author chose words over a bar,
    /// 2026-10-09); nil without a list.
    var todoLine: String? {
        guard let progress = agent?.tail?.progress, progress.total > 0 else { return nil }
        let count = "\(progress.done) of \(progress.total)"
        guard let step = agent?.tail?.step, !step.isEmpty else { return count }
        return "\(count) · \(step)"
    }

    /// The working line's words: "Compacting" while the agent compacts, else what its hooks say
    /// it's doing (`line`), else "Working" (an agent whose hooks don't say).
    func liveWords(_ line: LiveLine?, at date: Date) -> String {
        if isCompacting {
            return "Compacting"
        }
        return line?.words(at: date) ?? "Working"
    }
}

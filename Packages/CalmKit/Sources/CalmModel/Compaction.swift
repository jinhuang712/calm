import Foundation

/// An agent summarizing its conversation to make room for more (Claude Code's compaction): a
/// minute or two in which the agent is busy but does none of the turn's work (UIUX.md → Session
/// cards). Known from the agent's own reports, with the sizes its transcript records. Not
/// saved: after a restart the agent may long be done with it.
public struct Compaction: Hashable, Sendable {
    /// Asked for (`/compact`), or done by the agent on its own when the conversation filled up.
    public enum Trigger: String, Hashable, Sendable {
        case manual
        case auto
    }

    public var trigger: Trigger
    public var startedAt: Date
    /// When it ended; nil while it runs.
    public var endedAt: Date?
    /// The conversation's size when it began: the agent's last reply until the transcript
    /// records the compaction, then the agent's own count.
    public var tokensBefore: Int?
    /// What it kept, once the transcript says.
    public var tokensAfter: Int?

    public init(trigger: Trigger, startedAt: Date, endedAt: Date? = nil, tokensBefore: Int? = nil, tokensAfter: Int? = nil) {
        self.trigger = trigger
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.tokensBefore = tokensBefore
        self.tokensAfter = tokensAfter
    }

    /// A transcript's record of the compaction that ended at `context.date`, if it is this one.
    /// A compaction takes a minute or more, so a record from before it began is an earlier one;
    /// the slack is for a compaction first heard of when it ended, its start then being the
    /// moment Calm heard.
    func isRecorded(by context: CompactedContext) -> Bool {
        context.date >= startedAt.addingTimeInterval(-2)
    }
}

/// What a report says of a compaction: it started, or it ended.
public enum CompactionReport: Hashable, Sendable {
    case started(Compaction.Trigger)
    case ended(Compaction.Trigger)

    /// How `calm hook` passes it to the app: "start:manual", "end:auto".
    public var reportName: String {
        switch self {
        case let .started(trigger): "start:\(trigger.rawValue)"
        case let .ended(trigger): "end:\(trigger.rawValue)"
        }
    }

    public init?(reportName: String) {
        let parts = reportName.split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2, let trigger = Compaction.Trigger(rawValue: parts[1]) else { return nil }
        switch parts[0] {
        case "start": self = .started(trigger)
        case "end": self = .ended(trigger)
        default: return nil
        }
    }
}

/// A compaction as the agent's transcript records it once it is over (Claude Code's
/// `compact_boundary`): when, and the conversation's size before and after.
public struct CompactedContext: Codable, Hashable, Sendable {
    public var date: Date
    public var tokensBefore: Int?
    public var tokensAfter: Int?

    public init(date: Date, tokensBefore: Int?, tokensAfter: Int?) {
        self.date = date
        self.tokensBefore = tokensBefore
        self.tokensAfter = tokensAfter
    }
}

/// The bar a session card shows for a compaction, in the todo bar's place (UIUX.md → Session
/// cards): full while the agent compacts, then drained to the share it kept, for a few seconds
/// after one the agent did on its own, and on the *done* card a `/compact` ends with until you
/// move on.
public enum CompactionBar: Hashable, Sendable {
    /// Running, or just over with nothing recorded yet: the size it began at, when known.
    case full(tokens: Int?)
    /// Over: from the size it had to the size it kept.
    case drained(from: Int, to: Int)

    /// How long a drained bar stays after a compaction the agent did on its own.
    public static let lingers: TimeInterval = 5

    /// The share of the bar that stays filled.
    public var fraction: Double {
        switch self {
        case .full: 1
        case let .drained(from, to): from > 0 ? min(max(Double(to) / Double(from), 0), 1) : 0
        }
    }

    /// What the bar says beside it: "968k" while running, "968k → 13k" after.
    public var label: String? {
        switch self {
        case let .full(tokens): tokens.map(Self.tokens)
        case let .drained(from, to): "\(Self.tokens(from)) → \(Self.tokens(to))"
        }
    }

    /// A token count as people say it: "850", "1.2k", "13k", "968k", "1M", "1.2M".
    public static func tokens(_ count: Int) -> String {
        func short(_ value: Double, _ unit: String) -> String {
            let rounded = (value * 10).rounded() / 10
            return rounded == rounded.rounded() ? "\(Int(rounded))\(unit)" : String(format: "%.1f%@", rounded, unit)
        }
        switch count {
        case ..<1000: return "\(max(count, 0))"
        case ..<10000: return short(Double(count) / 1000, "k")
        case ..<999_500: return "\(Int((Double(count) / 1000).rounded()))k"
        default: return short(Double(count) / 1_000_000, "M")
        }
    }
}

public extension Session {
    /// Compacting right now: the card says so in its working line.
    var isCompacting: Bool {
        state == .working && compaction != nil && compaction?.endedAt == nil
    }

    /// What the working line names after "Working": the compaction while it runs, else the
    /// agent's task.
    var workingStep: String? {
        isCompacting ? "Compacting" : agent?.tail?.step
    }

    /// The compaction bar the card shows at `now`, if any (`compactionBarEnds` says when it goes
    /// by itself).
    func compactionBar(now: Date) -> CompactionBar? {
        guard let compaction else { return nil }
        guard let ended = compaction.endedAt else {
            return state == .working ? .full(tokens: compaction.tokensBefore) : nil
        }
        let staysDone = compaction.trigger == .manual && state == .done
        if let from = compaction.tokensBefore, let to = compaction.tokensAfter, from > 0 {
            return staysDone || now < ended.addingTimeInterval(CompactionBar.lingers) ? .drained(from: from, to: to) : nil
        }
        // Over, with nothing recorded yet (the transcript is written as the hook arrives): the bar
        // holds a moment rather than going and coming back drained; with no transcript, it goes.
        return now < ended.addingTimeInterval(CompactionBar.lingers) ? .full(tokens: compaction.tokensBefore) : nil
    }

    /// When the bar shown now goes by itself; nil while it runs or for good.
    var compactionBarEnds: Date? {
        guard let compaction, let ended = compaction.endedAt else { return nil }
        let recorded = compaction.tokensBefore != nil && compaction.tokensAfter != nil
        if recorded, compaction.trigger == .manual, state == .done {
            return nil
        }
        return ended.addingTimeInterval(CompactionBar.lingers)
    }
}

extension Workspace {
    /// A report's word on a compaction (`report`). Its start takes the size the agent's last
    /// reply gave; its end keeps what the transcript already recorded.
    mutating func noteCompaction(_ index: Int, _ report: StatusReport) {
        switch report.compaction {
        case let .started(trigger):
            sessions[index].compaction = Compaction(
                trigger: trigger, startedAt: report.date, tokensBefore: sessions[index].agent?.tail?.contextTokens,
            )
        case let .ended(trigger):
            var compaction = sessions[index].compaction ?? Compaction(
                trigger: trigger, startedAt: report.date, tokensBefore: sessions[index].agent?.tail?.contextTokens,
            )
            compaction.trigger = trigger
            compaction.endedAt = compaction.endedAt ?? report.date
            sessions[index].compaction = compaction
            if let recorded = sessions[index].agent?.tail?.lastCompaction {
                noteCompactionRecord(index, recorded)
            }
        case nil:
            // The agent moved on without saying the compaction ended; a report that isn't
            // *working* can't be one made while it compacts.
            if sessions[index].compaction?.endedAt == nil, report.source == .hook, report.state != .working {
                sessions[index].compaction = nil
            }
        }
    }

    /// The transcript recorded a compaction: if it's the session's, its sizes, and its end
    /// when the agent's report hasn't come yet.
    mutating func noteCompactionRecord(_ index: Int, _ recorded: CompactedContext) {
        guard var compaction = sessions[index].compaction, compaction.isRecorded(by: recorded) else { return }
        compaction.tokensBefore = recorded.tokensBefore ?? compaction.tokensBefore
        compaction.tokensAfter = recorded.tokensAfter
        compaction.endedAt = compaction.endedAt ?? recorded.date
        sessions[index].compaction = compaction
    }

    /// A new reading of the transcript, while a compaction runs: a recorded end, or a message
    /// after it began with no record of it ending. Esc cancels a compaction with no hook at all,
    /// and leaves only a message (Claude Code 2.1.291); while one runs, the transcript gains
    /// bookkeeping (a queued prompt, a link), never a message. A `/compact` cancelled goes back
    /// to idle; one Claude began on its own was mid-turn, and the turn's interruption settles it.
    mutating func noteCompactionInTranscript(_ index: Int, _ tail: TranscriptTail, readAt date: Date) {
        guard let compaction = sessions[index].compaction else { return }
        if let recorded = tail.lastCompaction, compaction.isRecorded(by: recorded) {
            noteCompactionRecord(index, recorded)
            return
        }
        guard compaction.endedAt == nil, let newest = tail.newestMessageAt, newest > compaction.startedAt.addingTimeInterval(0.5) else {
            return
        }
        sessions[index].compaction = nil
        if compaction.trigger == .manual, sessions[index].state == .working {
            sessions[index].state = .idle
            sessions[index].lastReport = StatusReport(state: .idle, message: nil, source: .hook, date: date)
        }
    }
}

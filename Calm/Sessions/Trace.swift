import CalmModel
import Foundation
import OSLog

/// A timeline of what decides what the sidebar shows, kept in the unified log (category `trace`,
/// notice level so it is written to disk):
///
///     /usr/bin/log show --last 5m --predicate 'subsystem == "com.jinhuang.calm" AND category == "trace"'
///
/// Made to see why a session's status is slow to appear after a launch (DESIGNS.md → Testing).
/// Each line is the seconds since launch, what happened, and which session, by the first eight
/// hex digits of its id (as in `state.json` and the zmx names). Only states, sources, counts and
/// agent names: never a word the user or an agent wrote.
///
/// Verbose for the first minute after launch, when the state is being rebuilt; after that only
/// changes are written, so a busy day stays quiet.
enum Trace {
    private static let log = Logger(subsystem: "com.jinhuang.calm", category: "trace")
    private static let clock = ContinuousClock()
    /// Touched by `begin()` first thing at launch, which starts the clock.
    private static let origin = clock.now

    /// How long after launch every report is written, not only those that changed something.
    private static let launchWindow = Duration.seconds(60)
    /// A request that waited this long for the main thread is written down.
    private static let stallThreshold = Duration.milliseconds(100)

    static var now: ContinuousClock.Instant {
        clock.now
    }

    static func begin() {
        _ = origin
        note("launch")
    }

    /// Still in the minute after launch.
    static var isLaunching: Bool {
        origin.duration(to: clock.now) < launchWindow
    }

    static func note(_ event: @autoclosure () -> String) {
        let line = "\(offset(origin.duration(to: clock.now))) \(event())"
        log.notice("\(line, privacy: .public)")
    }

    /// A status report reached a session (from a hook or a terminal signal).
    static func reported(_ id: Session.ID, _ report: StatusReport, before: SessionState?, after: SessionState?) {
        guard isLaunching || before != after else { return }
        note("report \(Trace.id(id)) from \(report.source.rawValue) says \(report.state.rawValue): \(transition(before, after))")
    }

    /// A hook said which agent it speaks for. Each one does; only the first, or one that
    /// changed something, is news once the launch is over.
    static func hookNamed(_ id: Session.ID, _ kind: AgentKind, before: AgentRun?, after: AgentRun?) {
        guard isLaunching || before?.kind != after?.kind || before?.transcriptPath != after?.transcriptPath else { return }
        let transcript = after?.transcriptPath == nil ? "unknown" : "known"
        let agent = before == nil ? "was not known" : "was known"
        note("hook names \(Trace.id(id)): \(kind.rawValue), transcript \(transcript), agent \(agent)")
    }

    /// The probe saw an agent start or end in a session's foreground.
    static func probed(_ id: Session.ID, _ event: String, before: Session, after: Session?) {
        note("probe \(Trace.id(id)): \(event); \(describe(before)) → \(describe(after))")
    }

    /// The transcript was read again and its tail differed.
    static func transcriptRead(_ id: Session.ID, _ tail: TranscriptTail, before: SessionState?, after: SessionState?) {
        note("transcript \(Trace.id(id)) read: \(fields(of: tail)); \(transition(before, after))")
    }

    /// What a transcript tail held, without any of its text: `title, recap, todos 3/5`.
    static func fields(of tail: TranscriptTail) -> String {
        let found = [
            tail.title.map { _ in "title" }, tail.lastMessage.map { _ in "recap" }, tail.step.map { _ in "step" },
            tail.progress.map { "todos \($0.done)/\($0.total)" }, tail.interrupted ? "interrupted" : nil,
        ].compactMap(\.self)
        return found.isEmpty ? "nothing" : found.joined(separator: ", ")
    }

    /// A control request that sat waiting for the main thread: a hook waits that long too, and
    /// the `calm hook` client gives up after a second.
    static func stall(of command: String, since received: ContinuousClock.Instant) {
        let waited = received.duration(to: clock.now)
        guard waited >= stallThreshold else { return }
        note("control \(command) waited \(offset(waited).dropFirst()) s for the main thread")
    }

    /// `+2.11`: seconds, to the hundredth.
    static func offset(_ elapsed: Duration) -> String {
        let (seconds, attoseconds) = elapsed.components
        return String(format: "+%.2f", Double(seconds) + Double(attoseconds) / 1e18)
    }

    static func id(_ id: UUID) -> String {
        id.uuidString.prefix(8).lowercased()
    }

    /// What the sidebar builds a row's mark and state from: `working, claudeCode`.
    static func describe(_ session: Session?) -> String {
        guard let session else { return "gone" }
        return "\(session.state.rawValue), \(session.agent?.kind.rawValue ?? "no agent")"
    }

    /// `working` when nothing changed, `working → idle` when it did.
    static func transition(_ before: SessionState?, _ after: SessionState?) -> String {
        let from = before?.rawValue ?? "gone"
        let to = after?.rawValue ?? "gone"
        return from == to ? from : "\(from) → \(to)"
    }
}

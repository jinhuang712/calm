import CalmAgents
import CalmModel
import Darwin
import Foundation

/// Watches each session's shell process every couple of seconds, with plain syscalls:
///
/// - **Folder:** for shells that don't report it themselves (no OSC 7, e.g. bash without
///   Ghostty's integration), read it from the shell process.
/// - **Foreground job:** when it changes, read the new job's arguments once and let the agent
///   adapters say whether an agent started or exited (FEATURES.md → F4).
///
/// A persistent session's shell runs under zmx, so its process comes from `zmx list` (only
/// when one isn't known yet) and works for sessions without a pane, e.g. after a relaunch.
/// Without zmx the pane's own foreground process is used.
@MainActor
final class SessionProbe {
    static let shared = SessionProbe()

    private var timer: Timer?
    private var shellProcesses: [String: pid_t] = [:]
    private var lastListing = Date.distantPast
    /// The foreground job last seen per session (0: the shell itself).
    private var foregroundJobs: [Session.ID: Int32] = [:]
    /// Size and modification time of each agent transcript when last read.
    private var transcriptStamps: [Session.ID: TranscriptStamp] = [:]
    /// Sessions whose transcript is being read right now, off the main thread.
    private var readingTranscripts: Set<Session.ID> = []
    /// When Calm last looked for each session's transcript.
    private var lastDiscoveries: [Session.ID: Date] = [:]
    /// When each session's transcript was last read (or found unchanged), for `readSoon`.
    private var lastReads: [Session.ID: Date] = [:]
    /// The least time between two reads of one transcript: the tick's.
    private static let readSpacing: TimeInterval = 2
    /// Reads a hook asked for, waiting their moment; and ones asked for while a read ran.
    private var soonReads: Set<Session.ID> = []
    private var rereads: Set<Session.ID> = []
    /// The launch pass is still out, with rows showing as loading (`settleSavedRuns`).
    private var savedRunsPending = false
    /// Polls so far, for the work done every few of them.
    private var ticks = 0

    /// Where the launch pass leaves its answer for the main thread to pick up.
    private final class AnswerBox: @unchecked Sendable {
        private let lock = NSLock()
        private var stored: LaunchPass.Answer?

        var answer: LaunchPass.Answer? {
            get { lock.withLock { stored } }
            set { lock.withLock { stored = newValue } }
        }
    }

    /// Size and modification time of the files that show a transcript changed (a database's
    /// write-ahead log grows while the database file stays put).
    private struct TranscriptStamp: Equatable, Sendable {
        struct Mark: Equatable, Sendable {
            var size: Int
            var modified: Date
        }

        var path: String
        var marks: [Mark]

        var modified: Date {
            marks.map(\.modified).max() ?? .distantPast
        }
    }

    /// What one background read of an agent's transcript found.
    private struct TranscriptRead: Sendable {
        var located: (agentSessionID: String, path: String)?
        var stamp: TranscriptStamp?
        var tail: TranscriptTail?
    }

    func start() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
        timer?.tolerance = 0.5
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    // MARK: Launch

    /// Settles the saved agent runs before the window opens (DESIGNS.md → Launch): is each agent
    /// still running in its shell, and what does it say about itself? The reads run off the main
    /// thread and the window waits for them up to `LaunchPass.budget`, so the sidebar almost
    /// always opens right. If they take longer, the rows show as loading until they finish, and
    /// a pass that hasn't answered by `LaunchPass.deadline` is given up on.
    func settleSavedRuns() {
        let manager = SessionManager.shared
        let questions = manager.workspace.sessions.compactMap { session in
            session.agent.map { LaunchPass.Question(id: session.id, shellName: session.persistentName, kind: $0.kind) }
        }
        guard !questions.isEmpty else { return }
        // Without zmx the shells ended with Calm, and so did their agents.
        guard manager.persistenceEnabled, PersistentShell.isAvailable else {
            manager.settleSavedRuns(nil)
            Trace.note("launch pass: no persistent shells, \(questions.count) saved runs ended")
            return
        }
        let started = ContinuousClock.now
        let home = FileManager.default.homeDirectoryForCurrentUser
        let box = AnswerBox()
        let group = DispatchGroup()
        group.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            box.answer = LaunchPass.run(questions, home: home)
            group.leave()
        }
        if group.wait(timeout: .now() + LaunchPass.budget) == .success {
            seed(box.answer)
            manager.settleSavedRuns(box.answer)
            let took = Trace.milliseconds(started.duration(to: .now))
            Trace.note("launch pass: \(questions.count) saved runs settled in \(took), before the window")
            return
        }
        manager.beginConfirming(Set(questions.map(\.id)))
        Trace.note("launch pass: not done in \(LaunchPass.budgetMilliseconds) ms, \(questions.count) rows show as loading")
        savedRunsPending = true
        group.notify(queue: .main) { [weak self] in
            MainActor.assumeIsolated { self?.finishSavedRuns(box.answer, gaveUp: false, since: started) }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + LaunchPass.deadline) { [weak self] in
            MainActor.assumeIsolated { self?.finishSavedRuns(nil, gaveUp: true, since: started) }
        }
    }

    /// The pass answered after the window opened, or the deadline came first: whichever is first.
    private func finishSavedRuns(_ answer: LaunchPass.Answer?, gaveUp: Bool, since started: ContinuousClock.Instant) {
        guard savedRunsPending else { return }
        savedRunsPending = false
        let took = Trace.milliseconds(started.duration(to: .now))
        Trace.note(gaveUp ? "launch pass: no answer after \(took), saved runs end" : "launch pass: answered after \(took)")
        seed(answer)
        SessionManager.shared.finishConfirming(answer)
    }

    /// What the pass learned, so the first regular probe neither asks zmx again nor takes the
    /// agents it just confirmed for new ones.
    private func seed(_ answer: LaunchPass.Answer?) {
        guard let answer else { return }
        shellProcesses = answer.shells
        lastListing = Date()
        for (id, found) in answer.outcomes {
            if case let .running(_, processID, _) = found {
                foregroundJobs[id] = processID
            }
        }
    }

    private func poll() {
        let manager = SessionManager.shared
        let persistent = manager.persistenceEnabled && PersistentShell.isAvailable
        for session in manager.workspace.sessions {
            let pane = manager.panes[session.id]
            if persistent {
                guard let shell = shellProcess(named: session.persistentName) else { continue }
                if pane?.reportsWorkingDirectory != true, let directory = Self.workingDirectory(of: shell) {
                    manager.workingDirectoryChanged(session.id, directory)
                }
                noteForegroundJob(ProcessInspector.foregroundJob(ofShell: shell) ?? 0, of: session.id)
            } else if let pane, let foreground = pane.foregroundProcessID {
                if !pane.reportsWorkingDirectory, let directory = Self.workingDirectory(of: foreground) {
                    manager.workingDirectoryChanged(session.id, directory)
                }
                noteForegroundJob(foreground, of: session.id)
            }
        }
        for session in manager.workspace.sessions {
            // A hook's read a moment ago stands for this tick's (`readSoon`).
            if let agent = session.agent, Date().timeIntervalSince(lastReads[session.id] ?? .distantPast) > Self.readSpacing - 0.5 {
                readTranscriptIfChanged(session.id, agent)
            }
        }
        // A few syscalls per agent; an update is news for hours, so every 10 s is plenty.
        ticks += 1
        if ticks % 5 == 1 {
            manager.checkAgentVersions()
        }
        if !manager.restarts.isEmpty {
            manager.runDueRestarts()
        }
        let live = Set(manager.workspace.sessions.map(\.id))
        foregroundJobs = foregroundJobs.filter { live.contains($0.key) }
        transcriptStamps = transcriptStamps.filter { live.contains($0.key) }
        lastDiscoveries = lastDiscoveries.filter { live.contains($0.key) }
        lastReads = lastReads.filter { live.contains($0.key) }
    }

    /// An agent's hook just spoke: what it did is usually in its transcript by now, so read it
    /// in a moment rather than at the next tick, and the card's recap keeps up with the working
    /// line. No more often than the tick reads (every `readSpacing`, which the tick then skips
    /// too): a changed tail writes the workspace, and that redraws the whole sidebar. A hook
    /// while a read runs gets one more after it. The tick stays: it's what notices an Esc (no
    /// hook says so), and agents coming and going.
    func readSoon(_ id: Session.ID) {
        guard !soonReads.contains(id) else { return }
        if readingTranscripts.contains(id) {
            rereads.insert(id)
            return
        }
        soonReads.insert(id)
        let spaced = lastReads[id].map { $0.addingTimeInterval(Self.readSpacing).timeIntervalSinceNow } ?? 0
        DispatchQueue.main.asyncAfter(deadline: .now() + max(0.25, spaced)) { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.soonReads.remove(id)
                guard let agent = SessionManager.shared.workspace.session(id)?.agent else { return }
                if self.readingTranscripts.contains(id) {
                    self.rereads.insert(id)
                } else {
                    self.readTranscriptIfChanged(id, agent)
                }
            }
        }
    }

    /// Re-reads an agent's transcript when it changed. The reading is file work (a Codex or pi
    /// transcript can hold megabytes of tool output to step past), so it runs off the main
    /// thread and the result comes back to it.
    ///
    /// Where the transcript is: what a hook said, else what the adapter finds from the agent's
    /// process. Finding is tried every few seconds until it works, then every so often again,
    /// because an agent's own `/new` starts another transcript.
    private func readTranscriptIfChanged(_ id: Session.ID, _ agent: AgentRun) {
        guard !readingTranscripts.contains(id), let reader = Agents.transcriptReader(for: agent.kind) else { return }
        let known = (path: agent.transcriptPath, agentSessionID: agent.agentSessionID)
        let interval: TimeInterval = known.path == nil ? 4 : 20
        let discover = agent.processID > 0 && Date().timeIntervalSince(lastDiscoveries[id] ?? .distantPast) > interval
        guard discover || known.path != nil else { return }
        if discover {
            lastDiscoveries[id] = Date()
        }
        lastReads[id] = Date()
        readingTranscripts.insert(id)
        let previous = transcriptStamps[id]
        let processID = agent.processID
        let kind = agent.kind
        let home = FileManager.default.homeDirectoryForCurrentUser
        Task.detached(priority: .utility) { [weak self] in
            let read = Self.readTranscript(
                reader, home: home, processID: processID, known: known, discover: discover, previous: previous,
            )
            await self?.finishReading(id, kind: kind, read)
        }
    }

    private nonisolated static func readTranscript(
        _ reader: any TranscriptReading,
        home: URL,
        processID: Int32,
        known: (path: String?, agentSessionID: String?),
        discover: Bool,
        previous: TranscriptStamp?,
    ) -> TranscriptRead {
        var path = known.path
        var agentSessionID = known.agentSessionID
        var located: (agentSessionID: String, path: String)?
        if discover, let found = reader.transcript(forProcess: processID, home: home), found.url.path != path {
            path = found.url.path
            agentSessionID = found.agentSessionID
            located = (found.agentSessionID, found.url.path)
        }
        guard let path else { return TranscriptRead(located: located) }
        let url = URL(filePath: path)
        let marks = reader.changeMarkers(of: url).compactMap { file -> TranscriptStamp.Mark? in
            guard let attributes = try? FileManager.default.attributesOfItem(atPath: file.path) else { return nil }
            return TranscriptStamp.Mark(
                size: (attributes[.size] as? NSNumber)?.intValue ?? 0,
                modified: attributes[.modificationDate] as? Date ?? .distantPast,
            )
        }
        let stamp = TranscriptStamp(path: path, marks: marks)
        guard !marks.isEmpty, stamp != previous else { return TranscriptRead(located: located) }
        return TranscriptRead(
            located: located, stamp: stamp, tail: reader.readTail(of: url, agentSessionID: agentSessionID, home: home),
        )
    }

    private func finishReading(_ id: Session.ID, kind: AgentKind, _ read: TranscriptRead) {
        readingTranscripts.remove(id)
        if rereads.remove(id) != nil {
            readSoon(id)
        }
        let manager = SessionManager.shared
        // The agent may have exited, or another started, while the file was being read.
        guard manager.workspace.session(id)?.agent?.kind == kind else { return }
        if let located = read.located {
            manager.noteAgentSession(id, kind: kind, agentSessionID: located.agentSessionID, transcriptPath: located.path)
        }
        if let stamp = read.stamp {
            transcriptStamps[id] = stamp
            if let tail = read.tail {
                manager.transcriptChanged(id, tail, modified: stamp.modified)
            }
        }
    }

    /// The agent that holds the session's terminal foreground, read from its process as it is now:
    /// the last tick says which process that is, and it may have exited since (then nothing is
    /// recognised). Not `session.agent`: a report can have replaced that run, which is exactly
    /// what this is asked to check (`AgentKind.speaksForSession`).
    func foregroundAgent(of id: Session.ID) -> AgentKind? {
        guard let job = foregroundJobs[id], job > 0 else { return nil }
        return Agents.detect(processID: job)
    }

    private func noteForegroundJob(_ job: Int32, of id: Session.ID) {
        guard foregroundJobs[id] != job else { return }
        foregroundJobs[id] = job
        SessionManager.shared.foregroundChanged(id, to: job > 0 ? ProcessInspector.snapshot(of: job) : nil)
    }

    private func shellProcess(named name: String) -> pid_t? {
        if let pid = shellProcesses[name], kill(pid, 0) == 0 {
            return pid
        }
        // Listing spawns zmx, so do it at most every few seconds.
        guard Date().timeIntervalSince(lastListing) > 5 else { return nil }
        lastListing = Date()
        shellProcesses = PersistentShell.shellProcesses()
        return shellProcesses[name]
    }

    static func workingDirectory(of pid: pid_t) -> String? {
        var info = proc_vnodepathinfo()
        let size = Int32(MemoryLayout<proc_vnodepathinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDVNODEPATHINFO, 0, &info, size) == size else { return nil }
        let path = withUnsafeBytes(of: info.pvi_cdir.vip_path) { String(bytes: $0.prefix { $0 != 0 }, encoding: .utf8) }
        return path?.isEmpty == false ? path : nil
    }
}

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
            if let agent = session.agent {
                readTranscriptIfChanged(session.id, agent)
            }
        }
        let live = Set(manager.workspace.sessions.map(\.id))
        foregroundJobs = foregroundJobs.filter { live.contains($0.key) }
        transcriptStamps = transcriptStamps.filter { live.contains($0.key) }
        lastDiscoveries = lastDiscoveries.filter { live.contains($0.key) }
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

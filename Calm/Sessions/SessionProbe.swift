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
        let live = Set(manager.workspace.sessions.map(\.id))
        foregroundJobs = foregroundJobs.filter { live.contains($0.key) }
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

import Darwin
import Foundation
import GhosttyKit

/// Finds a session's folder from its shell process, for shells that don't report it
/// themselves (no OSC 7, e.g. bash without Ghostty's integration).
///
/// Only panes that have never sent OSC 7 are looked at, every couple of seconds, with one
/// `proc_pidinfo` call each. A persistent session's shell runs under zmx, so its process is
/// found through `zmx list` (only when one isn't known yet); otherwise the pane's own
/// foreground process is used.
@MainActor
final class WorkingDirectoryProbe {
    static let shared = WorkingDirectoryProbe()

    private var timer: Timer?
    private var shellProcesses: [String: pid_t] = [:]
    private var lastListing = Date.distantPast

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
        for (id, pane) in manager.panes where !pane.reportsWorkingDirectory {
            guard let session = manager.workspace.session(id),
                  let pid = process(for: session.persistentName, pane: pane, persistent: manager.persistenceEnabled),
                  let directory = Self.workingDirectory(of: pid)
            else { continue }
            manager.workingDirectoryChanged(id, directory)
        }
    }

    private func process(for name: String, pane: TerminalSurfaceView, persistent: Bool) -> pid_t? {
        guard persistent, PersistentShell.isAvailable else {
            guard let surface = pane.surface else { return nil }
            let pid = ghostty_surface_foreground_pid(surface)
            return pid > 0 ? pid_t(pid) : nil
        }
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

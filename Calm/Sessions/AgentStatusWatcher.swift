import CalmAgents
import CalmModel
import Darwin
import Foundation

/// Hears the file an agent keeps about its own process change (`LiveStatusReading`), through the
/// system's file events: nothing runs between changes, so a session at rest costs nothing, and a
/// change reaches the row as it happens. What the file says is read when it changes, never
/// before: a status already there when the watch began is not news.
///
/// A file that isn't there, or can't be opened, is simply not watched; hooks alone speak for the
/// session, as they did before.
@MainActor
final class AgentStatusWatcher {
    private struct Watch {
        var reader: any LiveStatusReading
        var processID: Int32
        var source: any DispatchSourceFileSystemObject
    }

    private var watches: [Session.ID: Watch] = [:]
    private let home: URL
    private let changed: (Session.ID, AgentLiveStatus) -> Void

    init(home: URL, changed: @escaping (Session.ID, AgentLiveStatus) -> Void) {
        self.home = home
        self.changed = changed
    }

    /// Watches the status file of `processID`, the agent in session `id`, unless it already is.
    func watch(_ id: Session.ID, reader: any LiveStatusReading, processID: Int32) {
        if watches[id]?.processID == processID {
            return
        }
        stop(id)
        // `O_EVTONLY`: only for events, so the file can still be unmounted or removed.
        let descriptor = open(reader.statusFile(processID: processID, home: home).path, O_EVTONLY)
        guard descriptor >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor, eventMask: [.write, .extend, .delete, .rename], queue: .main,
        )
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated { self?.fired(id) }
        }
        source.setCancelHandler { close(descriptor) }
        source.resume()
        watches[id] = Watch(reader: reader, processID: processID, source: source)
    }

    func stop(_ id: Session.ID) {
        watches.removeValue(forKey: id)?.source.cancel()
    }

    /// Stops watching the sessions that are gone.
    func keep(only ids: Set<Session.ID>) {
        for id in watches.keys where !ids.contains(id) {
            stop(id)
        }
    }

    private func fired(_ id: Session.ID) {
        guard let watch = watches[id] else { return }
        // The agent replaced the file (a new inode): what this watches is gone, so follow the new one.
        if !watch.source.data.isDisjoint(with: [.delete, .rename]) {
            stop(id)
            self.watch(id, reader: watch.reader, processID: watch.processID)
        }
        if let status = watch.reader.liveStatus(processID: watch.processID, home: home) {
            changed(id, status)
        }
    }
}

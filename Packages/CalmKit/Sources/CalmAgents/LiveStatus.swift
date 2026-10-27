import CalmModel
import Foundation

/// Agents that keep a file saying what they are doing right now (DESIGNS.md → The sidebar comes back as it was left, checked before the
/// window opens). Calm asks
/// once at launch, so a row that was *working* when Calm quit doesn't wait for the agent's next
/// hook to say so. Formats are undocumented and change: anything unexpected reads as "nothing
/// known", never an error.
public protocol LiveStatusReading: AgentAdapter {
    /// The file the agent running as `processID` keeps about itself. The agent rewrites it in
    /// place, so the system can say when it changes (`AgentStatusWatcher`).
    func statusFile(processID: Int32, home: URL) -> URL

    /// What the agent running as `processID` says about itself, or nil when it can't say: no
    /// file, an unreadable one, another process's, or wording Calm doesn't know.
    func liveStatus(processID: Int32, home: URL) -> AgentLiveStatus?
}

public extension Agents {
    static func liveStatusReader(for kind: AgentKind) -> (any LiveStatusReading)? {
        adapter(for: kind) as? any LiveStatusReading
    }
}

/// `~/.claude/sessions/<pid>.json`, one per running process, rewritten in place (same inode all
/// session, seen on 2.1.296): `status` is `busy`, `idle`, or `waiting` with a `waitingFor`
/// ("permission prompt" seen; "input needed" and "dialog open" are in the binary), and
/// `statusUpdatedAt` is the milliseconds since 1970 at which it last changed. A turn that ended
/// with a background shell still running says `shell` (seen), which reads as no status. It
/// changes only when the status does (`updatedAt` moved with it in every capture), and it goes
/// idle when Esc withdraws a prompt or answers a dialog, which no hook reports.
extension ClaudeCodeAdapter: LiveStatusReading {
    public func statusFile(processID: Int32, home: URL) -> URL {
        home.appending(path: ".claude/sessions/\(processID).json")
    }

    public func liveStatus(processID: Int32, home: URL) -> AgentLiveStatus? {
        guard let data = try? Data(contentsOf: statusFile(processID: processID, home: home)) else { return nil }
        return Self.liveStatus(fromSessionFile: data, processID: processID)
    }

    static func liveStatus(fromSessionFile data: Data, processID: Int32) -> AgentLiveStatus? {
        guard let file = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              // The file is named for the process, and says so: another number is another process's.
              (file["pid"] as? NSNumber)?.int32Value == processID,
              let status = file["status"] as? String,
              let millis = (file["statusUpdatedAt"] as? NSNumber)?.doubleValue, millis > 0
        else { return nil }
        let phase: AgentLiveStatus.Phase
        switch status {
        case "busy": phase = .busy
        case "idle": phase = .idle
        case "waiting": phase = .waiting
        default: return nil
        }
        return AgentLiveStatus(phase: phase, since: Date(timeIntervalSince1970: millis / 1000))
    }
}

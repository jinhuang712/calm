import CalmModel
import Foundation

/// Agents that keep a file saying what they are doing right now (DESIGNS.md → Launch). Calm asks
/// once at launch, so a row that was *working* when Calm quit doesn't wait for the agent's next
/// hook to say so. Formats are undocumented and change: anything unexpected reads as "nothing
/// known", never an error.
public protocol LiveStatusReading: AgentAdapter {
    /// What the agent running as `processID` says about itself, or nil when it can't say: no
    /// file, an unreadable one, another process's, or wording Calm doesn't know.
    func liveStatus(processID: Int32, home: URL) -> AgentLiveStatus?
}

public extension Agents {
    static func liveStatusReader(for kind: AgentKind) -> (any LiveStatusReading)? {
        adapter(for: kind) as? any LiveStatusReading
    }
}

/// `~/.claude/sessions/<pid>.json`, one per running process (Claude Code 2.1.283 and 2.1.284):
/// `status` is `busy` or `idle` (both seen on disk) or `waiting` (in the binary, with a
/// `waitingFor` such as "dialog open"; not yet seen on disk), and `statusUpdatedAt` is the
/// milliseconds since 1970 at which it last changed. `updatedAt` moves more often and says
/// nothing about the turn.
extension ClaudeCodeAdapter: LiveStatusReading {
    public func liveStatus(processID: Int32, home: URL) -> AgentLiveStatus? {
        let url = home.appending(path: ".claude/sessions/\(processID).json")
        guard let data = try? Data(contentsOf: url) else { return nil }
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

import CalmModel
import Foundation

/// What an agent's hook payload says, ready for `calm status`: the state, the agent's own
/// words, and which of the agent's sessions and transcripts this is (for transcript tails).
public struct HookReport: Equatable, Sendable {
    public var state: SessionState
    public var message: String?
    public var agentSessionID: String?
    public var transcriptPath: String?
    /// Shells still running when the turn ended (monitors and kinds Calm doesn't know count
    /// too). They don't make the session *working*: nothing wakes the agent if one never ends.
    public var backgroundShells: Int

    public init(
        state: SessionState,
        message: String? = nil,
        agentSessionID: String? = nil,
        transcriptPath: String? = nil,
        backgroundShells: Int = 0,
    ) {
        self.state = state
        self.message = message
        self.agentSessionID = agentSessionID
        self.transcriptPath = transcriptPath
        self.backgroundShells = backgroundShells
    }

    /// Long agent messages are cut for a one- or two-line recap.
    public static func recap(_ text: String?, limit: Int = 280) -> String? {
        guard let text else { return nil }
        let flat = text
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        guard !flat.isEmpty else { return nil }
        return flat.count > limit ? String(flat.prefix(limit - 1)) + "…" : flat
    }
}

/// Agents whose hooks can call `calm hook <name>` with their payload on stdin.
public protocol HookReporting: AgentAdapter {
    /// The name used in `calm hook <name>`.
    var hookName: String { get }
    /// Reads one hook payload; nil for events that don't change the session's state.
    func hookReport(from payload: Data) -> HookReport?
}

public extension Agents {
    static func hookReporter(named name: String) -> (any HookReporting)? {
        adapters.lazy.compactMap { $0 as? any HookReporting }.first { $0.hookName == name }
    }
}

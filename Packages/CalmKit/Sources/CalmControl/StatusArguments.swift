import Foundation

/// The words after `calm status` (or `calm notify`): options first or anywhere, then the state
/// and message. `--agent`, `--agent-session` and `--transcript` tell Calm which agent this is
/// and which of its conversations, for agents that can't send a hook payload (pi's extension).
public struct StatusArguments: Equatable, Sendable {
    /// The session Calm started the shell in, unless `--session` says otherwise.
    public var session: String?
    public var agent: String?
    public var agentSession: String?
    public var transcript: String?
    /// What is left: the state, then the message.
    public var words: [String]

    /// An option whose value is missing (it ended the arguments) is dropped, not kept as a word.
    public static func parse(_ arguments: [String], defaultSession: String?) -> StatusArguments {
        var parsed = StatusArguments(session: defaultSession.flatMap { $0.isEmpty ? nil : $0 }, words: [])
        var iterator = arguments.makeIterator()
        while let word = iterator.next() {
            switch word {
            case "--session": parsed.session = iterator.next()
            case "--agent": parsed.agent = iterator.next()
            case "--agent-session": parsed.agentSession = iterator.next()
            case "--transcript": parsed.transcript = iterator.next()
            default: parsed.words.append(word)
            }
        }
        return parsed
    }
}

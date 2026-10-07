import CalmModel
import Foundation

/// Agents that put a tag in for an image pasted into their prompt, such as Claude Code's
/// `[Image #4]` (FEATURES.md → F8): Calm finds the image behind it for ⌘-hover and ⌘-click.
/// The agent keeps the image itself, where only its adapter knows to look.
public protocol PastedImageResolving: AgentAdapter {
    /// The tag, as an `NSRegularExpression` pattern whose one capture group is the image's number.
    var pastedImagePattern: String { get }
    /// The image behind a tag, read when asked and never kept: nil when it can't be found.
    func pastedImage(_ query: PastedImageQuery) -> URL?
}

/// Which tag, and what Calm knows of the agent running where it is.
public struct PastedImageQuery: Sendable, Equatable {
    public var number: Int
    /// The agent's process, 0 when only hooks have spoken.
    public var processID: Int32
    /// The agent's own conversation, as its hooks last reported it.
    public var agentSessionID: String?
    public var home: URL
    /// The environment the pane's shell started with.
    public var environment: [String: String]

    public init(number: Int, processID: Int32, agentSessionID: String?, home: URL, environment: [String: String]) {
        self.number = number
        self.processID = processID
        self.agentSessionID = agentSessionID
        self.home = home
        self.environment = environment
    }
}

public extension Agents {
    static func pastedImageResolver(for kind: AgentKind) -> (any PastedImageResolving)? {
        adapter(for: kind) as? any PastedImageResolving
    }
}

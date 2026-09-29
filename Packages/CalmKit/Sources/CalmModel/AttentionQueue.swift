import Foundation

/// Holds notifications until a natural pause (DESIGNS.md → Attention → notification
/// scheduling): the user stops typing for a moment, switches focus, or a maximum wait passes.
/// Nothing is ever dropped; a session's newer message replaces its older one.
public struct AttentionQueue: Sendable, Equatable {
    public struct Item: Sendable, Equatable {
        public var sessionID: UUID
        /// What the agent or program said, if anything.
        public var message: String?
        /// What happened, or nil for a notice that isn't a state change (`calm notify`).
        public var state: SessionState?
        public var queuedAt: Date
    }

    /// How long without typing counts as a pause.
    public static let quietInterval: TimeInterval = 3
    /// The longest a notification waits for a pause.
    public static let maximumWait: TimeInterval = 60

    public private(set) var pending: [Item] = []
    private var lastTyping: Date?
    private var lastFocusChange: Date?

    public init() {}

    public mutating func enqueue(_ sessionID: UUID, message: String?, state: SessionState? = nil, at date: Date) {
        pending.removeAll { $0.sessionID == sessionID }
        pending.append(Item(sessionID: sessionID, message: message, state: state, queuedAt: date))
    }

    /// The session was visited or stopped waiting; its notification no longer applies.
    public mutating func withdraw(_ sessionID: UUID) {
        pending.removeAll { $0.sessionID == sessionID }
    }

    public mutating func noteTyping(at date: Date) {
        lastTyping = date
    }

    /// Switching sessions or apps is a natural pause.
    public mutating func noteFocusChange(at date: Date) {
        lastFocusChange = date
    }

    /// Removes and returns the notifications that may be delivered now.
    public mutating func takeDue(at now: Date) -> [Item] {
        let quiet = lastTyping.map { now.timeIntervalSince($0) >= Self.quietInterval } ?? true
        let due = pending.filter { item in
            quiet
                || lastFocusChange.map { $0 >= item.queuedAt } == true
                || now.timeIntervalSince(item.queuedAt) >= Self.maximumWait
        }
        pending.removeAll { item in due.contains(item) }
        return due
    }
}

/// What a session is doing, as shown in the sidebar (see UIUX.md → Session states).
public enum SessionState: String, Sendable, CaseIterable, Codable {
    case idle
    case working
    case needsYou
    case done
    case failed

    /// Only *needs you* may move to the center of attention and notify.
    public var mayInterrupt: Bool {
        self == .needsYou
    }

    /// Visiting a session settles finished states back to idle; states that
    /// still expect something from the agent or the user are kept.
    public func afterVisit() -> SessionState {
        switch self {
        case .done, .failed: .idle
        case .idle, .working, .needsYou: self
        }
    }
}

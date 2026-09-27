import Foundation

/// Things a program in a terminal can say without any hooks: the fallback signals of
/// DESIGNS.md → Attention.
public enum TerminalSignal: Equatable, Sendable {
    /// OSC 9;4 progress.
    public enum Progress: Equatable, Sendable {
        case active
        case paused
        case error
        case cleared
    }

    case bell
    /// OSC 9 / OSC 777 desktop notification.
    case notification(title: String, body: String)
    case progress(Progress)
    /// Shell integration's command-finished mark (OSC 133).
    case commandFinished(exitCode: Int?, duration: TimeInterval)

    /// What a signal means for a session.
    public enum Outcome: Equatable, Sendable {
        case report(SessionState, message: String?)
        /// Pass the program's own notification on to the user.
        case notify(String)
        case ignore
    }

    /// Commands shorter than this finishing in a plain shell aren't worth a mark.
    public static let longCommand: TimeInterval = 10

    /// Interprets a signal. In an agent session, progress means working and a notification is
    /// read by its words: only an explicit ask becomes *needs you*, so a guess never interrupts
    /// for nothing. In a plain shell, a long command finishing marks the session done or failed.
    public func outcome(currentState: SessionState, hasAgent: Bool) -> Outcome {
        switch self {
        case .bell:
            // A bell is ambiguous; only an agent that was working and rings is taken as asking.
            return hasAgent && currentState == .working ? .report(.needsYou, message: nil) : .ignore
        case let .notification(title, body):
            let text = [title, body].filter { !$0.isEmpty }.joined(separator: ": ")
            guard !text.isEmpty else { return .ignore }
            guard hasAgent else { return .notify(text) }
            return .report(Self.classify(title: title, body: body), message: body.isEmpty ? title : body)
        case let .progress(progress):
            switch progress {
            case .active: return currentState == .working ? .ignore : .report(.working, message: nil)
            case .paused: return .ignore
            case .error: return .report(.failed, message: nil)
            case .cleared:
                guard currentState == .working else { return .ignore }
                return .report(hasAgent ? .done : .idle, message: nil)
            }
        case let .commandFinished(exitCode, duration):
            guard !hasAgent, duration >= Self.longCommand else { return .ignore }
            if let exitCode, exitCode != 0 {
                return .report(.failed, message: "Exited with \(exitCode) after \(Self.format(duration))")
            }
            return .report(.done, message: "Finished after \(Self.format(duration))")
        }
    }

    /// Reads an agent's notification: an explicit ask, an error, or a finished turn.
    static func classify(title: String, body: String) -> SessionState {
        let text = "\(title) \(body)".lowercased()
        // "Waiting for (your) input" is an idle agent after its turn, not a question.
        if text.contains("waiting for input") || text.contains("waiting for your input") {
            return .done
        }
        let asks = ["permission", "approve", "approval", "allow ", "confirm", "question", "needs your", "requires your"]
        if asks.contains(where: text.contains) {
            return .needsYou
        }
        let failures = ["error", "failed", "failure"]
        if failures.contains(where: text.contains) {
            return .failed
        }
        return .done
    }

    static func format(_ duration: TimeInterval) -> String {
        let seconds = Int(duration.rounded())
        return seconds < 60 ? "\(seconds) s" : "\(seconds / 60) min \(seconds % 60) s"
    }
}

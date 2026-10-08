import CalmModel
import Observation

/// One session's working line (`LiveLine`), kept apart from the workspace. It moves on every tool
/// call an agent makes, and a write to the workspace has the whole sidebar render again (13 to 20
/// million instructions, DESIGNS.md → State machine); a write here has only its own card render.
@MainActor
@Observable
final class LiveLineBox {
    private(set) var line: LiveLine?

    /// Stores `line` only when it differs: every set tells the card, equal or not.
    func set(_ line: LiveLine?) {
        if line != self.line {
            self.line = line
        }
    }
}

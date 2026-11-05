import CalmAgents
import Foundation
import GhosttyKit

extension TerminalSurfaceView {
    /// How long a command waits for a shell's prompt. A slow `.zshrc` past this only shows it twice.
    private static let promptWait = Duration.seconds(5)

    /// Types a command into the shell and presses Return, as if from the keyboard (e.g. resuming
    /// an agent session). It waits for the prompt when the shell marks one: text typed earlier
    /// shows twice, as the terminal echoes it and again when the prompt reads it (seen 2026-11-05).
    /// Past `promptWait`, or with no marks, it goes at once, and waits in the shell's input.
    func run(_ command: String) {
        guard marksPrompts, needsConfirmQuit else {
            typeAndReturn(command)
            return
        }
        Task { [weak self] in
            let deadline = ContinuousClock.now + Self.promptWait
            while let self, self.needsConfirmQuit, ContinuousClock.now < deadline {
                try? await Task.sleep(for: .milliseconds(20))
            }
            self?.typeAndReturn(command)
        }
    }

    private func typeAndReturn(_ command: String) {
        guard let surface else { return }
        // A long command would be cut by the terminal's line limit before the shell reads it.
        let command = LongCommand.typed(command, in: FileManager.default.temporaryDirectory.appending(path: "calm-commands"))
        command.withCString { ghostty_surface_text(surface, $0, UInt(command.utf8.count)) }
        var key = ghostty_input_key_s()
        key.action = GHOSTTY_ACTION_PRESS
        key.keycode = 36 // Return
        key.mods = GHOSTTY_MODS_NONE
        key.consumed_mods = GHOSTTY_MODS_NONE
        key.unshifted_codepoint = 13
        "\r".withCString { pointer in
            key.text = pointer
            _ = ghostty_surface_key(surface, key)
        }
        key.action = GHOSTTY_ACTION_RELEASE
        key.text = nil
        _ = ghostty_surface_key(surface, key)
    }
}

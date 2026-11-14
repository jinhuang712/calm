#if DEBUG
    import AppKit

    /// Self-test driver for restarting an agent (specs/FEATURES.md → F12). It needs a stand-in agent:
    /// a script that runs `exec -a claude /bin/sleep 600` (or `codex`), which Calm detects by its name,
    /// and `agent_run:<agent>:<id>` to give it a conversation, as the hooks would.
    /// - `restart_agent`: what Restart in the session menu does for the agent in the focused session. It
    ///   quits the stand-in the way its adapter does (a signal, or ⌃C through the pane), and a headless
    ///   run logs the command it would type in place of typing it.
    extension MainWindowController {
        func performRestartActionForTesting(_ action: String) -> Bool {
            guard action == "restart_agent" else { return false }
            focusedPane.map { _ = manager.requestRestart($0.id) }
            return true
        }
    }
#endif

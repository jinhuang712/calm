#if DEBUG
    import AppKit
    import CalmAgents
    import CalmControl
    import CalmModel

    extension MainWindowController {
        /// A compaction on the focused session's card (run `agent:<state>` first, after the waits):
        /// `hook_compact:<start|end>:<manual|auto>` sends Claude Code's PreCompact or PostCompact the
        /// way a real one arrives (payloads as 2.1.291 sends them), through the adapter and the
        /// control handler as `hook_stop` does; `agent_context:<tokens>` says what the agent's last
        /// reply saw, as its transcript's usage does; `agent_compacted:<before>:<after>` has the
        /// transcript record a compaction that just ended, as Claude Code's compact_boundary does.
        /// False for any other action.
        func performCompactionActionForTesting(_ action: String) -> Bool {
            let argument = action.drop { $0 != ":" }.dropFirst().split(separator: ":").map(String.init)
            switch String(action.prefix { $0 != ":" }) {
            case "hook_compact":
                guard argument.count == 2 else { return false }
                return sendCompactionForTesting(start: argument[0] == "start", trigger: argument[1])
            case "agent_context":
                guard let id = focusedPane?.id, var tail = manager.workspace.session(id)?.agent?.tail else { return false }
                tail.contextTokens = argument.first.flatMap { Int($0) }
                manager.transcriptChanged(id, tail, modified: .now)
            case "agent_compacted":
                let sizes = argument.compactMap { Int($0) }
                guard sizes.count == 2, let id = focusedPane?.id,
                      var tail = manager.workspace.session(id)?.agent?.tail else { return false }
                tail.lastCompaction = CompactedContext(date: .now, tokensBefore: sizes[0], tokensAfter: sizes[1])
                manager.transcriptChanged(id, tail, modified: .now)
            default:
                return false
            }
            return true
        }

        private func sendCompactionForTesting(start: Bool, trigger: String) -> Bool {
            guard let id = focusedPane?.id, let reporter = Agents.hookReporter(named: "claude-code") else { return false }
            let payload = start
                ? #"{"hook_event_name":"PreCompact","trigger":"\#(trigger)","custom_instructions":null}"#
                : #"{"hook_event_name":"PostCompact","trigger":"\#(trigger)","compact_summary":"<summary>…</summary>"}"#
            guard let hook = reporter.hookReport(from: Data(payload.utf8)) else { return false }
            let response = ControlServer.shared.handle(ControlRequest(
                cmd: .status, session: id.uuidString, state: hook.state.reportName, message: hook.message,
                agent: reporter.kind.rawValue, agentSession: hook.agentSessionID, transcript: hook.transcriptPath,
                compaction: hook.compaction?.reportName,
            ))
            let result = "\(hook.state.reportName), \(hook.compaction?.reportName ?? "none"), ok \(response.ok)"
            FileHandle.standardError.write(Data("calm-selftest: hook_compact → \(result)\n".utf8))
            return response.ok
        }
    }
#endif

import AppKit
import CalmAgents
import CalmModel
import SwiftUI

/// ⌘P (FEATURES.md → Command palette, UIUX.md → Command palette): what Calm does that has no key
/// everyone knows. Every row does its whole job when chosen: no second list, no picker.
extension MainWindowController {
    var isShowingCommandPalette: Bool {
        paletteHost != nil
    }

    func toggleCommandPalette() {
        if isShowingCommandPalette {
            hideCommandPalette()
        } else {
            showCommandPalette()
        }
    }

    private func showCommandPalette() {
        guard paletteHost == nil else { return }
        let commands = paletteCommands()
        if Headless.isOn {
            let rows = commands.map { $0.title + ($0.trailing.isEmpty ? "" : " [\($0.trailing)]") }
            let bare = commands.filter(\.detail.isEmpty).map(\.title)
            var line = "calm-selftest: palette: \(commands.count) rows: \(rows.joined(separator: " | "))"
            if !bare.isEmpty {
                line += "; no description: \(bare)"
            }
            FileHandle.standardError.write(Data((line + "\n").utf8))
        }
        let isDark = window?.appearance?.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let view = CommandPaletteView(
            commands: commands,
            isDark: isDark,
            onRun: { [weak self] command in self?.runPaletteCommand(command) },
            onDismiss: { [weak self] in self?.hideCommandPalette() },
        )
        let host = NSHostingView(rootView: view)
        host.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(host)
        NSLayoutConstraint.activate([
            host.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            host.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            host.topAnchor.constraint(equalTo: container.topAnchor),
            host.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        paletteHost = host
        window?.makeFirstResponder(host)
    }

    private func hideCommandPalette() {
        guard let host = paletteHost else { return }
        paletteHost = nil
        host.removeFromSuperview()
        refocus()
    }

    /// Closes the palette, then does what the row says: focus is back on the session (or goes to
    /// what the row opens) before the row runs.
    func runPaletteCommand(_ command: PaletteCommand) {
        hideCommandPalette()
        command.run()
    }

    // MARK: The rows, by category

    /// Agent conversation, session, view, folder, look, Calm, terminal: the order they are read in.
    /// A row shows only where it applies.
    func paletteCommands() -> [PaletteCommand] {
        // Settings covers the session, so its own rows would act out of sight.
        let inFront = manager.workspace.selectedLayout.flatMap { manager.workspace.session($0.focusedSessionID) }
        let focused = settingsPage.isShowing ? nil : inFront
        let own = focused.map { session in
            PaletteCommand.session(session, menu: sessionActions, palette: PaletteSessionActions(
                rename: { [weak self] in self?.beginRename(session.id) },
                copyLastReply: { [weak self] id in self?.copyLastReply(of: id) },
                openTranscript: { [weak self] id in self?.openTranscript(of: id) },
                restart: { [weak self] id in self?.restartAgent(in: id) },
                cancelRestart: { [weak self] id in self?.manager.cancelRestart(id) },
                restartPending: manager.restarts[session.id] == .afterTurn,
            ))
        } ?? SessionRows()
        return agentCommands(own.agent, focused: focused) + sessionCommands(own.session, focused: focused) + viewCommands()
            + own.folder + lookCommands() + calmCommands() + terminalCommands()
    }

    private func agentCommands(_ own: [PaletteCommand], focused: Session?) -> [PaletteCommand] {
        var rows = own
        // Restart All for each agent running somewhere, unless it would only repeat the session
        // in front's own Restart.
        for kind in AgentKind.allCases {
            let sessions = manager.restartableSessions(kind)
            guard sessions.count > 1 || sessions.first.map({ $0.id != focused?.id }) == true else { continue }
            rows.append(PaletteCommand(.restartAll, title: "Restart All \(kind.displayName) Sessions") { [weak self] in
                self?.manager.restartAll(kind)
            })
        }
        let current = manager.workspace.selectedLayout?.focusedSessionID
        if !manager.workspace.sessionsDoneUnseen(except: current).isEmpty {
            rows.append(PaletteCommand(.markDoneSeen, title: "Mark All Done as Seen") { [weak self] in
                self?.manager.markDoneSeen()
            })
        }
        return rows
    }

    private func sessionCommands(_ own: [PaletteCommand], focused: Session?) -> [PaletteCommand] {
        var rows = own
        if manager.workspace.sessionsNeedingYou.contains(where: { $0.id != focused?.id }) {
            rows.append(PaletteCommand(.jumpWaiting, title: "Jump to Waiting Session", trailing: "⌘⇧A") {
                TerminalMenuTarget.shared.jumpToWaitingSession(nil)
            })
        }
        if focused != nil, (manager.workspace.selectedLayout?.tree.leaves.count ?? 1) > 1 {
            rows.append(PaletteCommand(.unsplit, title: "Unsplit") { [weak self] in self?.unsplit() })
        }
        return rows
    }

    private func viewCommands() -> [PaletteCommand] {
        var rows = [PaletteCommand(
            .fileTree, title: filesColumn.isShown ? "Hide File Tree" : "Show File Tree", trailing: "⌘\\",
        ) { [weak self] in self?.toggleFiles() }]
        if manager.workspace.selectedLayout != nil {
            rows.append(PaletteCommand(.welcome, title: "Go to Welcome Page") { [weak self] in self?.goToWelcomePage() })
        }
        let groups = manager.workspace.projects
        if groups.contains(where: { !$0.isCollapsed }) {
            rows.append(PaletteCommand(.foldAll, title: "Fold All Groups") { [weak self] in
                self?.manager.setAllCollapsed(true)
            })
        }
        if groups.contains(where: \.isCollapsed) {
            rows.append(PaletteCommand(.unfoldAll, title: "Unfold All Groups") { [weak self] in
                self?.manager.setAllCollapsed(false)
            })
        }
        return rows
    }

    private func lookCommands() -> [PaletteCommand] {
        [PaletteCommand(.randomizeTheme, title: "Randomize Theme") { [weak self] in self?.randomizeTheme() }]
    }

    private func calmCommands() -> [PaletteCommand] {
        [
            PaletteCommand(.restart, title: "Restart \(BuildVariant.appName)") { Restart.request() },
            PaletteCommand(.agents, title: "Agents Settings…") { [weak self] in self?.showSettings(.agents) },
            PaletteCommand(.dumpLogs, title: "Dump Logs") { [weak self] in self?.dumpLogs() },
        ]
    }

    private func terminalCommands() -> [PaletteCommand] {
        let commands = (focusedPane?.config ?? TerminalEngine.shared.config)?.commands ?? []
        return commands.map { command in
            PaletteCommand(id: "terminal-\(command.action)", title: command.title, detail: command.detail) { [weak self] in
                self?.focusedPane?.perform(command.action)
            }
        }
    }

    // MARK: What the rows do

    /// A theme other than the one in force, written to config.toml as Settings does, and named in
    /// a quiet note since no row shows which one it landed on.
    func randomizeTheme() {
        let themes = settingsPage.themes
        themes.refresh()
        var generator = SystemRandomNumberGenerator()
        guard let choice = ThemePickerModel.randomChoice(among: themes.choices, excluding: themes.selectedID, using: &generator) else {
            return
        }
        themes.pick(choice.id)
        showNote("Theme: \(choice.name)")
    }

    /// The agent's newest message as it wrote it (not the card's recap), on the pasteboard.
    func copyLastReply(of id: Session.ID) {
        guard let conversation = manager.workspace.session(id)?.conversation, let path = conversation.transcriptPath,
              let reply = Agents.transcriptReader(for: conversation.kind)?.lastReply(of: URL(filePath: path))
        else {
            showNote("No reply to copy")
            return
        }
        put(reply, note: "Reply copied")
    }

    /// The agent's transcript file in the editor chosen in Settings.
    func openTranscript(of id: Session.ID) {
        guard let path = manager.workspace.session(id)?.conversation?.transcriptPath else { return }
        LinkOpener.openInEditor(path, line: nil, column: nil)
    }

    /// Writes the diagnostics file and opens the folder it is in. The trace takes a moment to read
    /// from the log, so the note says so first.
    func dumpLogs() {
        showNote("Collecting the log…")
        let report = DiagnosticsReport.current(manager: manager)
        Task { [weak self] in
            let trace = await Diagnostics.recentTrace()
            guard let file = Diagnostics.write(report.text(trace: trace)) else {
                self?.showNote("Couldn't write the log")
                return
            }
            Diagnostics.show(file)
        }
    }
}

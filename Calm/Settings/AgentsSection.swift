import AppKit
import CalmAgents
import CalmModel
import SwiftUI
import UserNotifications

/// Settings → Agents (FEATURES.md → F5, New agent sessions; ROADMAP M3.11–M3.12): the agent ⌘N
/// starts, each installed agent with the options it starts with and how it connects (the one
/// setup that needs consent writes files in an agent's own config folder), and the two
/// notification settings. Calm → Agents… opens it. Nothing is written anywhere without a click.
@MainActor
@Observable
final class AgentsSettingsModel {
    struct Row: Identifiable {
        let adapter: any AgentAdapter
        /// How the agent connects now: its own config can settle it (none does today).
        var setup: AgentSetup
        var state: AgentSetupFiles.State?
        var id: AgentKind {
            adapter.kind
        }
    }

    /// An installed agent that can send with ⌘ Return, and where its key settings stand.
    struct SendKeysAgent: Identifiable {
        let kind: AgentKind
        let state: SendKeysFile.State
        /// The file's name, for the line that says Calm can't edit it.
        let file: String
        var id: AgentKind {
            kind
        }
    }

    var rows: [Row] = []
    /// config.toml as last read or written: the options each agent starts with.
    private(set) var settings = CalmSettings()
    /// The agent ⌘N starts; nil with none installed.
    private(set) var newSessionAgent: AgentKind?
    var notifyStates: CalmSettings.NotifyStates
    var sound: Bool
    var sendWithCommandReturn: Bool
    private(set) var sendKeyAgents: [SendKeysAgent] = []
    /// Agents with a session open when the setting changed: they switch when they start again.
    private(set) var switchingOnRestart: [AgentKind] = []
    /// macOS turned Calm's notifications off, so a *needs you* can't reach the user.
    private(set) var notificationsBlocked = false
    var error: String?

    private let home: URL

    init(home: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.home = home
        let settings = SessionManager.shared.settings
        notifyStates = settings.notifyStates
        sound = settings.notificationSound
        sendWithCommandReturn = settings.sendWithCommandReturn
        refresh()
    }

    /// Installed agents (their config folder exists), and whether macOS lets Calm notify.
    func refresh() {
        let settings = SessionManager.shared.settings
        self.settings = settings
        notifyStates = settings.notifyStates
        sound = settings.notificationSound
        rows = Agents.adapters.compactMap { adapter in
            guard let folder = adapter.configFolder, FileManager.default.fileExists(atPath: home.appending(path: folder).path) else {
                return nil
            }
            let setup = adapter.currentSetup(home: home)
            var state: AgentSetupFiles.State?
            if case let .files(files) = setup {
                state = AgentSetupFiles.state(of: files, home: home)
            }
            return Row(adapter: adapter, setup: setup, state: state)
        }
        newSessionAgent = Agents.newSessionAgent(settings: settings, installed: rows.map(\.id))
        sendWithCommandReturn = settings.sendWithCommandReturn
        sendKeyAgents = AgentIntegrations.sendKeys(home: home).map {
            SendKeysAgent(kind: $0.kind, state: SendKeysFile.state(of: $0.keys), file: $0.keys.file.lastPathComponent)
        }
        // An agent whose sessions have all closed has nothing left to start again.
        let open = Set(SessionManager.shared.workspace.sessions.compactMap { $0.agent?.kind })
        switchingOnRestart.removeAll { !open.contains($0) }
        refreshNotificationStatus()
    }

    /// The agents the ⌘N menu offers: those installed, and the one config.toml names if it isn't.
    var newSessionChoices: [AgentKind] {
        let installed = rows.map(\.id)
        guard let chosen = newSessionAgent, !installed.contains(chosen) else { return installed }
        return installed + [chosen]
    }

    /// Claude Code is the default, so choosing it removes the key, as the other sections do.
    func setNewSessionAgent(_ kind: AgentKind) {
        save("agents.new-session", kind == .claudeCode ? nil : kind.configName)
        newSessionAgent = Agents.newSessionAgent(settings: settings, installed: rows.map(\.id))
        // The sidebar's footer and the welcome page name it, and they don't observe the settings.
        TerminalWindowManager.shared.controllers.forEach { $0.applyAppearance() }
    }

    /// A chip: on writes `true`, off removes the key (off is the default).
    func toggle(_ option: LaunchOption, of kind: AgentKind) {
        save(CalmSettings.launchOptionKey(option.id, of: kind), settings.isOn(option.id, of: kind) ? nil : "true")
    }

    private func refreshNotificationStatus() {
        #if DEBUG
            // Self-tests show the notice without asking the real notification center.
            if ProcessInfo.processInfo.environment["CALM_NOTIFICATIONS_BLOCKED"] == "1" {
                notificationsBlocked = true
                return
            }
        #endif
        // Never asked yet (Calm asks at its first notification) isn't blocked.
        guard AttentionCenter.deliversNotifications else { return }
        UNUserNotificationCenter.current().getNotificationSettings { [weak self] settings in
            let denied = settings.authorizationStatus == .denied
            Task { @MainActor in self?.notificationsBlocked = denied }
        }
    }

    func connect(_ row: Row) {
        guard case let .files(files) = row.setup else { return }
        do {
            try AgentSetupFiles.install(files, home: home)
            error = nil
        } catch {
            self.error = "Couldn't connect \(row.adapter.kind.displayName): \(error.localizedDescription)"
        }
        // A connected OpenCode also takes Calm's theme.
        AgentIntegrations.syncThemeFiles()
        refresh()
    }

    func disconnect(_ row: Row) {
        guard case let .files(files) = row.setup else { return }
        do {
            try AgentSetupFiles.remove(files, home: home)
            error = nil
        } catch {
            self.error = "Couldn't disconnect \(row.adapter.kind.displayName): \(error.localizedDescription)"
        }
        // And gives it back.
        AgentIntegrations.syncThemeFiles()
        refresh()
    }

    /// Choosing a default removes the key, as the other sections do (FEATURES.md → F14).
    func setNotifyStates(_ value: CalmSettings.NotifyStates) {
        notifyStates = value
        save("agents.notify", value == .needsYou ? nil : value.rawValue)
    }

    func setSound(_ value: Bool) {
        sound = value
        save("agents.sound", value ? "true" : nil)
    }

    /// Send with ⌘ Return (FEATURES.md → F5): the agents' own key settings, then ⌘↵ itself, which
    /// goes through to programs while it's on and types Return while it's off (`CalmDefaults`).
    func setSendWithCommandReturn(_ value: Bool) {
        sendWithCommandReturn = value
        save("agents.send-with-cmd-return", value ? "true" : nil)
        AgentIntegrations.syncSendKeys(on: value, home: home)
        TerminalEngine.shared.reloadConfig(soft: false)
        switchingOnRestart = AgentIntegrations.sendKeys(home: home).filter { !$0.keys.appliesLive }.map(\.kind)
        refresh()
    }

    /// The line under "Send prompts with": what Return becomes, and words only when something
    /// needs a step (UIUX.md → Settings → Agents).
    var sendKeysLine: String {
        var problems: [String] = []
        if sendWithCommandReturn {
            let own = sendKeyAgents.filter { $0.state == .ownKeys }.map(\.kind.displayName)
            if !own.isEmpty {
                problems.append("\(Self.list(own)) \(own.count == 1 ? "keeps" : "keep") your own Return")
            }
            for agent in sendKeyAgents where agent.state == .unreadable {
                problems.append("Calm can't edit \(agent.kind.displayName)'s \(agent.file)")
            }
        }
        guard problems.isEmpty else { return problems.joined(separator: " · ") }
        let line = "Return starts a new line"
        let waiting = switchingOnRestart.map(\.displayName)
        guard !waiting.isEmpty else { return line }
        return line + " · \(Self.list(waiting)) " + (waiting.count == 1 ? "switches when it starts again" : "switch when they start again")
    }

    /// Which agents it reaches, for the marks' tooltip; and why not Codex, when Codex is here.
    var sendKeysReach: String {
        let names = Self.list(sendKeyAgents.map(\.kind.displayName))
        guard rows.contains(where: { $0.adapter.kind == .codex }) else { return names }
        return "\(names). Not Codex: it can't use ⌘ keys, so it keeps Return."
    }

    private static func list(_ names: [String]) -> String {
        ListFormatter.localizedString(byJoining: names)
    }

    private func save(_ key: String, _ value: String?) {
        do {
            SessionManager.shared.settings = try CalmSettings.save(key, value)
            settings = SessionManager.shared.settings
        } catch {
            self.error = "Couldn't save the setting: \(error.localizedDescription)"
        }
    }
}

struct AgentsSection: View {
    @Bindable var model: AgentsSettingsModel
    let manager: SessionManager
    let style: SidebarStyle

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsTitle(title: "Agents", style: style)
                .padding(.bottom, 24.scaled)
            GroupHeading(title: "Installed", style: style)
            SettingsGroup(style: style) {
                if model.rows.isEmpty {
                    Text("No agents found yet. Calm notices Claude Code, Codex, OpenCode and pi once they're installed.")
                        .calmFont(size: SettingsMetrics.note)
                        .foregroundStyle(style.secondary)
                        .padding(SettingsMetrics.rowInset)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    newSessionRow
                    ForEach(model.rows) { row in
                        RowDivider(style: style)
                        AgentRow(
                            row: row, markState: markState(of: row.id), settings: model.settings, style: style,
                            onToggle: { model.toggle($0, of: row.id) },
                            onConnect: { model.connect(row) }, onDisconnect: { model.disconnect(row) },
                        )
                    }
                }
            }
            if !model.sendKeyAgents.isEmpty {
                GroupHeading(title: "Keys", style: style)
                    .padding(.top, 34.scaled)
                SettingsGroup(style: style) {
                    SendKeysRow(model: model, style: style)
                }
            }
            GroupHeading(title: "Notifications", style: style)
                .padding(.top, 34.scaled)
            SettingsGroup(style: style) {
                if model.notificationsBlocked {
                    blockedRow
                    RowDivider(style: style)
                }
                // Closures, not method references: passing `model.setSound` crashed the Swift 6.3.3
                // compiler (IRGen, isolated reabstraction thunk).
                SettingsRow(title: "Notify me when", symbol: "bell", style: style) {
                    SettingsMenu(
                        title: "Notify me when",
                        options: [(.needsYou, "An agent needs me"), (.all, "It needs me, finishes or fails")],
                        selection: model.notifyStates, style: style,
                    ) { model.setNotifyStates($0) }
                }
                RowDivider(style: style)
                SettingsRow(title: "Play a sound", symbol: "speaker.wave.2", style: style) {
                    Toggle("Play a sound", isOn: Binding(get: { model.sound }, set: { model.setSound($0) }))
                        .toggleStyle(CalmSwitchStyle(style: style))
                        .labelsHidden()
                }
            }
            if let error = model.error {
                Text(error)
                    .calmFont(size: SettingsMetrics.note)
                    .foregroundStyle(style.failure)
                    .padding(.top, 12.scaled)
            }
        }
    }

    /// ⌘N's agent, which ⌘⇧N starts too. The menu offers the agents installed.
    private var newSessionRow: some View {
        SettingsRow(title: "⌘N starts", note: "⌘⇧N too, in a scratch folder", symbol: "terminal", style: style) {
            if let chosen = model.newSessionAgent {
                SettingsMenu(
                    title: "⌘N starts",
                    options: model.newSessionChoices.map { (value: $0, label: $0.displayName) },
                    selection: chosen, style: style,
                ) { model.setNewSessionAgent($0) }
            }
        }
    }

    /// The agent's mark moves while one of its sessions works, as on its cards in the sidebar.
    private func markState(of kind: AgentKind) -> SessionState? {
        let sessions = manager.workspace.sessions.filter { $0.agent?.kind == kind }
        if sessions.contains(where: { $0.state == .working }) {
            return .working
        }
        return sessions.contains { $0.state == .needsYou } ? .needsYou : nil
    }

    private var blockedRow: some View {
        HStack(spacing: 16.scaled) {
            WarningMark(style: style, size: 18)
                .frame(width: 34.scaled)
            Text("macOS is blocking Calm's notifications")
                .calmFont(size: SettingsMetrics.label)
                .foregroundStyle(style.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button("Open System Settings") { SettingsActions.openNotificationSettings() }
                .buttonStyle(SettingsButtonStyle(style: style))
        }
        .padding(.horizontal, SettingsMetrics.rowInset)
        .frame(minHeight: SettingsMetrics.rowHeight)
    }
}

/// One installed agent on one row (UIUX.md → Settings → Agents): its mark (moving while one of
/// its sessions works), its name, and under it a chip for each option it starts with on ⌘N. The
/// right side stays empty while all is well (connected is the normal state) and holds only what
/// is off: Connect, Left alone, Set Up…, and ••• for Disconnect.
private struct AgentRow: View {
    let row: AgentsSettingsModel.Row
    let markState: SessionState?
    let settings: CalmSettings
    let style: SidebarStyle
    let onToggle: (LaunchOption) -> Void
    let onConnect: () -> Void
    let onDisconnect: () -> Void
    @State private var explaining = false

    var body: some View {
        HStack(spacing: 16.scaled) {
            AgentLogo(agent: row.id, state: markState, size: 34, style: style)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 8.scaled) {
                Text(row.id.displayName)
                    .calmFont(size: SettingsMetrics.label)
                    .foregroundStyle(style.primary)
                if let command = settings.command(of: row.id) {
                    // Set with `calm config` only: Settings shows it, in place of the chips it
                    // overrides, and has no field for it.
                    Text(command)
                        .calmFont(size: 13, design: .monospaced)
                        .foregroundStyle(style.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help("⌘N types this, as written (calm config set \(CalmSettings.commandKey(of: row.id))). "
                            + "calm config unset \(CalmSettings.commandKey(of: row.id)) brings the options back.")
                        .accessibilityLabel("\(row.id.displayName) starts with \(command)")
                } else if !row.adapter.launchOptions.isEmpty {
                    HStack(spacing: 8.scaled) {
                        ForEach(row.adapter.launchOptions) { option in
                            LaunchChip(option: option, isOn: settings.isOn(option.id, of: row.id), style: style) {
                                onToggle(option)
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            standing
        }
        .padding(.horizontal, SettingsMetrics.rowInset)
        .padding(.vertical, 14.scaled)
        .frame(minHeight: SettingsMetrics.rowHeight)
        .accessibilityElement(children: .contain)
    }

    /// The one action the agent needs, or why Calm left it alone; nothing when it is connected.
    @ViewBuilder
    private var standing: some View {
        switch (row.setup, row.state) {
        case let (.files(files), .notInstalled?):
            Button("Connect", action: onConnect)
                .buttonStyle(SettingsButtonStyle(style: style))
                .help("Adds \(Self.paths(files)), so it can tell Calm when it's working or waiting.")
        case (_, .connected?):
            HStack(spacing: 4.scaled) {
                Menu {
                    Button("Disconnect", action: onDisconnect)
                } label: {
                    Image(systemName: "ellipsis")
                        .calmFont(size: 13, weight: .semibold)
                        .foregroundStyle(style.secondary)
                        .frame(width: 28.scaled, height: 28.scaled)
                        .contentShape(Rectangle())
                }
                .menuStyle(.button)
                .buttonStyle(.plain)
                .menuIndicator(.hidden)
                .fixedSize()
                .accessibilityLabel("More for \(row.adapter.kind.displayName)")
            }
        case let (_, .conflict(path)?):
            StatusLabel(text: "Left alone", symbol: "minus.circle", style: style)
                .help("~/\(path) already exists and wasn't written by Calm, so Calm leaves it alone.")
        case let (.hint(text), _):
            // The one step is the user's to take in the agent's own settings: the button says
            // how, in a popover, instead of a paragraph on the page.
            Button("Set Up…") { explaining.toggle() }
                .buttonStyle(SettingsButtonStyle(style: style))
                .popover(isPresented: $explaining, arrowEdge: .bottom) {
                    Text(text)
                        .calmFont(size: SettingsMetrics.note)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(width: 280.scaled, alignment: .leading)
                        .padding(16.scaled)
                }
                .accessibilityHint(text)
        default:
            EmptyView()
        }
    }

    private static func paths(_ files: [String: String]) -> String {
        files.keys.sorted().map { "~/\($0)" }.joined(separator: ", ")
    }
}

/// One option an agent starts with, as a chip that turns on and off: on is a soft fill of the
/// accent with a check, off a quiet outline (UIUX.md → Settings → Agents). Pointing at it names
/// the flag it adds.
private struct LaunchChip: View {
    let option: LaunchOption
    let isOn: Bool
    let style: SidebarStyle
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5.scaled) {
                if isOn {
                    Image(systemName: "checkmark")
                        .calmFont(size: 10, weight: .bold)
                        .foregroundStyle(style.accent)
                }
                Text(option.label)
                    .calmFont(size: 13.5)
            }
            .foregroundStyle(isOn ? style.primary : style.secondary)
            .padding(.horizontal, 11.scaled)
            .frame(height: 26.scaled)
            .background(RoundedRectangle(cornerRadius: 7.scaled, style: .continuous).fill(isOn ? style.accent.opacity(0.16) : .clear))
            .overlay(
                RoundedRectangle(cornerRadius: 7.scaled, style: .continuous)
                    .strokeBorder(isOn ? .clear : hovering ? style.secondary.opacity(0.4) : style.hairline),
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.15), value: isOn)
        .help(option.flag + (option.onlyInGitRepository ? ", in a git repository" : ""))
        .accessibilityLabel(option.label)
        .accessibilityValue(isOn ? "On" : "Off")
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

/// Send with ⌘ Return (UIUX.md → Settings → Agents): one switch. ⌘ ↩ before it, as two soft keys,
/// say what it turns on (solid while on, an outline while off); the line under the title says
/// what Return becomes, after the marks of the agents it reaches. Picked by the author from local
/// mockups (2026-10-06): choices built from keys (pairs, boxes, chips) read as a legend, not a
/// control, so the keys are the switch's label and the switch is the control.
private struct SendKeysRow: View {
    @Bindable var model: AgentsSettingsModel
    let style: SidebarStyle

    var body: some View {
        HStack(spacing: 16.scaled) {
            SettingsIcon(symbol: "return", style: style)
            VStack(alignment: .leading, spacing: 4.scaled) {
                Text("Send prompts with")
                    .calmFont(size: SettingsMetrics.label)
                    .foregroundStyle(style.primary)
                HStack(spacing: 8.scaled) {
                    marks
                    Text(model.sendKeysLine)
                        .calmFont(size: SettingsMetrics.note)
                        .foregroundStyle(style.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .help(model.sendKeysLine)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            SoftKeys(symbols: ["command", "return"], lit: model.sendWithCommandReturn, style: style)
            Toggle(
                "Send prompts with Command-Return",
                isOn: Binding(get: { model.sendWithCommandReturn }, set: { model.setSendWithCommandReturn($0) }),
            )
            .toggleStyle(CalmSwitchStyle(style: style))
            .labelsHidden()
        }
        .padding(.horizontal, SettingsMetrics.rowInset)
        .padding(.vertical, 14.scaled)
        .frame(minHeight: SettingsMetrics.rowHeight)
        .accessibilityElement(children: .contain)
    }

    /// The agents it reaches, small and overlapping: one whose own keys win is grayed, and one whose
    /// file Calm can't edit carries the warning mark.
    private var marks: some View {
        HStack(spacing: -4.scaled) {
            ForEach(model.sendKeyAgents) { agent in
                let left = model.sendWithCommandReturn && agent.state == .ownKeys
                AgentLogo(agent: agent.kind, size: 18, style: style)
                    .saturation(left ? 0 : 1)
                    .opacity(left ? 0.35 : 1)
                    .background(RoundedRectangle(cornerRadius: 7.scaled, style: .continuous).fill(style.groupFill).padding(-2))
                    .overlay(alignment: .bottomTrailing) {
                        if model.sendWithCommandReturn, agent.state == .unreadable {
                            WarningMark(style: style, size: 9).offset(x: 4.scaled, y: 4.scaled)
                        }
                    }
            }
        }
        .help(model.sendKeysReach)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(model.sendKeysReach)
    }
}

/// Keys drawn as soft keys: a face a step off the card, a hairline edge and a one-point shadow
/// under it while `lit`, only the edge otherwise. SF Symbols, so ⌘ and ↩ match in weight.
struct SoftKeys: View {
    let symbols: [String]
    let lit: Bool
    let style: SidebarStyle

    var body: some View {
        HStack(spacing: 5.scaled) {
            ForEach(symbols, id: \.self) { symbol in
                Image(systemName: symbol)
                    .calmFont(size: 12, weight: .medium)
                    .foregroundStyle(lit ? style.primary : style.tertiary)
                    .frame(minWidth: 26.scaled, minHeight: 26.scaled)
                    .background(
                        RoundedRectangle(cornerRadius: 6.scaled, style: .continuous)
                            .fill(lit ? (style.isDark ? style.primary.opacity(0.09) : Color.white) : Color.clear)
                            .shadow(color: .black.opacity(lit ? (style.isDark ? 0.5 : 0.11) : 0), radius: 0, y: 1),
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 6.scaled, style: .continuous)
                            .strokeBorder(style.isDark ? Color.white.opacity(0.06) : Color.black.opacity(0.09)),
                    )
            }
        }
        .animation(.easeOut(duration: 0.15), value: lit)
        .accessibilityHidden(true)
    }
}

/// Where an agent stands, as quiet text with its mark.
private struct StatusLabel: View {
    let text: String
    let symbol: String
    let style: SidebarStyle

    var body: some View {
        Label {
            Text(text)
        } icon: {
            Image(systemName: symbol).calmFont(size: 12, weight: .semibold)
        }
        .labelStyle(.titleAndIcon)
        .calmFont(size: SettingsMetrics.control)
        .foregroundStyle(style.secondary)
        .frame(height: 28.scaled)
        .fixedSize()
    }
}

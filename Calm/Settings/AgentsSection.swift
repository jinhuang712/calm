import AppKit
import CalmAgents
import CalmModel
import SwiftUI
import UserNotifications

/// Settings → Agents (FEATURES.md → F5; ROADMAP M3.11–M3.12): how each installed agent connects,
/// the one setup that needs consent (files in an agent's own config folder), and the two
/// notification settings. Calm → Agents… opens it. Nothing is written anywhere without a click.
@MainActor
@Observable
final class AgentsSettingsModel {
    struct Row: Identifiable {
        let adapter: any AgentAdapter
        var state: AgentSetupFiles.State?
        var id: AgentKind {
            adapter.kind
        }
    }

    var rows: [Row] = []
    /// Agents Calm knows that aren't installed here.
    var missing: [AgentKind] = []
    var notifyStates: CalmSettings.NotifyStates
    var sound: Bool
    /// macOS turned Calm's notifications off, so a *needs you* can't reach the user.
    private(set) var notificationsBlocked = false
    var error: String?

    private let home: URL

    init(home: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.home = home
        let settings = SessionManager.shared.settings
        notifyStates = settings.notifyStates
        sound = settings.notificationSound
        refresh()
    }

    /// Installed agents (their config folder exists), and whether macOS lets Calm notify.
    func refresh() {
        let settings = SessionManager.shared.settings
        notifyStates = settings.notifyStates
        sound = settings.notificationSound
        rows = Agents.adapters.compactMap { adapter in
            guard let folder = adapter.configFolder, FileManager.default.fileExists(atPath: home.appending(path: folder).path) else {
                return nil
            }
            var state: AgentSetupFiles.State?
            if case let .files(files) = adapter.setup {
                state = AgentSetupFiles.state(of: files, home: home)
            }
            return Row(adapter: adapter, state: state)
        }
        missing = AgentKind.allCases.filter { kind in !rows.contains { $0.id == kind } }
        refreshNotificationStatus()
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
        guard case let .files(files) = row.adapter.setup else { return }
        do {
            try AgentSetupFiles.install(files, home: home)
            error = nil
        } catch {
            self.error = "Couldn't connect \(row.adapter.kind.displayName): \(error.localizedDescription)"
        }
        refresh()
    }

    func disconnect(_ row: Row) {
        guard case let .files(files) = row.adapter.setup else { return }
        do {
            try AgentSetupFiles.remove(files, home: home)
            error = nil
        } catch {
            self.error = "Couldn't disconnect \(row.adapter.kind.displayName): \(error.localizedDescription)"
        }
        refresh()
    }

    func setNotifyStates(_ value: CalmSettings.NotifyStates) {
        notifyStates = value
        save("agents.notify", value.rawValue)
    }

    func setSound(_ value: Bool) {
        sound = value
        save("agents.sound", value ? "true" : "false")
    }

    private func save(_ key: String, _ value: String) {
        do {
            SessionManager.shared.settings = try CalmSettings.save(key, value)
        } catch {
            self.error = "Couldn't save the setting: \(error.localizedDescription)"
        }
    }
}

struct AgentsSection: View {
    @Bindable var model: AgentsSettingsModel
    let style: SidebarStyle

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsTitle(
                title: "Agents",
                note: "Calm shows what each agent is doing, and tells you at the next pause when one needs you.",
                style: style,
            )
            .padding(.bottom, 22)
            GroupHeading(title: "Installed", style: style)
            SettingsGroup(style: style) {
                if model.rows.isEmpty {
                    Text("No agents found yet. Calm notices Claude Code, Codex, OpenCode, pi and omp once they're installed.")
                        .font(.system(size: 13))
                        .foregroundStyle(style.secondary)
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    ForEach(Array(model.rows.enumerated()), id: \.element.id) { index, row in
                        if index > 0 {
                            RowDivider(style: style)
                        }
                        agentRow(row)
                    }
                    if !model.missing.isEmpty {
                        RowDivider(style: style)
                        Text(missingNote)
                            .font(.system(size: 12))
                            .foregroundStyle(style.tertiary)
                            .padding(.leading, 60)
                            .padding(.trailing, 16)
                            .padding(.vertical, 11)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            GroupHeading(title: "Notifications", style: style)
                .padding(.top, 24)
            SettingsGroup(style: style) {
                if model.notificationsBlocked {
                    blockedRow
                    RowDivider(style: style)
                }
                // Closures, not method references: passing `model.setSound` crashed the Swift 6.3.3
                // compiler (IRGen, isolated reabstraction thunk).
                SettingsRow(title: "Notify me when", style: style) {
                    SettingsMenu(
                        title: "Notify me when",
                        options: [(.needsYou, "An agent needs me"), (.all, "It needs me, finishes or fails")],
                        selection: model.notifyStates, style: style,
                    ) { model.setNotifyStates($0) }
                }
                RowDivider(style: style)
                SettingsRow(title: "Play a sound", style: style) {
                    Toggle("Play a sound", isOn: Binding(get: { model.sound }, set: { model.setSound($0) }))
                        .toggleStyle(CalmSwitchStyle(style: style))
                        .labelsHidden()
                }
            }
            Text("Calm waits for a pause in your typing, and never notifies about the session you're looking at.")
                .font(.system(size: 12))
                .foregroundStyle(style.secondary)
                .padding(.top, 10)
                .padding(.horizontal, 2)
            if let error = model.error {
                Text(error)
                    .font(.system(size: 11))
                    .foregroundStyle(style.failure)
                    .padding(.top, 10)
            }
        }
    }

    private var missingNote: String {
        let names = model.missing.map(\.displayName).formatted(.list(type: .and))
        return model.missing.count == 1
            ? "\(names) isn't installed. Calm picks it up once it is."
            : "\(names) aren't installed. Calm picks them up once they are."
    }

    private var blockedRow: some View {
        HStack(spacing: 12) {
            WarningMark(style: style, size: 15)
            VStack(alignment: .leading, spacing: 2) {
                Text("macOS is blocking Calm's notifications")
                    .font(.system(size: 14))
                    .foregroundStyle(style.primary)
                Text("Until they're allowed, Calm can't tell you when an agent needs you.")
                    .font(.system(size: 12))
                    .foregroundStyle(style.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button("Open System Settings") { SettingsActions.openNotificationSettings() }
                .buttonStyle(SettingsButtonStyle(style: style))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
    }

    private func agentRow(_ row: AgentsSettingsModel.Row) -> some View {
        HStack(spacing: 12) {
            AgentLogo(agent: row.adapter.kind, size: 32, style: style)
            VStack(alignment: .leading, spacing: 3) {
                Text(row.adapter.kind.displayName)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(style.primary)
                Text(description(row))
                    .font(.system(size: 12))
                    .lineSpacing(1)
                    .foregroundStyle(style.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            trailing(row)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
        .accessibilityElement(children: .contain)
    }

    private func description(_ row: AgentsSettingsModel.Row) -> String {
        switch row.adapter.setup {
        case .automatic:
            return "Connected inside Calm. Nothing changes in its own settings."
        case .notifications:
            return "Works through the notifications it already sends."
        case let .hint(text):
            return text
        case let .files(files):
            let paths = files.keys.sorted().map { "~/\($0)" }.joined(separator: ", ")
            switch row.state {
            case .connected: return "Connected through \(paths)."
            case let .conflict(path): return "~/\(path) already exists and wasn't written by Calm, so Calm leaves it alone."
            default: return "Connect adds \(paths), so it can tell Calm when it's working, done or waiting."
            }
        }
    }

    /// Every row ends the same way: where it stands, or the one thing it needs.
    @ViewBuilder
    private func trailing(_ row: AgentsSettingsModel.Row) -> some View {
        switch (row.adapter.setup, row.state) {
        case (_, .notInstalled?):
            Button("Connect") { model.connect(row) }
                .buttonStyle(SettingsButtonStyle(style: style))
        case (_, .connected?):
            HStack(spacing: 12) {
                status("Connected", symbol: "checkmark")
                Button("Disconnect") { model.disconnect(row) }
                    .buttonStyle(.plain)
                    .font(.system(size: 13))
                    .foregroundStyle(style.tertiary)
            }
        case (_, .conflict?):
            status("Left alone", symbol: "minus.circle")
        case (.hint, _):
            status("One step left", symbol: "circle.lefthalf.filled")
        default:
            status("Connected", symbol: "checkmark")
        }
    }

    private func status(_ text: String, symbol: String) -> some View {
        Label {
            Text(text)
        } icon: {
            Image(systemName: symbol).font(.system(size: 10, weight: .semibold))
        }
        .labelStyle(.titleAndIcon)
        .font(.system(size: 13))
        .foregroundStyle(style.secondary)
        .fixedSize()
    }
}

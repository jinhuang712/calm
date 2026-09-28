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
            SettingsTitle(title: "Agents", style: style)
                .padding(.bottom, 24)
            GroupHeading(title: "Installed", style: style)
            SettingsGroup(style: style) {
                if model.rows.isEmpty {
                    Text("No agents found yet. Calm notices Claude Code, Codex, OpenCode, pi and omp once they're installed.")
                        .font(.system(size: SettingsMetrics.note))
                        .foregroundStyle(style.secondary)
                        .padding(SettingsMetrics.rowInset)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    ForEach(Array(model.rows.enumerated()), id: \.element.id) { index, row in
                        if index > 0 {
                            RowDivider(style: style)
                        }
                        agentRow(row)
                    }
                }
            }
            GroupHeading(title: "Notifications", style: style)
                .padding(.top, 30)
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
            if let error = model.error {
                Text(error)
                    .font(.system(size: SettingsMetrics.note))
                    .foregroundStyle(style.failure)
                    .padding(.top, 12)
            }
        }
    }

    private var blockedRow: some View {
        HStack(spacing: 14) {
            WarningMark(style: style, size: 18)
            Text("macOS is blocking Calm's notifications")
                .font(.system(size: SettingsMetrics.label))
                .foregroundStyle(style.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button("Open System Settings") { SettingsActions.openNotificationSettings() }
                .buttonStyle(SettingsButtonStyle(style: style))
        }
        .padding(.horizontal, SettingsMetrics.rowInset)
        .frame(minHeight: SettingsMetrics.rowHeight)
    }

    private func agentRow(_ row: AgentsSettingsModel.Row) -> some View {
        HStack(spacing: 14) {
            AgentLogo(agent: row.adapter.kind, size: 38, style: style)
            VStack(alignment: .leading, spacing: 4) {
                Text(row.adapter.kind.displayName)
                    .font(.system(size: SettingsMetrics.label, weight: .medium))
                    .foregroundStyle(style.primary)
                if let detail = detail(row) {
                    Text(detail)
                        .font(.system(size: SettingsMetrics.note))
                        .lineSpacing(1)
                        .foregroundStyle(style.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            trailing(row)
        }
        .padding(.horizontal, SettingsMetrics.rowInset)
        .padding(.vertical, 12)
        .frame(minHeight: SettingsMetrics.rowHeight)
        .accessibilityElement(children: .contain)
    }

    /// A line under the name only when there's something to do or know; a connected agent is
    /// just its name and "Connected".
    private func detail(_ row: AgentsSettingsModel.Row) -> String? {
        switch row.adapter.setup {
        case .automatic, .notifications:
            return nil
        case let .hint(text):
            return text
        case let .files(files):
            let paths = files.keys.sorted().map { "~/\($0)" }.joined(separator: ", ")
            switch row.state {
            case .connected: return nil
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
                    .font(.system(size: SettingsMetrics.control))
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
            Image(systemName: symbol).font(.system(size: 12, weight: .semibold))
        }
        .labelStyle(.titleAndIcon)
        .font(.system(size: SettingsMetrics.control))
        .foregroundStyle(style.secondary)
        .fixedSize()
    }
}

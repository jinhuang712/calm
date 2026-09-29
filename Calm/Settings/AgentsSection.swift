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
        /// How the agent connects now: its own config can settle it (OpenCode's notifications).
        var setup: AgentSetup
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
            let setup = adapter.currentSetup(home: home)
            var state: AgentSetupFiles.State?
            if case let .files(files) = setup {
                state = AgentSetupFiles.state(of: files, home: home)
            }
            return Row(adapter: adapter, setup: setup, state: state)
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
        guard case let .files(files) = row.setup else { return }
        do {
            try AgentSetupFiles.install(files, home: home)
            error = nil
        } catch {
            self.error = "Couldn't connect \(row.adapter.kind.displayName): \(error.localizedDescription)"
        }
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
    let manager: SessionManager
    let style: SidebarStyle

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsTitle(title: "Agents", style: style)
                .padding(.bottom, 24.scaled)
            GroupHeading(title: "Installed", style: style)
            if model.rows.isEmpty {
                SettingsGroup(style: style) {
                    Text("No agents found yet. Calm notices Claude Code, Codex, OpenCode, pi and omp once they're installed.")
                        .calmFont(size: SettingsMetrics.note)
                        .foregroundStyle(style.secondary)
                        .padding(SettingsMetrics.rowInset)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                LazyVGrid(
                    columns: [GridItem(.flexible(), spacing: 16.scaled), GridItem(.flexible(), spacing: 16.scaled)],
                    spacing: 16.scaled,
                ) {
                    ForEach(model.rows) { row in
                        AgentCard(
                            row: row, activity: activity(of: row.adapter.kind), style: style,
                            onConnect: { model.connect(row) }, onDisconnect: { model.disconnect(row) },
                        )
                    }
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

    /// What the agent is doing in Calm right now, from the open sessions.
    private func activity(of kind: AgentKind) -> AgentCard.Activity {
        let sessions = manager.workspace.sessions.filter { $0.agent?.kind == kind }
        return AgentCard.Activity(
            sessions: sessions.count,
            working: sessions.count { $0.state == .working },
            needsYou: sessions.count { $0.state == .needsYou },
        )
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

/// One installed agent: its mark (moving while one of its sessions works), where it stands, and
/// what it's doing in Calm now. Anything longer (OpenCode's step, what Connect adds) waits
/// behind its pill or button.
private struct AgentCard: View {
    struct Activity {
        var sessions: Int
        var working: Int
        var needsYou: Int

        var markState: SessionState? {
            working > 0 ? .working : needsYou > 0 ? .needsYou : nil
        }

        var summary: String {
            guard sessions > 0 else { return "Not running" }
            var parts = [sessions == 1 ? "1 session" : "\(sessions) sessions"]
            if needsYou > 0 {
                parts.append("\(needsYou) needs you")
            }
            if working > 0 {
                parts.append("\(working) working")
            }
            return parts.joined(separator: " · ")
        }
    }

    let row: AgentsSettingsModel.Row
    let activity: Activity
    let style: SidebarStyle
    let onConnect: () -> Void
    let onDisconnect: () -> Void
    @State private var explaining = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                AgentLogo(agent: row.adapter.kind, state: activity.markState, size: 48, style: style)
                Spacer(minLength: 8.scaled)
                standing
            }
            Spacer(minLength: 18.scaled)
            Text(row.adapter.kind.displayName)
                .calmFont(size: 19, weight: .medium)
                .foregroundStyle(style.primary)
            Text(activity.summary)
                .calmFont(size: SettingsMetrics.note)
                .foregroundStyle(activity.needsYou > 0 ? style.attention : style.secondary)
                .padding(.top, 4.scaled)
        }
        .padding(20.scaled)
        .frame(maxWidth: .infinity, minHeight: 172.scaled, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 16.scaled, style: .continuous).fill(style.groupFill))
        .overlay(RoundedRectangle(cornerRadius: 16.scaled, style: .continuous).strokeBorder(style.hairline))
        .accessibilityElement(children: .contain)
    }

    /// Where the agent stands, in quiet text, or the one action it needs.
    @ViewBuilder
    private var standing: some View {
        switch (row.setup, row.state) {
        case let (.files(files), .notInstalled?):
            Button("Connect", action: onConnect)
                .buttonStyle(SettingsButtonStyle(style: style))
                .help("Adds \(Self.paths(files)), so it can tell Calm when it's working or waiting.")
        case (_, .connected?):
            HStack(spacing: 4.scaled) {
                StatusLabel(text: "Connected", symbol: "checkmark", style: style)
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
            StatusLabel(text: "Connected", symbol: "checkmark", style: style)
        }
    }

    private static func paths(_ files: [String: String]) -> String {
        files.keys.sorted().map { "~/\($0)" }.joined(separator: ", ")
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

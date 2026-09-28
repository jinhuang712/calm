import AppKit
import CalmAgents
import CalmModel
import SwiftUI

/// The Agents panel (FEATURES.md → F5; ROADMAP M3.11–M3.12): shown once at first launch and
/// from Calm → Agents…. It says how each installed agent connects, offers the one setup that
/// needs consent (files in an agent's own config folder), and holds the two notification
/// settings. Nothing is written anywhere without a click here.
@MainActor
@Observable
final class AgentsPanelModel {
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
    var error: String?

    private let home: URL

    init(home: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.home = home
        let settings = SessionManager.shared.settings
        notifyStates = settings.notifyStates
        sound = settings.notificationSound
        refresh()
    }

    /// Installed agents: their config folder exists.
    func refresh() {
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

struct AgentsPanelView: View {
    @Bindable var model: AgentsPanelModel
    let style: SidebarStyle
    let onDone: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.18)
                .ignoresSafeArea()
                .onTapGesture(perform: onDone)
            VStack(alignment: .leading, spacing: 16) {
                Text("Agents")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(style.primary)
                AgentsContent(model: model, style: style)
                HStack {
                    Spacer()
                    Button("Done", action: onDone)
                        .keyboardShortcut(.defaultAction)
                }
            }
            .padding(20)
            .frame(width: 460)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(style.background))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(style.tertiary.opacity(0.25)))
            .shadow(color: .black.opacity(style.isDark ? 0.35 : 0.12), radius: 24, y: 8)
        }
        .onExitCommand(perform: onDone) // esc
        .environment(\.colorScheme, style.isDark ? .dark : .light)
    }
}

/// How each installed agent connects, and the notification settings: in the first-launch panel
/// (in the theme's colors) and in Settings → Agents (`style` nil: the system's colors).
struct AgentsContent: View {
    @Bindable var model: AgentsPanelModel
    var style: SidebarStyle?

    private var primary: Color {
        style?.primary ?? .primary
    }

    private var secondary: Color {
        style?.secondary ?? .secondary
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Calm shows what each agent is doing, and tells you at the next pause when one needs you.")
                .font(.system(size: 12))
                .foregroundStyle(secondary)
                .fixedSize(horizontal: false, vertical: true)
            if model.rows.isEmpty {
                Text("No agents found yet. Calm notices Claude Code, Codex, OpenCode, pi and omp when they run.")
                    .font(.system(size: 12))
                    .foregroundStyle(secondary)
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(model.rows) { row in
                        agentRow(row)
                    }
                }
            }
            Divider().opacity(0.5)
            VStack(alignment: .leading, spacing: 10) {
                // Closures, not method references: passing `model.setSound` crashed the Swift 6.3.3
                // compiler (IRGen, isolated reabstraction thunk).
                Picker("Notify me when", selection: Binding(get: { model.notifyStates }, set: { model.setNotifyStates($0) })) {
                    Text("An agent needs me").tag(CalmSettings.NotifyStates.needsYou)
                    Text("It needs me, finishes or fails").tag(CalmSettings.NotifyStates.all)
                }
                .pickerStyle(.radioGroup)
                Toggle("Play a sound", isOn: Binding(get: { model.sound }, set: { model.setSound($0) }))
            }
            .font(.system(size: 12))
            if let error = model.error {
                Text(error)
                    .font(.system(size: 11))
                    .foregroundStyle(style?.failure ?? .red)
            }
        }
    }

    private func agentRow(_ row: AgentsPanelModel.Row) -> some View {
        HStack(alignment: .top, spacing: 10) {
            AgentLogo(agent: row.adapter.kind, size: 20, style: style)
            VStack(alignment: .leading, spacing: 2) {
                Text(row.adapter.kind.displayName)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(primary)
                Text(description(row))
                    .font(.system(size: 12))
                    .foregroundStyle(secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            action(row)
        }
    }

    private func description(_ row: AgentsPanelModel.Row) -> String {
        switch row.adapter.setup {
        case .automatic:
            return "Connected inside Calm. Nothing is changed in its own settings."
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

    @ViewBuilder
    private func action(_ row: AgentsPanelModel.Row) -> some View {
        switch row.state {
        case .notInstalled:
            Button("Connect") { model.connect(row) }
        case .connected:
            Button("Disconnect") { model.disconnect(row) }
        default:
            if case .automatic = row.adapter.setup {
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(style?.tertiary ?? Color.secondary)
            }
        }
    }
}

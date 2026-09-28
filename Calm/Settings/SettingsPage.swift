import AppKit
import CalmModel
import SwiftUI

/// The settings page (FEATURES.md → F14, UIUX.md → Settings): ⌘, turns the whole window into
/// Settings, as the welcome page fills it. A list of sections takes the sidebar's place, a
/// session that needs you still shows at its foot, and esc (or ⌘, again) goes back to the session
/// exactly as it was; it keeps running underneath. Everything is saved to config.toml at once.
@MainActor
final class SettingsPage {
    enum Section: String, CaseIterable, Identifiable {
        case appearance, agents, general, shortcuts

        var id: String {
            rawValue
        }

        var title: String {
            rawValue.capitalized
        }

        var symbol: String {
            switch self {
            case .appearance: "circle.lefthalf.filled"
            case .agents: "sparkle"
            case .general: "slider.horizontal.3"
            case .shortcuts: "keyboard"
            }
        }
    }

    /// Which section shows; Settings reopens where it was left.
    @MainActor
    @Observable
    final class Navigation {
        var section = Section.appearance
    }

    let themes = ThemePickerModel()
    let windowOptions = WindowOptionsModel()
    let general = GeneralSettingsModel()
    let agents = AgentsSettingsModel()
    let navigation = Navigation()

    private weak var container: NSView?
    private var host: NSHostingView<SettingsView>?
    private var keyMonitor: Any?

    init(container: NSView) {
        self.container = container
    }

    var isShowing: Bool {
        host != nil
    }

    func show(_ section: Section?, style: SidebarStyle, background: NSColor, actions: SettingsView.Actions) {
        if let section {
            navigation.section = section
        }
        guard !isShowing else {
            restyle(style: style, background: background, actions: actions)
            // Opening the window (Calm → Agents…) gave the keyboard back to the session.
            container?.window?.makeFirstResponder(host)
            return
        }
        refresh()
        guard let container else { return }
        let host = NSHostingView(rootView: view(style: style, background: background, actions: actions))
        host.frame = container.bounds
        host.autoresizingMask = [.width, .height]
        container.addSubview(host, positioned: .above, relativeTo: nil)
        self.host = host
        // Lays out the scroll view's content now: a window that isn't drawing yet (a headless
        // self-test) would otherwise show it blank.
        host.layoutSubtreeIfNeeded()
        Motion.fadeIn(host, duration: 0.2)
        // Typing no longer reaches the session underneath.
        container.window?.makeFirstResponder(host)
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self, weak container] event in
            // esc, unless something opened over the page (search) takes it first.
            guard let self, let host = self.host, event.keyCode == 53, event.window === host.window,
                  container?.subviews.last === host
            else { return event }
            actions.close()
            return nil
        }
    }

    /// New colors (the theme or appearance changed) without resetting the page.
    func restyle(style: SidebarStyle, background: NSColor, actions: SettingsView.Actions) {
        host?.rootView = view(style: style, background: background, actions: actions)
    }

    func refresh() {
        themes.refresh()
        windowOptions.refresh()
        general.refresh()
        agents.refresh()
    }

    func hide() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
        }
        keyMonitor = nil
        guard let host else { return }
        self.host = nil
        Motion.fadeOutAndRemove(host, duration: 0.14)
    }

    private func view(style: SidebarStyle, background: NSColor, actions: SettingsView.Actions) -> SettingsView {
        SettingsView(page: self, manager: SessionManager.shared, style: style, background: Color(nsColor: background), actions: actions)
    }
}

struct SettingsView: View {
    struct Actions {
        let close: () -> Void
        let goToSession: (Session.ID) -> Void
        let reload: () -> Void
    }

    let page: SettingsPage
    let manager: SessionManager
    let style: SidebarStyle
    /// The terminal's background: the page stands where the session would.
    let background: Color
    let actions: Actions

    /// Room for the list and a full-width page; narrower windows show the list as icons.
    private static let roomyWidth: CGFloat = 900

    var body: some View {
        GeometryReader { proxy in
            let compact = proxy.size.width < Self.roomyWidth
            HStack(spacing: 0) {
                SettingsList(
                    navigation: page.navigation, compact: compact, style: style,
                    warnings: warnings, waiting: manager.workspace.sessionsNeedingYou.first,
                    hasSessions: !manager.workspace.sessions.isEmpty, actions: actions,
                )
                .frame(width: compact ? 64 : 232)
                .background(style.background)
                Rectangle()
                    .fill(style.hairline)
                    .frame(width: 1)
                ScrollView {
                    content
                        .frame(maxWidth: 600, alignment: .leading)
                        .padding(.horizontal, 32)
                        .padding(.top, 46)
                        .padding(.bottom, 40)
                        .frame(maxWidth: .infinity)
                }
                .scrollIndicators(.never)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(background)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        // Opaque over the whole window, title strip included: nothing of the session shows through.
        .background(background)
        .ignoresSafeArea()
        .environment(\.colorScheme, style.isDark ? .dark : .light)
    }

    /// Sections with something broken in them.
    private var warnings: Set<SettingsPage.Section> {
        var sections = Set<SettingsPage.Section>()
        if page.agents.notificationsBlocked {
            sections.insert(.agents)
        }
        if !page.general.problems.isEmpty {
            sections.insert(.general)
        }
        return sections
    }

    @ViewBuilder
    private var content: some View {
        switch page.navigation.section {
        case .appearance: AppearanceSection(themes: page.themes, windowOptions: page.windowOptions, style: style)
        case .agents: AgentsSection(model: page.agents, style: style)
        case .general: GeneralSection(model: page.general, style: style, onReload: actions.reload)
        case .shortcuts: ShortcutsSection(style: style)
        }
    }
}

/// The sections, where the sidebar was; a session that needs you, and the way back, at its foot.
private struct SettingsList: View {
    @Bindable var navigation: SettingsPage.Navigation
    let compact: Bool
    let style: SidebarStyle
    let warnings: Set<SettingsPage.Section>
    let waiting: Session?
    let hasSessions: Bool
    let actions: SettingsView.Actions

    var body: some View {
        VStack(alignment: compact ? .center : .leading, spacing: 2) {
            if !compact {
                Text("Settings")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(style.primary)
                    .padding(.horizontal, 10)
                    .padding(.bottom, 12)
                    .accessibilityAddTraits(.isHeader)
            }
            ForEach(SettingsPage.Section.allCases) { section in
                item(section)
            }
            Spacer(minLength: 16)
            if let waiting {
                waitingRow(waiting)
                    .padding(.bottom, 4)
            }
            Button(action: actions.close) {
                HStack(spacing: 8) {
                    KeyCaps(keys: ["esc"], style: style)
                    if !compact {
                        Text(hasSessions ? "Back to your sessions" : "Back")
                            .font(.system(size: 12))
                            .foregroundStyle(style.secondary)
                    }
                }
                .padding(.horizontal, compact ? 0 : 10)
                .frame(height: 30)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(hasSessions ? "Back to your sessions" : "Back")
        }
        // Below the traffic lights, as the sidebar's search field sits.
        .padding(.top, 58)
        .padding(.horizontal, compact ? 8 : 12)
        .padding(.bottom, 14)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private func item(_ section: SettingsPage.Section) -> some View {
        let selected = navigation.section == section
        return Button {
            navigation.section = section
        } label: {
            HStack(spacing: 10) {
                Image(systemName: section.symbol)
                    .font(.system(size: 14))
                    .frame(width: 18)
                if !compact {
                    Text(section.title)
                        .font(.system(size: 13))
                    Spacer(minLength: 4)
                }
                if warnings.contains(section) {
                    WarningMark(style: style, size: compact ? 10 : 12)
                }
            }
            .foregroundStyle(selected ? style.primary : style.secondary)
            .padding(.horizontal, 10)
            .frame(maxWidth: compact ? nil : .infinity, alignment: .leading)
            .frame(height: 32)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(selected ? style.selection : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(compact ? section.title : "")
        .accessibilityLabel(section.title)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    /// A session that needs you, in its card's tint: one click goes to it (UIUX.md → Settings).
    private func waitingRow(_ session: Session) -> some View {
        Button {
            actions.goToSession(session.id)
        } label: {
            HStack(spacing: 10) {
                Circle()
                    .fill(style.attention)
                    .frame(width: 7, height: 7)
                if !compact {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(session.displayTitle)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(style.primary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Text("Needs you")
                            .font(.system(size: 11))
                            .foregroundStyle(style.secondary)
                    }
                    Spacer(minLength: 0)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: compact ? nil : .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(style.attention.opacity(0.14)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(compact ? "\(session.displayTitle) needs you" : "")
        .accessibilityLabel("\(session.displayTitle) needs you")
    }
}

/// Opens Calm's and Ghostty's files and System Settings. Headless self-tests log what they'd
/// open instead.
@MainActor
enum SettingsActions {
    static func openConfigFile() {
        let url = CalmSettings.standardURL
        if !FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? "# Calm Terminal settings: https://github.com/jinhuang712/calm/blob/main/FEATURES.md\n"
                .write(to: url, atomically: true, encoding: .utf8)
        }
        open(url)
    }

    static func openThemesFolder() {
        let folder = ThemeLibrary.userFolder
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        open(folder)
    }

    static func openGhosttyConfig() {
        open(TerminalConfig.userConfigFile)
    }

    /// System Settings → Notifications, at Calm's entry.
    static func openNotificationSettings() {
        let id = Bundle.main.bundleIdentifier ?? ""
        guard let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension?id=\(id)") else { return }
        open(url)
    }

    private static func open(_ url: URL) {
        if Headless.isOn {
            FileHandle.standardError.write(Data("calm-selftest: would open \(url.isFileURL ? url.path : url.absoluteString)\n".utf8))
            return
        }
        NSWorkspace.shared.open(url)
    }
}

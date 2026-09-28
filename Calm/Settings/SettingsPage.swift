import AppKit
import CalmModel
import SwiftUI

/// The settings page (FEATURES.md → F14, UIUX.md → Settings): ⌘, turns the whole window into
/// Settings, as the welcome page fills it. A list of sections takes the sidebar's place, and esc
/// (or ⌘, again) goes back to the session exactly as it was; it keeps running underneath. Everything is saved to config.toml at once.
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
    }

    let page: SettingsPage
    let manager: SessionManager
    let style: SidebarStyle
    /// The terminal's background: the page stands where the session would.
    let background: Color
    let actions: Actions

    /// Room for the list and a full page; narrower windows show the list as icons.
    private static var roomyWidth: CGFloat {
        SidebarView.width + 560.scaled
    }

    var body: some View {
        GeometryReader { proxy in
            let compact = proxy.size.width < Self.roomyWidth
            HStack(spacing: 0) {
                // As wide as the sidebar and drawn like it, so ⌘, reads as the sidebar changing
                // what it lists rather than a new panel.
                SettingsList(
                    navigation: page.navigation, compact: compact, style: style,
                    warnings: warnings, hasSessions: !manager.workspace.sessions.isEmpty, actions: actions,
                )
                .frame(width: compact ? 68.scaled : SidebarView.width)
                .background(style.background)
                Rectangle()
                    .fill(style.hairline)
                    .frame(width: 1)
                ScrollView {
                    content
                        .frame(maxWidth: Self.columnWidth, alignment: .leading)
                        .padding(.leading, leadingInset(pane: proxy.size.width - (compact ? 68.scaled : SidebarView.width) - 1))
                        .padding(.trailing, 48.scaled)
                        .padding(.top, 40.scaled)
                        .padding(.bottom, 48.scaled)
                        .frame(maxWidth: .infinity, alignment: .leading)
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

    private static var columnWidth: CGFloat {
        780.scaled
    }

    /// The page stays near the list, so the two read as one screen: centered while the pane is
    /// modest, then held 112 pt from the list. On a wide window a centered column ended up an
    /// island, far from the list it belongs to.
    private func leadingInset(pane: CGFloat) -> CGFloat {
        min(max((pane - Self.columnWidth) / 2, 48.scaled), 112.scaled)
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
        case .general: GeneralSection(model: page.general, style: style)
        case .shortcuts: ShortcutsSection(style: style)
        }
    }
}

/// The sections, where the sidebar was, and the way back at its foot.
private struct SettingsList: View {
    @Bindable var navigation: SettingsPage.Navigation
    let compact: Bool
    let style: SidebarStyle
    let warnings: Set<SettingsPage.Section>
    let hasSessions: Bool
    let actions: SettingsView.Actions

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Room for the traffic lights, as the sidebar leaves above its search field.
            Color.clear.frame(height: 40.scaled)
            if !compact {
                Text("Settings")
                    .calmFont(size: SettingsMetrics.listTitle, weight: .medium)
                    .foregroundStyle(style.primary)
                    .frame(height: 40.scaled, alignment: .leading)
                    .padding(.horizontal, 16.scaled)
                    .padding(.bottom, 16.scaled)
                    .accessibilityAddTraits(.isHeader)
            }
            VStack(spacing: 2.scaled) {
                ForEach(SettingsPage.Section.allCases) { section in
                    item(section)
                }
            }
            .padding(.horizontal, 12.scaled)
            Spacer(minLength: 16)
            VStack(spacing: 2.scaled) {
                ListButton(style: style, help: compact ? "Back (esc)" : "", action: actions.close) {
                    HStack(spacing: 11.scaled) {
                        KeyCaps(keys: ["esc"], style: style, large: true)
                            .frame(width: SettingsMetrics.listTile)
                        if !compact {
                            Text(hasSessions ? "Back to your sessions" : "Back")
                                .calmFont(size: SettingsMetrics.listItem)
                            Spacer(minLength: 4)
                        }
                    }
                    .padding(.horizontal, 8.scaled)
                }
                .accessibilityLabel(hasSessions ? "Back to your sessions" : "Back")
            }
            .padding(.horizontal, 12.scaled)
            .padding(.top, 10.scaled)
            .padding(.bottom, 14.scaled)
            // The sidebar's footer line.
            .overlay(alignment: .top) { Rectangle().fill(style.tertiary.opacity(0.14)).frame(height: 1) }
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    /// A section, drawn as the sidebar's footer rows are: its icon on a small tile.
    private func item(_ section: SettingsPage.Section) -> some View {
        let selected = navigation.section == section
        return ListButton(style: style, isSelected: selected, help: compact ? section.title : "") {
            navigation.section = section
        } label: {
            HStack(spacing: 11.scaled) {
                Image(systemName: section.symbol)
                    .calmFont(size: 16)
                    .frame(width: SettingsMetrics.listTile, height: SettingsMetrics.listTile)
                    .background(
                        RoundedRectangle(cornerRadius: 8.scaled, style: .continuous)
                            .fill(style.primary.opacity(selected ? 0.1 : 0.055)),
                    )
                if !compact {
                    Text(section.title)
                        .calmFont(size: SettingsMetrics.listItem, weight: selected ? .medium : .regular)
                    Spacer(minLength: 4)
                }
                if warnings.contains(section) {
                    WarningMark(style: style, size: compact ? 10 : 13)
                }
            }
            .padding(.horizontal, 8.scaled)
        }
        .accessibilityLabel(section.title)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// A row in the list: a full-width target, a quiet hover and the selection's surface, as the
/// sidebar's footer rows have.
private struct ListButton<Label: View>: View {
    let style: SidebarStyle
    var isSelected = false
    let help: String
    let action: () -> Void
    @ViewBuilder let label: Label
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            label
                .frame(maxWidth: .infinity, minHeight: SettingsMetrics.listRow, alignment: .leading)
                .foregroundStyle(isSelected || hovering ? style.primary : style.secondary)
                .background(
                    RoundedRectangle(cornerRadius: 10.scaled, style: .continuous)
                        .fill(isSelected ? style.selection : hovering ? style.selection.opacity(0.6) : .clear),
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
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

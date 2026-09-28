import AppKit
import CalmModel
import SwiftUI

/// Settings → General (UIUX.md → Settings): the editor, where paths open, auto-grouping, and the
/// config files behind every setting, with any line of config.toml Calm had to skip and the font
/// the Ghostty config sets.
@MainActor
@Observable
final class GeneralSettingsModel {
    /// `nil` is automatic: the first installed editor (LinkOpener's order).
    private(set) var editor: Editor?
    private(set) var installed: [Editor] = []
    private(set) var opensInViewer = true
    private(set) var autoGrouping = true
    /// config.toml's lines Calm couldn't read ("line 12: expected key = value").
    private(set) var problems: [String] = []
    /// "JetBrains Mono · 13 pt": set in the Ghostty config, which is where it's changed.
    private(set) var terminalFont = ""

    func refresh() {
        let settings = SessionManager.shared.settings
        installed = EditorLocator.installed
        editor = settings.string("editor").flatMap { Editor(rawValue: ($0 as NSString).lastPathComponent) }
        opensInViewer = LinkOpener.prefersViewer
        autoGrouping = settings.autoGrouping
        problems = settings.problems
        terminalFont = TerminalConfig.fontDescription
    }

    func setEditor(_ value: Editor?) {
        editor = value
        save("editor", value?.rawValue)
    }

    func setOpensInViewer(_ value: Bool) {
        opensInViewer = value
        save("open-paths", value ? nil : "editor")
    }

    func setAutoGrouping(_ value: Bool) {
        autoGrouping = value
        save("auto-grouping", value ? nil : "false")
    }

    /// `set:<key>=<value>` in self-tests goes through here, like a click.
    func set(_ key: String, _ value: String) {
        switch key {
        case "editor": setEditor(value == "automatic" ? nil : Editor(rawValue: value))
        case "open-paths": setOpensInViewer(value != "editor")
        case "auto-grouping": setAutoGrouping(value != "false")
        default: break
        }
    }

    private func save(_ key: String, _ value: String?) {
        do {
            SessionManager.shared.settings = try CalmSettings.save(key, value)
        } catch {
            FileHandle.standardError.write(Data("calm: could not save \(key): \(error)\n".utf8))
        }
    }
}

struct GeneralSection: View {
    let model: GeneralSettingsModel
    let style: SidebarStyle

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsTitle(title: "General", style: style)
                .padding(.bottom, 24.scaled)
            GroupHeading(title: "Opening files", style: style)
            SettingsGroup(style: style) {
                SettingsRow(title: "Editor", style: style) {
                    SettingsMenu(
                        title: "Editor", options: editorOptions, selection: model.editor, style: style,
                    ) { model.setEditor($0) }
                }
                RowDivider(style: style)
                SettingsRow(title: "Markdown, images and code", style: style) {
                    SettingsMenu(
                        title: "Markdown, images and code", options: [(true, "Open in Calm"), (false, "Open in the editor")],
                        selection: model.opensInViewer, style: style,
                    ) { model.setOpensInViewer($0) }
                }
            }
            GroupHeading(title: "Sessions", style: style)
                .padding(.top, 30.scaled)
            SettingsGroup(style: style) {
                SettingsRow(title: "Group sessions by folder", style: style) {
                    Toggle(
                        "Group sessions by folder",
                        isOn: Binding(get: { model.autoGrouping }, set: { model.setAutoGrouping($0) }),
                    )
                    .toggleStyle(CalmSwitchStyle(style: style))
                    .labelsHidden()
                }
            }
            GroupHeading(title: "Config files", style: style)
                .padding(.top, 30.scaled)
            SettingsGroup(style: style) {
                fileRow("Calm settings", problems: model.problems) { SettingsActions.openConfigFile() }
                RowDivider(style: style)
                SettingsRow(title: "Ghostty settings", note: model.terminalFont, style: style) {
                    Button("Open") { SettingsActions.openGhosttyConfig() }
                        .buttonStyle(SettingsButtonStyle(style: style))
                }
                RowDivider(style: style)
                fileRow("Your themes", problems: []) { SettingsActions.openThemesFolder() }
            }
        }
    }

    private var editorOptions: [(value: Editor?, label: String)] {
        let automatic = model.installed.first.map { "Automatic (\($0.displayName))" } ?? "Automatic"
        return [(value: nil, label: automatic)] + model.installed.map { (value: Optional($0), label: $0.displayName) }
    }

    /// A file or folder, and any line of it Calm couldn't read.
    private func fileRow(_ title: String, problems: [String], open: @escaping () -> Void) -> some View {
        HStack(spacing: 16.scaled) {
            VStack(alignment: .leading, spacing: 4.scaled) {
                Text(title)
                    .calmFont(size: SettingsMetrics.label)
                    .foregroundStyle(style.primary)
                ForEach(problems, id: \.self) { problem in
                    Label {
                        Text("\(problem.prefix(1).uppercased())\(problem.dropFirst()). Calm skipped it.")
                    } icon: {
                        WarningMark(style: style, size: SettingsMetrics.note)
                    }
                    .calmFont(size: SettingsMetrics.note)
                    .foregroundStyle(style.failure)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button("Open", action: open)
                .buttonStyle(SettingsButtonStyle(style: style))
        }
        .padding(.horizontal, SettingsMetrics.rowInset)
        .padding(.vertical, 14.scaled)
        .frame(minHeight: SettingsMetrics.rowHeight)
    }
}

/// Settings → Shortcuts: Calm's own keys (UIUX.md → Keyboard). They come from the Ghostty
/// config, which is where they're changed.
struct ShortcutsSection: View {
    let style: SidebarStyle

    private struct Group {
        let title: String
        let rows: [(keys: [String], action: String)]
    }

    private static let columns: [[Group]] = [
        [
            Group(title: "Sessions", rows: [
                (["⌘", "K"], "Search sessions"),
                (["⌃", "Tab"], "Cycle, most recent first"),
                (["⌘", "1…9"], "Jump by position"),
                (["⌘", "⇧", "A"], "Next one that needs you"),
                (["⌘", "⇧", "I"], "Show the arrival card"),
            ]),
            Group(title: "New", rows: [
                (["⌘", "T"], "New session"),
                (["⌘", "⇧", "N"], "New scratch session"),
                (["⌘", "O"], "New project"),
                (["⌘", "⇧", "T"], "Reopen closed session"),
            ]),
        ],
        [
            Group(title: "View", rows: [
                (["⌘", "P"], "Command palette"),
                (["⌘", "⌃", "S"], "Toggle the sidebar"),
                (["⌘", "\\"], "Toggle the files column"),
                (["esc"], "Close a viewed file"),
                (["⌘", ","], "Settings"),
            ]),
            Group(title: "Terminal", rows: [
                (["⌘", "D"], "Split right"),
                (["⌘", "⇧", "D"], "Split down"),
                (["⌘", "⇧", "K"], "Clear the screen"),
            ]),
        ],
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                SettingsTitle(title: "Shortcuts", style: style)
                Button("Open Ghostty Config") { SettingsActions.openGhosttyConfig() }
                    .buttonStyle(SettingsButtonStyle(style: style))
            }
            // Keys are changed in the Ghostty config (the button above), where the user's own
            // keybindings win over Calm's.
            Color.clear.frame(height: 24.scaled)
            HStack(alignment: .top, spacing: 20.scaled) {
                ForEach(Self.columns.indices, id: \.self) { column in
                    VStack(alignment: .leading, spacing: 18.scaled) {
                        ForEach(Self.columns[column], id: \.title) { group in
                            VStack(alignment: .leading, spacing: 0) {
                                GroupHeading(title: group.title, style: style)
                                SettingsGroup(style: style) {
                                    ForEach(group.rows, id: \.action) { row in
                                        HStack(spacing: 10.scaled) {
                                            Text(row.action)
                                                .calmFont(size: SettingsMetrics.label)
                                                .foregroundStyle(style.primary)
                                            Spacer(minLength: 8)
                                            KeyCaps(keys: row.keys, style: style, large: true)
                                        }
                                        .padding(.horizontal, SettingsMetrics.rowInset)
                                        .frame(height: 50.scaled)
                                        .accessibilityElement(children: .ignore)
                                        .accessibilityLabel("\(row.action), \(row.keys.joined())")
                                    }
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
    }
}

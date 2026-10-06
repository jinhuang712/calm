import AppKit
import CalmModel
import SwiftUI

/// Settings → General (UIUX.md → Settings): the editor, where paths open, auto-grouping, and the
/// config files behind every setting, with any line of config.toml Calm had to skip and the font
/// the Ghostty config sets.
@MainActor
@Observable
final class GeneralSettingsModel {
    /// Automatic is the first installed editor (LinkOpener's order).
    private(set) var editor = EditorSetting.automatic
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
        editor = EditorSetting(configured: settings.string("editor"))
        opensInViewer = LinkOpener.prefersViewer
        autoGrouping = settings.autoGrouping
        problems = settings.problems
        terminalFont = TerminalConfig.fontDescription
    }

    func setEditor(_ value: EditorSetting) {
        editor = value
        save("editor", value.configured)
    }

    /// "Choose Application…": the system's file picker, on /Applications.
    func chooseEditorApplication() {
        SettingsActions.chooseApplication { [weak self] app in self?.setEditorApplication(app) }
    }

    func setEditorApplication(_ app: URL) {
        // A known editor at its usual place is the plain choice, by name, so it isn't listed twice.
        if let (editor, tool) = EditorLocator.tool(inApplication: app), EditorLocator.locations(for: editor).contains(tool) {
            setEditor(.editor(editor))
        } else {
            setEditor(.application(path: app.path))
        }
    }

    /// Said under the row only when the chosen app can't open a file at a line.
    var editorNote: String? {
        guard case let .application(path) = editor, EditorLocator.tool(inApplication: URL(filePath: path)) == nil else { return nil }
        return "Opens the file, not at the line."
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
        case "editor": setEditor(value == "automatic" ? .automatic : EditorSetting(configured: value))
        case "editor-app": setEditorApplication(URL(filePath: value)) // what the picker hands back
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
                SettingsRow(title: "Editor", note: model.editorNote, symbol: "chevron.left.forwardslash.chevron.right", style: style) {
                    SettingsMenu(
                        title: "Editor", options: editorOptions, selection: model.editor, style: style,
                        actions: [(title: "Choose Application…", run: { model.chooseEditorApplication() })],
                    ) { model.setEditor($0) }
                }
                RowDivider(style: style)
                SettingsRow(title: "Markdown, images and code", symbol: "doc.richtext", style: style) {
                    SettingsMenu(
                        title: "Markdown, images and code", options: [(true, "Open in Calm"), (false, "Open in the editor")],
                        selection: model.opensInViewer, style: style,
                    ) { model.setOpensInViewer($0) }
                }
            }
            GroupHeading(title: "Sessions", style: style)
                .padding(.top, 30.scaled)
            SettingsGroup(style: style) {
                SettingsRow(title: "Group sessions by folder", symbol: "folder", style: style) {
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
                fileRow("Calm settings", symbol: "gearshape", problems: model.problems) { SettingsActions.openConfigFile() }
                RowDivider(style: style)
                SettingsRow(title: "Ghostty settings", note: model.terminalFont, symbol: "terminal", style: style) {
                    Button("Open") { SettingsActions.openGhosttyConfig() }
                        .buttonStyle(SettingsButtonStyle(style: style))
                }
                RowDivider(style: style)
                fileRow("Your themes", symbol: "paintpalette", problems: []) { SettingsActions.openThemesFolder() }
            }
        }
    }

    private var editorOptions: [(value: EditorSetting, label: String)] {
        let automatic = model.installed.first.map { "Automatic (\($0.displayName))" } ?? "Automatic"
        var options: [(value: EditorSetting, label: String)] = [(value: .automatic, label: automatic)]
        options += model.installed.map { (value: EditorSetting.editor($0), label: $0.displayName) }
        // An app chosen with "Choose Application…" stays listed (and ticked) beside the editors found.
        if case let .application(path) = model.editor {
            options.append((value: .application(path: path), label: EditorSetting.applicationName(path: path)))
        }
        return options
    }

    /// A file or folder, and any line of it Calm couldn't read.
    private func fileRow(_ title: String, symbol: String, problems: [String], open: @escaping () -> Void) -> some View {
        HStack(spacing: 16.scaled) {
            SettingsIcon(symbol: symbol, style: style)
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
                (["⌃", "Tab"], "Cycle, top to bottom"),
                (["⌘", "1…9"], "Jump by position"),
                (["⌘", "⇧", "A"], "Next one that needs you"),
                (["⌘", "⇧", "I"], "Show the arrival card"),
            ]),
            Group(title: "New", rows: [
                (["⌘", "N"], "New session running your agent"),
                (["⌘", "T"], "New session"),
                (["⌘", "⇧", "N"], "New scratch session, running your agent"),
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

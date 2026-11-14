import AppKit
import CalmModel
import SwiftUI

/// Settings → General (specs/UIUX.md → Settings): the editor, where paths open, auto-grouping, and the
/// config files behind every setting, with any line of config.toml Calm had to skip and the font
/// the Ghostty config sets.
@MainActor
@Observable
final class GeneralSettingsModel {
    /// Automatic is the first installed editor (LinkOpener's order).
    private(set) var editor = EditorSetting.automatic
    private(set) var installed: [Editor] = []
    /// The set editor that isn't found, and where files go instead.
    private(set) var editorChoice = EditorLocator.Choice()
    /// Where each kind of file opens (`files.open-<kind>`).
    private(set) var openers: [CalmSettings.FileKind: CalmSettings.FileOpener] = [:]
    private(set) var autoGrouping = true
    private(set) var checksForUpdates = true
    /// config.toml's lines Calm couldn't read ("line 12: expected key = value").
    private(set) var problems: [String] = []
    /// "JetBrains Mono · 13 pt": set in the Ghostty config, which is where it's changed.
    private(set) var terminalFont = ""

    func refresh() {
        let settings = SessionManager.shared.settings
        installed = EditorLocator.installed
        editor = EditorSetting(configured: settings.string("files.editor"))
        editorChoice = EditorLocator.choice()
        openers = Dictionary(uniqueKeysWithValues: CalmSettings.FileKind.allCases.map { ($0, settings.opener(for: $0)) })
        autoGrouping = settings.autoGrouping
        checksForUpdates = settings.checksForUpdates
        problems = settings.problems
        terminalFont = TerminalConfig.fontDescription
    }

    func setEditor(_ value: EditorSetting) {
        editor = value
        save("files.editor", value.configured)
        editorChoice = EditorLocator.choice()
    }

    /// "Choose Application…": the system's file picker, on /Applications.
    func chooseEditorApplication() {
        SettingsActions.chooseApplication { [weak self] app in self?.setEditorApplication(app) }
    }

    func setEditorApplication(_ app: URL) {
        // A known editor at its usual place is the plain choice, by name, so it isn't listed twice.
        if let (editor, tool) = EditorLocator.tool(inApplication: app), EditorLocator.locations(for: editor).contains(tool) {
            setEditor(.editor(editor))
        } else if let id = Bundle(url: app)?.bundleIdentifier, EditorSetting.isBundleID(id),
                  EditorLocator.application(bundleID: id)?.standardizedFileURL.path == app.standardizedFileURL.path {
            // By ID, so the setting survives the app moving. Only when macOS picks this same copy by
            // it: a dev build beside the installed app stays a path.
            setEditor(.applicationID(id))
        } else {
            setEditor(.application(path: app.path))
        }
    }

    /// Said under the row when the set editor is gone, or when the chosen app can't open a file at
    /// a line.
    var editorNote: String? {
        if let missing = editorChoice.missing {
            return "\(missing) isn't found. Files open in \(editorChoice.target?.name ?? "their default app")."
        }
        // A known editor's bundle resolves to its tool, so `.application` is one with no command line.
        guard case .application = editorChoice.target else { return nil }
        return "Opens the file, not at the line."
    }

    /// An application's name in the menu: by its bundle when found, else as the setting names it.
    static func applicationLabel(_ setting: EditorSetting) -> String? {
        switch setting {
        case let .application(path):
            EditorSetting.applicationName(path: path)
        case let .applicationID(id):
            EditorLocator.application(bundleID: id).map { EditorSetting.applicationName(path: $0.path) } ?? EditorLocator.missingName(id)
        case .automatic, .editor:
            nil
        }
    }

    func setOpener(_ value: CalmSettings.FileOpener, for kind: CalmSettings.FileKind) {
        openers[kind] = value
        // Written even when it is the default: an older config's `open-in = "editor"` would otherwise
        // still win over an unset key.
        save(kind.key, value.rawValue)
    }

    func setAutoGrouping(_ value: Bool) {
        autoGrouping = value
        save("sidebar.auto-grouping", value ? nil : "false")
    }

    func setChecksForUpdates(_ value: Bool) {
        checksForUpdates = value
        save("updates.check", value ? nil : "false")
    }

    /// `set:<key>=<value>` in self-tests goes through here, like a click.
    func set(_ key: String, _ value: String) {
        switch key {
        case "editor": setEditor(value == "automatic" ? .automatic : EditorSetting(configured: value))
        case "editor-app": setEditorApplication(URL(filePath: value)) // what the picker hands back
        case let name where name.hasPrefix("open-"):
            if let kind = CalmSettings.FileKind(rawValue: String(name.dropFirst(5))),
               let opener = CalmSettings.FileOpener(rawValue: value) {
                setOpener(opener, for: kind)
            }
        case "auto-grouping": setAutoGrouping(value != "false")
        case "updates": setChecksForUpdates(value != "false")
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
                SettingsRow(title: "Markdown", symbol: "doc.richtext", style: style) {
                    openerPicker(.markdown, title: "Markdown")
                }
                RowDivider(style: style)
                SettingsRow(title: "Web pages", symbol: "globe", style: style) {
                    openerPicker(.html, title: "Web pages")
                }
                RowDivider(style: style)
                SettingsRow(title: "Images", symbol: "photo", style: style) {
                    openerPicker(.images, title: "Images")
                }
                RowDivider(style: style)
                SettingsRow(title: "PDF", symbol: "doc", style: style) {
                    openerPicker(.pdf, title: "PDF")
                }
                RowDivider(style: style)
                SettingsRow(title: "Code", symbol: "curlybraces", style: style) {
                    openerPicker(.code, title: "Code")
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
            GroupHeading(title: "Updates", style: style)
                .padding(.top, 30.scaled)
            SettingsGroup(style: style) {
                SettingsRow(
                    title: "Check for updates",
                    note: "Once a day Calm asks GitHub which release is newest. The request carries only Calm's version.",
                    symbol: "arrow.down.circle",
                    style: style,
                ) {
                    Toggle(
                        "Check for updates",
                        isOn: Binding(get: { model.checksForUpdates }, set: { model.setChecksForUpdates($0) }),
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
        if let label = GeneralSettingsModel.applicationLabel(model.editor) {
            options.append((value: model.editor, label: label))
        }
        return options
    }

    /// A file or folder, and any line of it Calm couldn't read.
    private func openerPicker(_ kind: CalmSettings.FileKind, title: String) -> some View {
        CalmSegmented(
            title: title,
            options: [(CalmSettings.FileOpener.calm, "Calm"), (.system, "Default"), (.editor, "Editor")],
            selection: model.openers[kind] ?? .calm, segmentWidth: 76, style: style,
        ) { model.setOpener($0, for: kind) }
    }

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

/// Settings → Shortcuts: Calm's own keys (specs/UIUX.md → Keyboard). They come from the Ghostty
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
                (["⌘", "T"], "New shell"),
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

import AppKit
import CalmModel
import SwiftUI

/// Settings → General (UIUX.md → Settings): the editor, where paths open, auto-grouping, and the
/// config files behind every setting, with any line of config.toml Calm had to skip.
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

    func refresh() {
        let settings = SessionManager.shared.settings
        installed = EditorLocator.installed
        editor = settings.string("editor").flatMap { Editor(rawValue: ($0 as NSString).lastPathComponent) }
        opensInViewer = LinkOpener.prefersViewer
        autoGrouping = settings.autoGrouping
        problems = settings.problems
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
    let onReload: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsTitle(title: "General", style: style)
                .padding(.bottom, 22)
            GroupHeading(title: "Opening files", note: "When you ⌘-click a path an agent printed", style: style)
            SettingsGroup(style: style) {
                SettingsRow(title: "Editor", style: style) {
                    SettingsMenu(
                        title: "Editor", options: editorOptions, selection: model.editor, style: style,
                    ) { model.setEditor($0) }
                }
                RowDivider(style: style)
                SettingsRow(title: "Files Calm can show", note: "Markdown, HTML, PDFs, images and code. Esc goes back.", style: style) {
                    SettingsMenu(
                        title: "Files Calm can show", options: [(true, "Open in Calm"), (false, "Open in the editor")],
                        selection: model.opensInViewer, style: style,
                    ) { model.setOpensInViewer($0) }
                }
            }
            GroupHeading(title: "Sessions", style: style)
                .padding(.top, 22)
            SettingsGroup(style: style) {
                SettingsRow(
                    title: "Group sessions by folder", note: "A session moves to another group when its folder changes.", style: style,
                ) {
                    Toggle(
                        "Group sessions by folder",
                        isOn: Binding(get: { model.autoGrouping }, set: { model.setAutoGrouping($0) }),
                    )
                    .toggleStyle(CalmSwitchStyle(style: style))
                    .labelsHidden()
                }
            }
            GroupHeading(title: "Config files", note: "Every setting here is also a line in config.toml", style: style)
                .padding(.top, 22)
            SettingsGroup(style: style) {
                fileRow("Calm settings", path: CalmSettings.standardURL, problems: model.problems) { SettingsActions.openConfigFile() }
                RowDivider(style: style)
                SettingsRow(
                    title: "Ghostty settings",
                    note: "Font, keys and the rest of the terminal. They win over Calm's defaults.",
                    style: style,
                ) {
                    Button("Open") { SettingsActions.openGhosttyConfig() }
                        .buttonStyle(SettingsButtonStyle(style: style))
                }
                RowDivider(style: style)
                fileRow("Your themes", path: ThemeLibrary.userFolder, problems: []) { SettingsActions.openThemesFolder() }
                RowDivider(style: style)
                HStack {
                    Text("Edited a file by hand?")
                        .font(.system(size: 11))
                        .foregroundStyle(style.secondary)
                    Spacer()
                    Button("Reload Files", action: onReload)
                        .buttonStyle(SettingsButtonStyle(style: style))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
            }
        }
    }

    private var editorOptions: [(value: Editor?, label: String)] {
        let automatic = model.installed.first.map { "Automatic (\($0.displayName))" } ?? "Automatic"
        return [(value: nil, label: automatic)] + model.installed.map { (value: Optional($0), label: $0.displayName) }
    }

    /// A file or folder with its path, and what Calm couldn't read in it.
    private func fileRow(_ title: String, path: URL, problems: [String], open: @escaping () -> Void) -> some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13))
                    .foregroundStyle(style.primary)
                Text((path.path as NSString).abbreviatingWithTildeInPath)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(style.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                ForEach(problems, id: \.self) { problem in
                    Label {
                        Text("\(problem.prefix(1).uppercased())\(problem.dropFirst()). Calm skipped it.")
                    } icon: {
                        WarningMark(style: style, size: 11)
                    }
                    .font(.system(size: 11))
                    .foregroundStyle(style.failure)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button("Open", action: open)
                .buttonStyle(SettingsButtonStyle(style: style))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .frame(minHeight: 44)
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
            ]),
        ],
        [
            Group(title: "View", rows: [
                (["⌘", "P"], "Command palette"),
                (["⌘", "⌃", "S"], "Toggle the sidebar"),
                (["⌘", "⇧", "E"], "Toggle the files column"),
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
            Text("Calm's own keys. They come from your Ghostty config, where a keybinding of yours wins over Calm's.")
                .font(.system(size: 13))
                .foregroundStyle(style.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 6)
                .padding(.bottom, 22)
            HStack(alignment: .top, spacing: 20) {
                ForEach(Self.columns.indices, id: \.self) { column in
                    VStack(alignment: .leading, spacing: 18) {
                        ForEach(Self.columns[column], id: \.title) { group in
                            VStack(alignment: .leading, spacing: 0) {
                                GroupHeading(title: group.title, style: style)
                                SettingsGroup(style: style) {
                                    ForEach(group.rows, id: \.action) { row in
                                        HStack(spacing: 10) {
                                            Text(row.action)
                                                .font(.system(size: 12))
                                                .foregroundStyle(style.primary)
                                            Spacer(minLength: 8)
                                            KeyCaps(keys: row.keys, style: style)
                                        }
                                        .padding(.horizontal, 12)
                                        .frame(height: 30)
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

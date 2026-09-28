import AppKit
import CalmModel
import SwiftUI

/// A settings pane's frame: native colors, the same margins and width in every section.
struct SettingsPane<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content
        }
        .padding(24)
        .frame(width: 560, alignment: .topLeading)
    }
}

struct SettingsHeading: View {
    let title: String
    var note: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 13, weight: .medium))
            if let note {
                Text(note)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.bottom, 12)
    }
}

// MARK: General

/// Settings → General (UIUX.md → Settings screen): the editor, where paths open, auto-grouping.
@MainActor
@Observable
final class GeneralSettingsModel {
    /// `nil` is automatic: the first installed editor (LinkOpener's order).
    private(set) var editor: Editor?
    private(set) var installed: [Editor] = []
    private(set) var opensInViewer = true
    private(set) var autoGrouping = true

    func refresh() {
        let settings = SessionManager.shared.settings
        installed = EditorLocator.installed
        editor = settings.string("editor").flatMap { Editor(rawValue: ($0 as NSString).lastPathComponent) }
        opensInViewer = LinkOpener.prefersViewer
        autoGrouping = settings.autoGrouping
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

struct GeneralSettingsView: View {
    let model: GeneralSettingsModel

    var body: some View {
        SettingsPane {
            SettingsHeading(title: "Files and links", note: "Where a path an agent prints opens when you ⌘-click it.")
            Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 12) {
                GridRow {
                    Text("Editor").font(.system(size: 12)).gridColumnAlignment(.trailing)
                    Picker("Editor", selection: Binding(get: { model.editor }, set: { model.setEditor($0) })) {
                        Text(automaticLabel).tag(Editor?.none)
                        if !model.installed.isEmpty {
                            Divider()
                        }
                        ForEach(model.installed, id: \.self) { editor in
                            Text(editor.displayName).tag(Editor?.some(editor))
                        }
                    }
                    .labelsHidden()
                    .fixedSize()
                }
                GridRow {
                    Text("Open files").font(.system(size: 12))
                    Picker("Open files", selection: Binding(get: { model.opensInViewer }, set: { model.setOpensInViewer($0) })) {
                        Text("In Calm when it can show them").tag(true)
                        Text("In the editor").tag(false)
                    }
                    .labelsHidden()
                    .fixedSize()
                }
            }
            Divider().padding(.vertical, 20)
            SettingsHeading(title: "Projects")
            Toggle(
                "Group sessions by their folder, and move them when it changes",
                isOn: Binding(get: { model.autoGrouping }, set: { model.setAutoGrouping($0) }),
            )
            .font(.system(size: 12))
        }
    }

    private var automaticLabel: String {
        model.installed.first.map { "Automatic (\($0.displayName))" } ?? "Automatic"
    }
}

// MARK: Keys

/// Settings → Keys: Calm's own shortcuts (UIUX.md → Keyboard). Terminal keys come from the
/// Ghostty config, which is where they're changed.
struct KeysSettingsView: View {
    static let shortcuts: [(keys: String, action: String)] = [
        ("⌘K", "Search sessions"),
        ("⌘P", "Command palette"),
        ("⌃Tab", "Cycle sessions, most recent first"),
        ("⌘1…9", "Jump to a session by position"),
        ("⌘⇧A", "Jump to the next session that needs you"),
        ("⌘⇧I", "Show the arrival card again"),
        ("⌘⇧E", "Toggle the files column"),
        ("⌘⌃S", "Toggle the sidebar"),
        ("⌘T  ⌘D  ⌘⇧D", "New tab, split right, split down"),
        ("⌘⇧N  ⌘O", "New scratch session, new project"),
        ("⌘⇧K", "Clear the screen"),
        ("esc", "Close a viewed file"),
        ("⌘,", "Settings"),
    ]

    var body: some View {
        SettingsPane {
            SettingsHeading(
                title: "Shortcuts",
                note: "Keys come from your Ghostty config, and a keybinding there wins over Calm's.",
            )
            Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 8) {
                ForEach(Self.shortcuts, id: \.keys) { shortcut in
                    GridRow {
                        Text(shortcut.keys)
                            .font(.system(size: 12, design: .rounded))
                            .foregroundStyle(.secondary)
                            .gridColumnAlignment(.trailing)
                        Text(shortcut.action)
                            .font(.system(size: 12))
                    }
                }
            }
            HStack {
                Spacer()
                Button("Open Ghostty Config") { SettingsActions.openGhosttyConfig() }
            }
            .padding(.top, 20)
        }
    }
}

// MARK: Advanced

struct AdvancedSettingsView: View {
    var body: some View {
        SettingsPane {
            SettingsHeading(
                title: "Configuration",
                note: "Every setting is also in config.toml, along with a few that don't need a screen.",
            )
            HStack(spacing: 10) {
                Button("Open Config File") { SettingsActions.openConfigFile() }
                Button("Open Themes Folder") { SettingsActions.openThemesFolder() }
                Button("Reload") { TerminalEngine.shared.reloadConfig(soft: false) }
            }
        }
    }
}

/// Opens Calm's and Ghostty's files. Headless self-tests log what they'd open instead.
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

    private static func open(_ url: URL) {
        if Headless.isOn {
            FileHandle.standardError.write(Data("calm-selftest: would open \(url.path)\n".utf8))
            return
        }
        NSWorkspace.shared.open(url)
    }
}

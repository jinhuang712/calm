import AppKit
import CalmModel
import OSLog

/// Opens ⌘-clicked links (specs/FEATURES.md → F8): URLs in the browser, files in Calm's viewer, the
/// default app or the user's editor at the line, as each kind of file is set. Relative paths resolve against
/// the agent's folder, the session's, then its project's (agents often print repository-relative paths).
@MainActor
enum LinkOpener {
    private static let log = Logger(subsystem: "com.jinhuang.calm", category: "links")

    /// Where a file opens (`files.open-markdown`, `open-html` and so on). A file the viewer doesn't
    /// show goes to the editor.
    static func opener(for path: String) -> CalmSettings.FileOpener {
        guard let kind = ViewableKind.of(path) else { return .editor }
        return SessionManager.shared.settings.opener(for: kind.fileKind)
    }

    /// Whether this file opens in Calm's viewer.
    static func opensInViewer(_ path: String) -> Bool {
        ViewableKind.of(path) != nil && opener(for: path) == .calm
    }

    /// What a link points at, trying the project's folder for a relative path that isn't in the
    /// session's, and a path without the words the terminal swept up after it (`Link.candidates`).
    /// Files that don't exist resolve to nil.
    static func resolve(_ text: String, directory: String?, projectDirectory: String?, agentDirectory: String? = nil) -> Link? {
        Link.candidates(for: text).lazy.compactMap {
            resolveExactly($0, directory: directory, projectDirectory: projectDirectory, agentDirectory: agentDirectory)
        }.first
    }

    /// `resolve` for this text only. The agent's folder (a git worktree it moved into while the
    /// shell stayed behind) is tried first: it holds the files the agent just wrote.
    static func resolveExactly(_ text: String, directory: String?, projectDirectory: String?, agentDirectory: String? = nil) -> Link? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let first = Link.parse(text, relativeTo: directory, home: home)
        guard case .file = first else { return first }
        // `nil` last: an absolute path or `~` means the same in every folder.
        for folder in [agentDirectory, directory, projectDirectory, nil] {
            if let link = Link.parse(text, relativeTo: folder, home: home),
               case let .file(path, _, _) = link, FileManager.default.fileExists(atPath: path) {
                return link
            }
        }
        return nil
    }

    /// Opens a link outside Calm. Returns false when it names nothing.
    @discardableResult
    static func open(_ text: String, directory: String?, projectDirectory: String?) -> Bool {
        guard let link = resolve(text, directory: directory, projectDirectory: projectDirectory) else { return false }
        openOutside(link)
        return true
    }

    /// What the tag beside a ⌘-hovered link says: where a click takes it, decided as a click would
    /// (MainWindowController's `requestsOpenLink`: the viewer for files it shows, else the editor).
    static func preview(of link: Link?, text: String) -> LinkPreview {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        switch link {
        case nil:
            return .missing(text)
        case let .url(url):
            return .url(url)
        case let .file(path, line, _):
            var isDirectory: ObjCBool = false
            FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory)
            if isDirectory.boolValue {
                return .folder(path: path, home: home)
            }
            let kind = ViewableKind.of(path)
            let destination: LinkPreview.Destination = if opensInViewer(path) {
                .viewer
            } else if opener(for: path) == .editor {
                editorDestination(EditorLocator.choice())
            } else {
                .defaultApp
            }
            return .file(path: path, line: line, isImage: kind == .image, destination: destination, home: home)
        }
    }

    static func editorDestination(_ choice: EditorLocator.Choice) -> LinkPreview.Destination {
        if let missing = choice.missing {
            return .missingEditor(missing, fallback: choice.target?.name)
        }
        return choice.target.map { .editor($0.name) } ?? .defaultApp
    }

    static func openOutside(_ link: Link) {
        switch link {
        case let .url(url):
            perform("open \(url.absoluteString)") { NSWorkspace.shared.open(url) }
        case let .file(path, line, column):
            var isDirectory: ObjCBool = false
            FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory)
            if isDirectory.boolValue {
                perform("open \(path)") { NSWorkspace.shared.open(URL(filePath: path)) }
            } else if opener(for: path) == .system {
                openInDefaultApp(path)
            } else {
                openInEditor(path, line: line, column: column)
            }
        }
    }

    /// The user's editor at the position, or the file's default app when no editor is found.
    static func openInEditor(_ path: String, line: Int?, column: Int?) {
        switch EditorLocator.find() {
        case nil:
            openInDefaultApp(path)
        case let .tool(editor, executable):
            let arguments = editor.arguments(file: path, line: line, column: column)
            perform("\(editor.rawValue) \(arguments.joined(separator: " "))") {
                let process = Process()
                process.executableURL = executable
                process.arguments = arguments
                try? process.run()
            }
        case let .application(app):
            // An app Calm has no command line for: it gets the file, not the line.
            perform("open -a \(app.lastPathComponent) \(path)") {
                yieldFocus(to: app)
                NSWorkspace.shared.open([URL(filePath: path)], withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration())
            }
        }
    }

    /// Lets the app that gets the file come forward. Since macOS 14 activation is cooperative: an
    /// app asking to come forward is refused unless the active app (Calm, on a ⌘-click) yields to it
    /// first. A file handed to a running editor stayed behind Calm without this (2026-11-09).
    static func yieldFocus(to app: URL) {
        guard let id = Bundle(url: app)?.bundleIdentifier else { return }
        NSApp.yieldActivation(toApplicationWithBundleIdentifier: id)
    }

    /// The app macOS opens the file with (a picture or a PDF from the viewer, or a kind set to Default).
    static func openInDefaultApp(_ path: String) {
        perform("open \(path)") {
            let url = URL(filePath: path)
            if let app = NSWorkspace.shared.urlForApplication(toOpen: url) {
                yieldFocus(to: app)
            }
            NSWorkspace.shared.open(url)
        }
    }

    /// Headless self-tests never open other apps: they log what would be opened.
    private static func perform(_ description: String, _ action: () -> Void) {
        log.info("link: \(description, privacy: .public)")
        if Headless.isOn {
            FileHandle.standardError.write(Data("calm-selftest: would \(description)\n".utf8))
        } else {
            action()
        }
    }
}

/// Where a file opens: an editor's command-line tool, which takes a line, or an application
/// chosen in Settings that Calm knows no command line for.
enum EditorTarget {
    case tool(Editor, URL)
    case application(URL)

    var name: String {
        switch self {
        case let .tool(editor, _): editor.displayName
        case let .application(app): EditorSetting.applicationName(path: app.path)
        }
    }
}

/// Finds the user's editor: the `files.editor` setting (a name such as `cursor`, a path, an
/// application chosen in Settings by its `.app` path or bundle ID), else the first installed in
/// `Editor`'s order (VS Code and its forks, Zed, Sublime Text, IntelliJ IDEA, then Xcode). A GUI app's
/// PATH is minimal, so known install locations are checked directly.
enum EditorLocator {
    private static let log = Logger(subsystem: "com.jinhuang.calm", category: "links")

    /// What the setting comes to: the editor files go to, and the one set but not found, by name.
    struct Choice {
        var target: EditorTarget?
        var missing: String?
    }

    @MainActor
    static func find() -> EditorTarget? {
        choice().target
    }

    /// A set editor that is gone falls back to automatic, and is named so the ⌘ tag and Settings
    /// can say so (specs/FEATURES.md → A missing editor is named, then skipped).
    @MainActor
    static func choice() -> Choice {
        choice(configured: SessionManager.shared.settings.string("files.editor"))
    }

    static func choice(configured: String?) -> Choice {
        guard let configured, !configured.isEmpty else { return Choice(target: automatic()) }
        if let target = target(configured: configured) {
            return Choice(target: target)
        }
        let missing = missingName(configured)
        log.notice("editor \(configured, privacy: .public) not found, using automatic")
        return Choice(target: automatic(), missing: missing)
    }

    private static func target(configured: String) -> EditorTarget? {
        let path = (configured as NSString).expandingTildeInPath
        if configured.hasSuffix(".app") {
            return FileManager.default.fileExists(atPath: path) ? target(application: URL(filePath: path)) : nil
        }
        let name = (configured as NSString).lastPathComponent
        if configured.contains("/") {
            // A tool given by path: run as the editor its name says, else with VS Code's arguments.
            return isExecutable(URL(filePath: path)) ? .tool(Editor(rawValue: name) ?? .vscode, URL(filePath: path)) : nil
        }
        if let editor = Editor(rawValue: name) {
            return locations(for: editor).first(where: isExecutable).map { .tool(editor, $0) }
        }
        if EditorSetting.isBundleID(configured) {
            return application(bundleID: configured).map(target(application:))
        }
        return nil
    }

    private static func target(application app: URL) -> EditorTarget {
        tool(inApplication: app).map { .tool($0.0, $0.1) } ?? .application(app)
    }

    /// The application macOS knows by this bundle ID, wherever it is now.
    static func application(bundleID: String) -> URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
    }

    /// The set editor as people know it: "Gloss" for `/Applications/Gloss.app` or `dev.gloss.Gloss`.
    static func missingName(_ configured: String) -> String {
        if configured.hasSuffix(".app") {
            return EditorSetting.applicationName(path: configured)
        }
        let name = (configured as NSString).lastPathComponent
        if let editor = Editor(rawValue: name) {
            return editor.displayName
        }
        if !configured.contains("/"), EditorSetting.isBundleID(configured), let last = configured.split(separator: ".").last {
            return String(last)
        }
        return name
    }

    private static func automatic() -> EditorTarget? {
        for editor in Editor.allCases {
            if let url = locations(for: editor).first(where: isExecutable) {
                return .tool(editor, url)
            }
        }
        return nil
    }

    /// The editors installed on this Mac, in detection order (Settings → General).
    static var installed: [Editor] {
        Editor.allCases.filter { locations(for: $0).contains(where: isExecutable) }
    }

    /// The command-line tool inside an application bundle, when it is one of the known editors
    /// (matched by the bundle's name, so a copy in ~/Applications counts).
    static func tool(inApplication app: URL) -> (Editor, URL)? {
        for editor in Editor.allCases {
            for (name, tool) in editor.bundledTools where name == app.lastPathComponent {
                let url = app.appending(path: tool)
                if isExecutable(url) {
                    return (editor, url)
                }
            }
        }
        return nil
    }

    static func locations(for editor: Editor) -> [URL] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let bins = ["/opt/homebrew/bin", "/usr/local/bin", "\(home)/.local/bin", "\(home)/bin"].map { "\($0)/\(editor.rawValue)" }
        let bundled = editor.bundledTools.map { "/Applications/\($0.app)/\($0.tool)" }
        // xed is the shim in /usr/bin, which follows the selected Xcode: tried before the bundle.
        let system = editor == .xcode ? ["/usr/bin/xed"] : []
        return (bins + system + bundled).map { URL(filePath: $0) }
    }

    private static func isExecutable(_ url: URL) -> Bool {
        FileManager.default.isExecutableFile(atPath: url.path)
    }
}

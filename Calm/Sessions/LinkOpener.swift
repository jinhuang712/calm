import AppKit
import CalmModel
import OSLog

/// Opens ⌘-clicked links (FEATURES.md → F8): URLs in the browser, files in Calm's viewer (the
/// default for viewable files) or the user's editor at the line. Relative paths resolve against
/// the session's folder, then its project's (agents often print repository-relative paths).
@MainActor
enum LinkOpener {
    private static let log = Logger(subsystem: "com.jinhuang.calm", category: "links")

    /// Whether viewable files open in Calm's viewer (`files.open-in = "viewer"`, the default) or the editor.
    static var prefersViewer: Bool {
        SessionManager.shared.settings.string("files.open-in")?.lowercased() != "editor"
    }

    /// What a link points at, trying the project's folder for a relative path that isn't in the
    /// session's, and a path without the words the terminal swept up after it (`Link.candidates`).
    /// Files that don't exist resolve to nil.
    static func resolve(_ text: String, directory: String?, projectDirectory: String?) -> Link? {
        Link.candidates(for: text).lazy.compactMap { resolveExactly($0, directory: directory, projectDirectory: projectDirectory) }.first
    }

    /// `resolve` for this text only.
    static func resolveExactly(_ text: String, directory: String?, projectDirectory: String?) -> Link? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        var link = Link.parse(text, relativeTo: directory, home: home)
        if case let .file(path, _, _) = link, !FileManager.default.fileExists(atPath: path) {
            link = nil
            if let projectDirectory, let fromProject = Link.parse(text, relativeTo: projectDirectory, home: home),
               case let .file(projectPath, _, _) = fromProject, FileManager.default.fileExists(atPath: projectPath) {
                link = fromProject
            }
        }
        return link
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
            let destination: LinkPreview.Destination = if prefersViewer, kind != nil {
                .viewer
            } else if let target = EditorLocator.find() {
                .editor(target.name)
            } else {
                .defaultApp
            }
            return .file(path: path, line: line, isImage: kind == .image, destination: destination, home: home)
        }
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
            } else {
                openInEditor(path, line: line, column: column)
            }
        }
    }

    /// The user's editor at the position, or the file's default app when no editor is found.
    static func openInEditor(_ path: String, line: Int?, column: Int?) {
        switch EditorLocator.find() {
        case nil:
            perform("open \(path)") { NSWorkspace.shared.open(URL(filePath: path)) }
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
                NSWorkspace.shared.open([URL(filePath: path)], withApplicationAt: app, configuration: .init())
            }
        }
    }

    /// A picture or a PDF from the viewer: the app macOS opens it with, not the code editor.
    static func openInDefaultApp(_ path: String) {
        perform("open \(path)") { NSWorkspace.shared.open(URL(filePath: path)) }
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

/// Finds the user's editor: the `files.editor` setting (a name such as `cursor`, a path, or an
/// application chosen in Settings), else the first installed in `Editor`'s order (VS Code and its
/// forks, Zed, Sublime Text, IntelliJ IDEA, then Xcode). A GUI app's PATH is minimal, so known
/// install locations are checked directly.
enum EditorLocator {
    @MainActor
    static func find() -> EditorTarget? {
        if let configured = SessionManager.shared.settings.string("files.editor"), !configured.isEmpty {
            let path = (configured as NSString).expandingTildeInPath
            if configured.hasSuffix(".app") {
                // An app that has since been deleted falls through to automatic.
                if FileManager.default.fileExists(atPath: path) {
                    let app = URL(filePath: path)
                    return tool(inApplication: app).map { .tool($0.0, $0.1) } ?? .application(app)
                }
            } else {
                let name = (configured as NSString).lastPathComponent
                let editor = Editor(rawValue: name) ?? .vscode
                if configured.contains("/") {
                    return .tool(editor, URL(filePath: path))
                }
                if let editor = Editor(rawValue: name), let url = locations(for: editor).first(where: isExecutable) {
                    return .tool(editor, url)
                }
            }
        }
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

import AppKit
import CalmModel
import OSLog

/// Opens ⌘-clicked links (FEATURES.md → F8): URLs in the browser, files in the user's editor at
/// the line (or their default app when no editor is found). Relative paths resolve against the
/// session's folder, then its project's (agents often print repository-relative paths).
@MainActor
enum LinkOpener {
    private static let log = Logger(subsystem: "com.jinhuang.calm", category: "links")

    /// Returns false when a file link names nothing on disk.
    @discardableResult
    static func open(_ text: String, directory: String?, projectDirectory: String?) -> Bool {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        var link = Link.parse(text, relativeTo: directory, home: home)
        if case let .file(path, _, _) = link, !FileManager.default.fileExists(atPath: path), let projectDirectory,
           let fromProject = Link.parse(text, relativeTo: projectDirectory, home: home),
           case let .file(projectPath, _, _) = fromProject, FileManager.default.fileExists(atPath: projectPath) {
            link = fromProject
        }
        switch link {
        case let .url(url):
            perform("open \(url.absoluteString)") { NSWorkspace.shared.open(url) }
            return true
        case let .file(path, line, column):
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) else { return false }
            if !isDirectory.boolValue, let (editor, executable) = EditorLocator.find() {
                let arguments = editor.arguments(file: path, line: line, column: column)
                perform("\(editor.rawValue) \(arguments.joined(separator: " "))") {
                    let process = Process()
                    process.executableURL = executable
                    process.arguments = arguments
                    try? process.run()
                }
            } else {
                perform("open \(path)") { NSWorkspace.shared.open(URL(filePath: path)) }
            }
            return true
        case nil:
            return false
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

/// Finds the user's editor: the `editor` setting (a name such as `cursor`, or a path), else the
/// first installed in `Editor`'s order (VS Code and its forks, Zed, Sublime Text, IntelliJ IDEA,
/// then Xcode). A GUI app's PATH is minimal, so known install locations are checked directly.
enum EditorLocator {
    @MainActor
    static func find() -> (Editor, URL)? {
        if let configured = SessionManager.shared.settings.string("editor"), !configured.isEmpty {
            let name = (configured as NSString).lastPathComponent
            let editor = Editor(rawValue: name) ?? .vscode
            if configured.contains("/") {
                return (editor, URL(filePath: (configured as NSString).expandingTildeInPath))
            }
            if let editor = Editor(rawValue: name), let url = locations(for: editor).first(where: isExecutable) {
                return (editor, url)
            }
        }
        for editor in Editor.allCases {
            if let url = locations(for: editor).first(where: isExecutable) {
                return (editor, url)
            }
        }
        return nil
    }

    static func locations(for editor: Editor) -> [URL] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let bins = ["/opt/homebrew/bin", "/usr/local/bin", "\(home)/.local/bin", "\(home)/bin"].map { "\($0)/\(editor.rawValue)" }
        let bundled: [String] = switch editor {
        case .vscode: ["/Applications/Visual Studio Code.app/Contents/Resources/app/bin/code"]
        case .cursor: ["/Applications/Cursor.app/Contents/Resources/app/bin/cursor"]
        case .trae: ["/Applications/Trae.app/Contents/Resources/app/bin/trae"]
        case .windsurf: ["/Applications/Windsurf.app/Contents/Resources/app/bin/windsurf"]
        case .zed: ["/Applications/Zed.app/Contents/MacOS/cli"]
        case .sublime: ["/Applications/Sublime Text.app/Contents/SharedSupport/bin/subl"]
        case .xcode: ["/usr/bin/xed"]
        case .idea: ["/Applications/IntelliJ IDEA.app/Contents/MacOS/idea", "/Applications/IntelliJ IDEA CE.app/Contents/MacOS/idea"]
        }
        return (bins + bundled).map { URL(filePath: $0) }
    }

    private static func isExecutable(_ url: URL) -> Bool {
        FileManager.default.isExecutableFile(atPath: url.path)
    }
}

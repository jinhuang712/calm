import Foundation

/// What the tag beside a ⌘-hovered link says (FEATURES.md → F8, UIUX.md → Links): what the link
/// is, where it is, and what a click does.
public struct LinkPreview: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        case web
        case file
        case image
        case folder
        case missing
    }

    /// Where a file opens, as the app works it out from the settings and what's installed.
    public enum Destination: Equatable, Sendable {
        case viewer
        case editor(String)
        case defaultApp
    }

    public var kind: Kind
    /// The file's name (with `:line`), or the site.
    public var title: String
    /// The folder it's in (`~` for home), or the URL's path.
    public var detail: String?
    /// What a click does: "Open in viewer", "Open in browser", "Not found"…
    public var action: String

    public init(kind: Kind, title: String, detail: String?, action: String) {
        self.kind = kind
        self.title = title
        self.detail = detail
        self.action = action
    }

    public static func url(_ url: URL) -> LinkPreview {
        let scheme = url.scheme?.lowercased() ?? ""
        let action = scheme == "http" || scheme == "https" ? "Open in browser" : "Open"
        guard let host = url.host(), !host.isEmpty else {
            // mailto:, tel:, magnet:… have no host: show what follows the scheme.
            let text = url.absoluteString
            let title = text.range(of: ":").map { String(text[$0.upperBound...]) } ?? text
            return LinkPreview(kind: .web, title: String(title.trimmingPrefix("//")), detail: nil, action: action)
        }
        var path = url.path()
        if let query = url.query() {
            path += "?" + query
        }
        return LinkPreview(kind: .web, title: host, detail: path.isEmpty || path == "/" ? nil : path, action: action)
    }

    public static func file(path: String, line: Int?, isImage: Bool, destination: Destination, home: String) -> LinkPreview {
        let name = (path as NSString).lastPathComponent
        let action = switch destination {
        case .viewer: "Open in viewer"
        case let .editor(editor): "Open in \(editor)"
        case .defaultApp: "Open"
        }
        return LinkPreview(
            kind: isImage ? .image : .file,
            title: name + (line.map { ":\($0)" } ?? ""),
            detail: abbreviated((path as NSString).deletingLastPathComponent, home: home),
            action: action,
        )
    }

    public static func folder(path: String, home: String) -> LinkPreview {
        LinkPreview(
            kind: .folder,
            title: path == home ? "~" : (path as NSString).lastPathComponent,
            detail: path == home ? nil : abbreviated((path as NSString).deletingLastPathComponent, home: home),
            action: "Open in Finder",
        )
    }

    /// A link that leads nowhere (a file that isn't there), by the text the terminal matched.
    public static func missing(_ text: String) -> LinkPreview {
        let folder = (text as NSString).deletingLastPathComponent
        return LinkPreview(
            kind: .missing,
            title: (text as NSString).lastPathComponent,
            detail: folder.isEmpty ? nil : folder,
            action: "Not found",
        )
    }

    /// A folder as people read it: `~` for home.
    static func abbreviated(_ path: String, home: String) -> String {
        if path == home {
            return "~"
        }
        if !home.isEmpty, path.hasPrefix(home + "/") {
            return "~" + path.dropFirst(home.count)
        }
        return path
    }
}

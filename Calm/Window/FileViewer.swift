import AppKit
import CalmModel
import PDFKit
import SwiftUI
import WebKit

/// What the viewer shows a file as (FEATURES.md → F10), by extension; small UTF-8 files without a
/// known extension show as text.
enum ViewableKind: Equatable {
    case markdown
    case html
    case pdf
    case image
    case code(language: String?)
    case text

    /// Files bigger than this open outside Calm instead.
    static let maximumTextSize = 5_000_000

    static func of(_ path: String) -> ViewableKind? {
        let url = URL(filePath: path)
        let ext = url.pathExtension.lowercased()
        switch ext {
        case "md", "markdown", "mdx": return .markdown
        case "html", "htm": return .html
        case "pdf": return .pdf
        case "png", "jpg", "jpeg", "gif", "webp", "heic", "tiff", "bmp", "svg": return .image
        default: break
        }
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? .max
        guard size <= maximumTextSize else { return nil }
        if let language = languages[ext] ?? languages[url.lastPathComponent.lowercased()] {
            return .code(language: language)
        }
        // Anything else that reads as UTF-8 text.
        guard let handle = try? FileHandle(forReadingFrom: url), let head = try? handle.read(upToCount: 4096) else { return nil }
        try? handle.close()
        return String(bytes: head, encoding: .utf8) != nil && !head.contains(0) ? .text : nil
    }

    /// highlight.js language names for common extensions (and a few well-known file names).
    static let languages: [String: String] = [
        "swift": "swift", "js": "javascript", "mjs": "javascript", "cjs": "javascript", "jsx": "javascript",
        "ts": "typescript", "tsx": "typescript", "py": "python", "rb": "ruby", "go": "go", "rs": "rust",
        "java": "java", "kt": "kotlin", "c": "c", "h": "c", "m": "objectivec", "mm": "objectivec", "cpp": "cpp",
        "cc": "cpp", "hpp": "cpp", "cs": "csharp", "php": "php", "sh": "bash", "bash": "bash", "zsh": "bash",
        "fish": "bash", "json": "json", "yaml": "yaml", "yml": "yaml", "toml": "ini", "ini": "ini", "xml": "xml",
        "plist": "xml", "css": "css", "scss": "scss", "less": "less", "sql": "sql", "lua": "lua", "diff": "diff",
        "patch": "diff", "graphql": "graphql", "dockerfile": "dockerfile", "makefile": "makefile", "zig": "zig",
    ]
}

/// The file viewer (FEATURES.md → F10): a viewable file covers the terminal area, under the title
/// strip, which stays the session's; esc returns to the session exactly as it was (it keeps running
/// underneath).
@MainActor
final class FileViewer: NSObject {
    private weak var container: NSView?
    private var root: NSView?
    private var keyMonitor: Any?
    private var onClose: (() -> Void)?
    /// Scripts for the page, held until it has loaded.
    private var pendingScripts: [String] = []
    private var pageLoaded = false
    private(set) weak var webView: WKWebView?
    private(set) weak var pdfView: PDFView?
    private var reading: Task<Void, Never>?
    private(set) var file: String?
    /// Find in the file (ViewerFind): the header's field and what it found.
    let find = ViewerFindModel()
    /// Find's colors: the viewer's background and text, the terminal's accent.
    var findColors: FindColors?
    /// PDFKit's matches, and the underlines added for each while find is open.
    var pdfMatches: [PDFSelection] = []
    var pdfMarks: [[(page: PDFPage, underline: PDFAnnotation)]] = []
    private let findMessages = ViewerFindMessages()
    /// The session the file was opened over; going to another one leaves the file.
    private(set) var session: Session.ID?
    /// Matches the terminal area's corners (a card window rounds them).
    var cornerRadius: CGFloat = 0
    /// Read by the title strip: it dims the session's name while a file is open over it.
    let presence = ViewerPresence()
    /// The header's changes and the switch between the file and its diff.
    let model = ViewerModel()
    /// Showing the session page rather than a file (`showSession`).
    private(set) var isSessionPage = false

    init(container: NSView) {
        self.container = container
        super.init()
        findMessages.viewer = self
        wireFind()
    }

    var isShowing: Bool {
        root != nil
    }

    /// A file to show, and where it's opened from.
    struct Opening {
        var path: String
        /// The line a link pointed at, highlighted in code.
        var line: Int?
        /// The session it's opened over; going to another one leaves the file.
        var session: Session.ID?
        /// The session's project, which the header's folder is relative to.
        var projectRoot: String?
        /// From the files column's Changes: a changed file opens on its unified diff.
        var preferDiff = false
    }

    /// Shows a file over `area` (the terminal area, under the title strip), and keeps it there
    /// while the sidebar or the files column slides. `background` is the terminal's, so the file
    /// takes the session's place on the same surface. Returns false if Calm can't show it.
    @discardableResult
    func show(
        _ opening: Opening,
        over area: NSView,
        background: NSColor,
        style: SidebarStyle,
        onClose: @escaping () -> Void,
    ) -> Bool {
        let path = opening.path
        let background = background.withAlphaComponent(1)
        guard let container, let kind = ViewableKind.of(path),
              let (content, render) = makeContent(kind, path: path, line: opening.line, background: background, style: style)
        else {
            return false
        }
        hide(animated: false)
        // Calm's page takes the file once it has loaded; an HTML file or an SVG loads as it is.
        pendingScripts = render.map { [$0] } ?? []
        pageLoaded = false
        self.onClose = onClose
        file = path
        session = opening.session
        find.reset(for: Self.searcher(for: kind, path: path))
        model.change = .unchanged
        model.mode = .file
        present(content, header: ViewerHeader(
            name: (path as NSString).lastPathComponent,
            folder: Self.folder(of: path, in: opening.projectRoot),
            detail: Self.detail(kind, path: path),
            openTitle: Self.openTitle(kind, path: path),
            style: style,
            model: model,
            find: find,
            onMode: { [weak self] mode in self?.setMode(mode) },
            onOpen: { [weak self] in self?.open(kind, line: opening.line) },
            onBack: { [weak self] in self?.close() },
        ), over: area, background: background)
        switch kind {
        case .markdown, .code, .text:
            readChanges(of: path, preferDiff: opening.preferDiff)
        case .html, .image, .pdf:
            break
        }
        return true
    }

    /// What the session page shows (FEATURES.md → F16, the whole session).
    struct SessionOpening {
        var page: SessionPage
        /// "Claude Code · since 14:02 · 1,240 lines"
        var detail: String
        /// The session it's opened over; going to another one leaves it.
        var session: Session.ID?
        /// The terminal's font, so the lines read as they did there; nil for the page's own.
        var fontFamily: String?
        var fontSize: Double
    }

    /// Shows what the session showed in Calm's page, over the terminal area as a file is shown,
    /// the newest lines in view. Its find field has Screen | Session with Session chosen: Screen
    /// and esc go back to the live program (the window's `find.onScreen`).
    func showSession(
        _ opening: SessionOpening,
        over area: NSView,
        background: NSColor,
        style: SidebarStyle,
        onClose: @escaping () -> Void,
    ) {
        guard let pageURL = Bundle.main.url(forResource: "viewer", withExtension: "html", subdirectory: "Viewer") else { return }
        let background = background.withAlphaComponent(1)
        hide(animated: false)
        let web = makeWebView()
        web.configuration.userContentController.add(findMessages, name: "calmFind")
        web.loadFileURL(pageURL, allowingReadAccessTo: pageURL.deletingLastPathComponent())
        pendingScripts = [Self.sessionScript(opening, background: background, style: style)]
        pageLoaded = false
        self.onClose = onClose
        session = opening.session
        isSessionPage = true
        find.reset(for: .page, session: true)
        model.change = .unchanged
        model.mode = .file
        present(web, header: ViewerHeader(
            name: "What this session showed",
            folder: opening.detail,
            detail: nil,
            openTitle: nil,
            style: style,
            model: model,
            find: find,
            onMode: { _ in },
            onOpen: {},
            onBack: { [weak self] in self?.find.onScreen?() },
        ), over: area, background: background)
    }

    /// Puts `content` under `header` over `area`, on the terminal's `background`.
    private func present(_ content: NSView, header headerView: ViewerHeader, over area: NSView, background: NSColor) {
        guard let container else { return }
        presence.isShowing = true
        // The header and content follow the root's size by autoresizing; the root itself is pinned
        // below to the area's edges.
        let frame = area.frame
        let root = NSView(frame: frame)
        root.translatesAutoresizingMaskIntoConstraints = false
        root.wantsLayer = true
        root.layer?.backgroundColor = background.cgColor
        root.layer?.cornerRadius = cornerRadius
        root.layer?.cornerCurve = .continuous
        root.layer?.masksToBounds = cornerRadius > 0
        // A card's edge, which the root would otherwise cover.
        root.layer?.borderWidth = area.layer?.borderWidth ?? 0
        root.layer?.borderColor = area.layer?.borderColor

        let headerHeight = 40.scaled
        let header = NSHostingView(rootView: headerView)
        header.safeAreaRegions = []
        header.frame = NSRect(x: 0, y: frame.height - headerHeight, width: frame.width, height: headerHeight)
        header.autoresizingMask = [.width, .minYMargin]
        content.frame = NSRect(x: 0, y: 0, width: frame.width, height: frame.height - headerHeight)
        content.autoresizingMask = [.width, .height]
        root.addSubview(content)
        root.addSubview(header)
        container.addSubview(root, positioned: .above, relativeTo: nil)
        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: area.leadingAnchor),
            root.trailingAnchor.constraint(equalTo: area.trailingAnchor),
            root.topAnchor.constraint(equalTo: area.topAnchor),
            root.bottomAnchor.constraint(equalTo: area.bottomAnchor),
        ])
        self.root = root
        Motion.fadeIn(root, duration: 0.16)

        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .leftMouseDown]) { [weak self] event in
            guard let self, event.window === container.window else { return event }
            find.hidePictureNote()
            return event.type == .keyDown && handleKey(event) ? nil : event
        }
    }

    /// The viewer's keys, ahead of the terminal under it: esc closes find first, then the viewer;
    /// ⌘F, ⌘G, ⌘⇧G and ⌘E find in the file (FEATURES.md → F16).
    private func handleKey(_ event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask).subtracting([.capsLock, .numericPad, .function])
        if event.keyCode == 53, modifiers.isEmpty {
            if isSessionPage {
                find.onScreen?()
            } else if find.isOpen {
                find.close()
            } else {
                close()
            }
            return true
        }
        guard modifiers == .command || modifiers == [.command, .shift] else { return false }
        switch event.charactersIgnoringModifiers?.lowercased() {
        case "f" where modifiers == .command:
            find.toggle()
        case "g" where find.isOpen:
            find.step(up: modifiers.contains(.shift))
        case "e" where modifiers == .command:
            findSelection()
        default:
            return false
        }
        return true
    }

    /// ⌘E: the words selected in the file become find's.
    func findSelection() {
        if find.searcher == .pdf {
            find.toggle(words: pdfView?.currentSelection?.string ?? "")
            return
        }
        webView?.evaluateJavaScript("window.getSelection().toString()") { [weak self] result, _ in
            let words = (result as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            MainActor.assumeIsolated { self?.find.toggle(words: words) }
        }
    }

    private static func searcher(for kind: ViewableKind, path: String) -> ViewerFindModel.Searcher {
        switch kind {
        case .markdown, .code, .text: .page
        case .pdf: .pdf
        case .html: .web
        case .image: URL(filePath: path).pathExtension.lowercased() == "svg" ? .web : .picture
        }
    }

    func close() {
        hide(animated: true)
        onClose?()
        onClose = nil
    }

    private func hide(animated: Bool) {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
        }
        keyMonitor = nil
        reading?.cancel()
        reading = nil
        file = nil
        session = nil
        isSessionPage = false
        pdfMatches = []
        pdfMarks = []
        find.reset(for: .page)
        presence.isShowing = false
        guard let root else { return }
        self.root = nil
        if animated {
            Motion.fadeOutAndRemove(root, duration: 0.14)
        } else {
            root.removeFromSuperview()
        }
    }

    private func open(_ kind: ViewableKind, line: Int?) {
        guard let file else { return }
        switch kind {
        case .image, .pdf:
            LinkOpener.openInDefaultApp(file)
        default:
            LinkOpener.openInEditor(file, line: line, column: nil)
        }
    }

    // MARK: Changes

    /// Reads what git says about the file off the main thread; the header's `+3 −3` and switch,
    /// and the page's marks, appear when it answers.
    private func readChanges(of path: String, preferDiff: Bool) {
        reading = Task { [weak self] in
            let change = await Task.detached(priority: .userInitiated) { ViewerChange.read(path) }.value
            guard let self, !Task.isCancelled, file == path else { return }
            model.change = change
            if let payload = change.pagePayload {
                runScript(Self.call("calmSetChanges", payload))
                if preferDiff {
                    setMode(.unified)
                }
            }
        }
    }

    func setMode(_ mode: ViewerModel.Mode) {
        guard case .changed = model.change, model.mode != mode else { return }
        model.mode = mode
        runScript("calmSetMode(\"\(mode.rawValue)\")")
    }

    private func runScript(_ script: String) {
        if pageLoaded, let webView {
            webView.evaluateJavaScript(script)
        } else {
            pendingScripts.append(script)
        }
    }

    private static func call(_ function: String, _ argument: [String: Any]) -> String {
        let json = (try? JSONSerialization.data(withJSONObject: argument)).flatMap { String(bytes: $0, encoding: .utf8) } ?? "{}"
        return "\(function)(\(json))"
    }

    // MARK: Header

    /// The file's folder relative to the session's project when it's inside it (nil at its top),
    /// else with `~` for home.
    static func folder(of path: String, in projectRoot: String?) -> String? {
        let folder = (path as NSString).deletingLastPathComponent
        if let projectRoot {
            let root = projectRoot.hasSuffix("/") ? String(projectRoot.dropLast()) : projectRoot
            if folder == root {
                return nil
            }
            if folder.hasPrefix(root + "/") {
                return String(folder.dropFirst(root.count + 1))
            }
        }
        return (folder as NSString).abbreviatingWithTildeInPath
    }

    /// What a picture or a PDF is: "PNG · 2000 × 302 · 84 KB", "PDF · 6 pages".
    private static func detail(_ kind: ViewableKind, path: String) -> String? {
        let url = URL(filePath: path)
        let type = url.pathExtension.uppercased()
        switch kind {
        case .image:
            var parts = [type]
            if let rep = NSImage(contentsOf: url)?.representations.first, rep.pixelsWide > 0 {
                parts.append("\(rep.pixelsWide) × \(rep.pixelsHigh)")
            }
            if let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                parts.append(ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file))
            }
            return parts.joined(separator: " · ")
        case .pdf:
            guard let pages = PDFDocument(url: url)?.pageCount else { return type }
            return "\(type) · \(pages) page\(pages == 1 ? "" : "s")"
        default:
            return nil
        }
    }

    /// Code goes to the editor; a picture or a PDF to the app macOS opens it with.
    private static func openTitle(_ kind: ViewableKind, path: String) -> String {
        switch kind {
        case .image, .pdf:
            guard let app = NSWorkspace.shared.urlForApplication(toOpen: URL(filePath: path)) else { return "Open" }
            return "Open in \(FileManager.default.displayName(atPath: app.path).replacingOccurrences(of: ".app", with: ""))"
        default:
            return "Open in Editor"
        }
    }

    // MARK: Content

    /// The view for `path`, and for Calm's own page the script that renders the file in it.
    private func makeContent(
        _ kind: ViewableKind, path: String, line: Int?, background: NSColor, style: SidebarStyle,
    ) -> (NSView, String?)? {
        let url = URL(filePath: path)
        switch kind {
        case .pdf:
            guard let document = PDFDocument(url: url) else { return nil }
            let view = PDFView()
            view.document = document
            view.autoScales = true
            view.backgroundColor = background
            pdfView = view
            return (view, nil)
        case .image where url.pathExtension.lowercased() != "svg":
            guard let image = NSImage(contentsOf: url) else { return nil }
            let view = NSImageView(image: image)
            view.imageScaling = .scaleProportionallyDown
            return (view, nil)
        case .html, .image:
            let web = makeWebView()
            web.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
            return (web, nil)
        case .markdown, .code, .text:
            guard let text = try? String(contentsOf: url, encoding: .utf8),
                  let page = Bundle.main.url(forResource: "viewer", withExtension: "html", subdirectory: "Viewer")
            else { return nil }
            let web = makeWebView()
            // The map in Calm's page tells the field when a click on a tick changes the current match.
            web.configuration.userContentController.add(findMessages, name: "calmFind")
            web.loadFileURL(page, allowingReadAccessTo: page.deletingLastPathComponent())
            return (web, Self.renderScript(kind: kind, text: text, line: line, background: background, style: style))
        }
    }

    private func makeWebView() -> WKWebView {
        let web = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
        web.navigationDelegate = self
        web.setValue(false, forKey: "drawsBackground") // no white flash before the page's colors
        webView = web
        return web
    }

    #if DEBUG
        /// The page's rendered text, read through the DOM: works when nothing can be painted (a
        /// headless run with the display asleep).
        func renderedTextForTesting() async -> String? {
            try? await webView?.evaluateJavaScript("document.body.innerText") as? String
        }

        /// What the header shows and the page drew, for a self-test's log.
        func stateForTesting() async -> String {
            let lines = model.change.lines.map { "+\($0.added) −\($0.deleted)" } ?? "\(model.change == .new ? "new" : "unchanged")"
            let script = "[document.querySelectorAll('.l.add,.l.mod').length, document.querySelectorAll('.r.del,.r.add').length].join(' ')"
            let page = await (try? webView?.evaluateJavaScript(script) as? String) ?? "no page"
            return "change \(lines), mode \(model.mode.rawValue), marks and diff rows \(page)"
        }
    #endif

    /// The page's lines, each with the time mark before it if it starts a part, in the terminal's font.
    private static func sessionScript(_ opening: SessionOpening, background: NSColor, style: SidebarStyle) -> String {
        let lines: [[String: String]] = opening.page.lines.map { line in
            var item = ["t": line.text]
            if let mark = line.mark {
                item["m"] = clock(mark)
            }
            return item
        }
        return call("calmRender", [
            "kind": "session",
            "lines": lines,
            "colors": style.viewerColors(background: background),
            "gutter": Double(ViewerHeader.leading),
            "font": opening.fontFamily ?? "",
            "fontSize": opening.fontSize,
        ])
    }

    /// A time as the system shows it ("14:02", or "2:02 PM"), with the day when it isn't today.
    static func clock(_ date: Date) -> String {
        Calendar.current.isDateInToday(date)
            ? date.formatted(date: .omitted, time: .shortened)
            : date.formatted(.dateTime.month(.abbreviated).day().hour().minute())
    }

    private static func renderScript(kind: ViewableKind, text: String, line: Int?, background: NSColor, style: SidebarStyle) -> String {
        var document: [String: Any] = [
            "text": text,
            "colors": style.viewerColors(background: background),
            "gutter": Double(ViewerHeader.leading),
        ]
        switch kind {
        case .markdown: document["kind"] = "markdown"
        case let .code(language):
            document["kind"] = "code"
            document["language"] = language ?? ""
        default: document["kind"] = "text"
        }
        if let line {
            document["line"] = line
        }
        return call("calmRender", document)
    }
}

extension FileViewer: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didFinish _: WKNavigation!) {
        pageLoaded = true
        for script in pendingScripts {
            webView.evaluateJavaScript(script)
        }
        pendingScripts = []
        // Find opened before the page could search (the session page opens with the words).
        if find.isOpen, !find.query.isEmpty {
            find.onSearch?(find.query)
        }
    }

    /// Links in a viewed file: web links open in the browser, local files in the viewer or outside.
    func webView(
        _: WKWebView,
        decidePolicyFor action: WKNavigationAction,
        decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void,
    ) {
        guard action.navigationType == .linkActivated, let url = action.request.url else {
            decisionHandler(.allow)
            return
        }
        decisionHandler(.cancel)
        let directory = file.map { ($0 as NSString).deletingLastPathComponent }
        LinkOpener.open(url.isFileURL ? url.path : url.absoluteString, directory: directory, projectDirectory: nil)
    }
}

extension SidebarStyle {
    /// CSS colors for the viewer page, from the same palette as the chrome, on `background` (the
    /// terminal's, which the viewer takes the place of).
    func viewerColors(background: NSColor) -> [String: String] {
        func css(_ color: Color) -> String {
            let resolved = NSColor(color).usingColorSpace(.sRGB) ?? .gray
            return String(
                format: "rgba(%d, %d, %d, %.3f)",
                Int(resolved.redComponent * 255), Int(resolved.greenComponent * 255), Int(resolved.blueComponent * 255),
                resolved.alphaComponent,
            )
        }
        return [
            "bg": css(Color(nsColor: background)), "fg": css(primary), "muted": css(secondary), "faint": css(tertiary),
            "line": css(tertiary.opacity(0.35)), "code-bg": css(selection), "mark": css(accent.opacity(0.18)),
            "added": css(done), "removed": css(failure), "modified": css(accent),
        ]
    }
}

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

/// The file viewer (FEATURES.md → F10): a viewable file covers the terminal area; esc returns to
/// the session exactly as it was (it keeps running underneath).
@MainActor
final class FileViewer: NSObject {
    private weak var container: NSView?
    private var root: NSView?
    private var keyMonitor: Any?
    private var onClose: (() -> Void)?
    private var pendingRender: String?
    private weak var webView: WKWebView?
    private(set) var file: String?
    /// The session the file was opened over; going to another one leaves the file.
    private(set) var session: Session.ID?
    /// Matches the terminal area's corners (a card window rounds them).
    var cornerRadius: CGFloat = 0

    init(container: NSView) {
        self.container = container
    }

    var isShowing: Bool {
        root != nil
    }

    /// Shows `path` over `area` (the terminal area), and keeps it there while the sidebar or the
    /// files column slides. Returns false if Calm can't show it.
    @discardableResult
    func show(
        _ path: String,
        line: Int?,
        over area: NSView,
        session: Session.ID?,
        sessionTitle: String,
        style: SidebarStyle,
        onClose: @escaping () -> Void,
    ) -> Bool {
        guard let container, let kind = ViewableKind.of(path), let content = makeContent(kind, path: path, line: line, style: style) else {
            return false
        }
        hide(animated: false)
        self.onClose = onClose
        file = path
        self.session = session
        // The header and content follow the root's size by autoresizing; the root itself is pinned
        // below to the area's sides and to the window's top and bottom, over the title strip.
        let frame = NSRect(x: area.frame.minX, y: 0, width: area.frame.width, height: container.bounds.height)
        let root = NSView(frame: frame)
        root.translatesAutoresizingMaskIntoConstraints = false
        root.wantsLayer = true
        root.layer?.backgroundColor = NSColor(style.background).cgColor
        root.layer?.cornerRadius = cornerRadius
        root.layer?.cornerCurve = .continuous
        root.layer?.masksToBounds = cornerRadius > 0

        let headerHeight: CGFloat = 46
        let header = NSHostingView(rootView: ViewerHeader(
            path: path, sessionTitle: sessionTitle, style: style,
            onOpenInEditor: { [weak self] in self?.openInEditor(line: line) },
            onBack: { [weak self] in self?.close() },
        ))
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
            root.topAnchor.constraint(equalTo: container.topAnchor),
            root.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        self.root = root
        Motion.fadeIn(root, duration: 0.16)

        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, event.keyCode == 53, event.window === container.window else { return event }
            close()
            return nil
        }
        return true
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
        file = nil
        session = nil
        guard let root else { return }
        self.root = nil
        if animated {
            Motion.fadeOutAndRemove(root, duration: 0.14)
        } else {
            root.removeFromSuperview()
        }
    }

    private func openInEditor(line: Int?) {
        guard let file else { return }
        LinkOpener.openInEditor(file, line: line, column: nil)
    }

    // MARK: Content

    private func makeContent(_ kind: ViewableKind, path: String, line: Int?, style: SidebarStyle) -> NSView? {
        let url = URL(filePath: path)
        switch kind {
        case .pdf:
            guard let document = PDFDocument(url: url) else { return nil }
            let view = PDFView()
            view.document = document
            view.autoScales = true
            view.backgroundColor = NSColor(style.background)
            return view
        case .image where url.pathExtension.lowercased() != "svg":
            guard let image = NSImage(contentsOf: url) else { return nil }
            let view = NSImageView(image: image)
            view.imageScaling = .scaleProportionallyDown
            return view
        case .html, .image:
            let web = makeWebView()
            web.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
            return web
        case .markdown, .code, .text:
            guard let text = try? String(contentsOf: url, encoding: .utf8),
                  let page = Bundle.main.url(forResource: "viewer", withExtension: "html", subdirectory: "Viewer")
            else { return nil }
            let web = makeWebView()
            pendingRender = Self.renderScript(kind: kind, text: text, line: line, style: style)
            web.loadFileURL(page, allowingReadAccessTo: page.deletingLastPathComponent())
            return web
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
    #endif

    private static func renderScript(kind: ViewableKind, text: String, line: Int?, style: SidebarStyle) -> String {
        var document: [String: Any] = ["text": text, "colors": style.viewerColors]
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
        let json = (try? JSONSerialization.data(withJSONObject: document)).flatMap { String(bytes: $0, encoding: .utf8) } ?? "{}"
        return "calmRender(\(json))"
    }
}

extension FileViewer: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didFinish _: WKNavigation!) {
        if let script = pendingRender {
            pendingRender = nil
            webView.evaluateJavaScript(script)
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

struct ViewerHeader: View {
    let path: String
    let sessionTitle: String
    let style: SidebarStyle
    let onOpenInEditor: () -> Void
    let onBack: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text((path as NSString).lastPathComponent)
                    .calmFont(size: 13, weight: .medium)
                    .foregroundStyle(style.primary)
                Text((path as NSString).abbreviatingWithTildeInPath)
                    .calmFont(size: 11)
                    .foregroundStyle(style.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 12)
            Button("Open in Editor", action: onOpenInEditor)
                .controlSize(.small)
            Button(action: onBack) {
                Text("esc · Back to \(sessionTitle)")
                    .calmFont(size: 11)
                    .foregroundStyle(style.secondary)
                    .lineLimit(1)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(style.background)
        .overlay(alignment: .bottom) { Rectangle().fill(style.tertiary.opacity(0.2)).frame(height: 1) }
        .environment(\.colorScheme, style.isDark ? .dark : .light)
    }
}

extension SidebarStyle {
    /// CSS colors for the viewer page, from the same palette as the chrome.
    var viewerColors: [String: String] {
        func css(_ color: Color) -> String {
            let resolved = NSColor(color).usingColorSpace(.sRGB) ?? .gray
            return String(
                format: "rgba(%d, %d, %d, %.3f)",
                Int(resolved.redComponent * 255), Int(resolved.greenComponent * 255), Int(resolved.blueComponent * 255),
                resolved.alphaComponent,
            )
        }
        return [
            "bg": css(background), "fg": css(primary), "muted": css(secondary), "faint": css(tertiary),
            "line": css(tertiary.opacity(0.35)), "code-bg": css(selection), "mark": css(accent.opacity(0.18)),
        ]
    }
}

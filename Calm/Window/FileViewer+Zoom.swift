import AppKit
import CalmModel
import PDFKit
import WebKit

/// What ⌘+ and ⌘− size in the viewer, by what it shows (FEATURES.md → F10).
enum ViewerZoomTarget {
    /// The web view: a page of text, whose size is kept for the next one when `remembered` (a
    /// file's, not the session page's), or an SVG.
    case web(ViewerZoom.Kind, remembered: Bool)
    case pdf
    case picture

    init(_ kind: ViewableKind, path: String) {
        switch kind {
        case .markdown, .code, .text, .html: self = .web(.page, remembered: true)
        case .pdf: self = .pdf
        case .image: self = URL(filePath: path).pathExtension.lowercased() == "svg" ? .web(.picture, remembered: false) : .picture
        }
    }
}

// MARK: Size

extension FileViewer {
    /// A page of text opens at the size files are read at; anything else at its own.
    func startZoom(_ target: ViewerZoomTarget) {
        zoomTarget = target
        model.zoomHovered = false
        switch target {
        case let .web(_, remembered):
            guard let webView else { break }
            webZoom = remembered ? SessionManager.shared.workspace.viewerZoom ?? 1 : 1
            webView.pageZoom = webZoom
            if webZoom != 1 {
                runScript(Self.zoomedScript(webZoom))
            }
        case .pdf:
            observeZoom(.PDFViewScaleChanged, of: pdfView)
        case .picture:
            observeZoom(NSScrollView.didEndLiveMagnifyNotification, of: pictureView)
        }
        model.zoom = currentZoom
    }

    /// Nothing shows: no size, nothing to follow.
    func stopZoom() {
        zoomTarget = nil
        webZoom = 1
        for observer in zoomObservers {
            NotificationCenter.default.removeObserver(observer)
        }
        zoomObservers = []
        model.zoom = 1
        model.zoomHovered = false
    }

    /// The row's size follows what the viewer shows, and fades as it comes or goes.
    func noteZoom() {
        let zoom = currentZoom
        guard abs(zoom - model.zoom) > 0.0005 else { return }
        Motion.animate(.easeOut(duration: 0.16)) { model.zoom = zoom }
    }

    private var currentZoom: Double {
        switch zoomTarget {
        case .web: webZoom
        case .pdf: pdfView.map { $0.autoScales ? 1 : Double($0.scaleFactor / max($0.scaleFactorForSizeToFit, 0.0001)) } ?? 1
        case .picture: pictureView.map { Double($0.magnification) } ?? 1
        case nil: 1
        }
    }

    /// A PDF's scale or a picture's magnification changed by itself (a pinch).
    private func observeZoom(_ name: Notification.Name, of object: AnyObject?) {
        guard let object else { return }
        zoomObservers.append(NotificationCenter.default.addObserver(forName: name, object: object, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.noteZoom() }
        })
    }

    /// ⌘+ (`bigger`), ⌘− or ⌘0 (nil) while something shows: it grows or shrinks, not the terminal
    /// under it (FEATURES.md → F10). A page of text keeps its size for the next one, and the next
    /// launch; a picture or a PDF starts fitted again.
    func zoom(bigger: Bool?) {
        switch zoomTarget {
        case let .web(kind, remembered):
            let next = bigger.map { ViewerZoom.step(webZoom, bigger: $0, kind: kind) } ?? 1
            guard next != webZoom, let webView else { return }
            webZoom = next
            // WebKit keeps the scroll offset, which the page laid out at another size puts
            // somewhere else; these two keep what's at the top of the view there. They and the
            // zoom reach the page in order, over the same connection.
            if pageLoaded {
                webView.evaluateJavaScript(Self.zoomAnchorScript)
            }
            webView.pageZoom = next
            runScript(Self.zoomedScript(next))
            if remembered {
                let manager = SessionManager.shared
                if manager.changeWorkspace({ _ = $0.noteViewerZoom(next) }) {
                    manager.scheduleSave()
                }
            }
        case .pdf:
            pdfView.map { Self.zoom($0, bigger: bigger) }
        case .picture:
            pictureView?.zoom(bigger: bigger)
        case nil:
            break
        }
        noteZoom()
    }

    /// A PDF sized against the scale that fits its width (what `autoScales` keeps), and fitted
    /// again on ⌘0.
    private static func zoom(_ view: PDFView, bigger: Bool?) {
        guard let bigger else {
            view.autoScales = true
            return
        }
        let fit = view.scaleFactorForSizeToFit
        guard fit > 0 else { return }
        let next = ViewerZoom.step(view.scaleFactor / fit, bigger: bigger, kind: .picture)
        let steps = ViewerZoom.Kind.picture.steps
        view.minScaleFactor = min(view.minScaleFactor, fit * steps[0])
        view.maxScaleFactor = max(view.maxScaleFactor, fit * steps[steps.count - 1])
        view.autoScales = false
        view.scaleFactor = fit * next
    }

    /// Before the page changes size: the element at the top of the view and how far into it the
    /// view starts (or, with nothing to hold on to, how far down the page). Works in any page.
    private static let zoomAnchorScript = """
    (() => {
      const root = document.scrollingElement || document.documentElement;
      window.__calmZoomAnchor = null;
      if (root.scrollTop <= 0) return;
      const skip = (element) => !element || element === document.body || element === document.documentElement
        || element.id === "content" || element.closest("#calm-find-map");
      for (const y of [1, 8, 16, 32, 64]) {
        for (const x of [innerWidth / 2, innerWidth / 3, innerWidth * 2 / 3, 60]) {
          const element = document.elementFromPoint(x, y);
          if (skip(element)) continue;
          const box = element.getBoundingClientRect();
          if (box.height <= 0) continue;
          window.__calmZoomAnchor = { element, into: -box.top / box.height };
          return;
        }
      }
      window.__calmZoomAnchor = { fraction: root.scrollTop / Math.max(root.scrollHeight - innerHeight, 1) };
    })();
    """

    /// After it changed: Calm's page keeps its gutter and find map at their size on screen, then
    /// the view goes back to what was at its top.
    private static func zoomedScript(_ zoom: Double) -> String {
        """
        (() => {
          window.calmSetZoom?.(\(zoom));
          const anchor = window.__calmZoomAnchor;
          window.__calmZoomAnchor = null;
          if (!anchor) return;
          const root = document.scrollingElement || document.documentElement;
          if (anchor.element?.isConnected) {
            const box = anchor.element.getBoundingClientRect();
            window.scrollBy(0, box.top + anchor.into * box.height);
          } else if (anchor.fraction !== undefined) {
            window.scrollTo(0, anchor.fraction * Math.max(root.scrollHeight - innerHeight, 1));
          }
        })();
        """
    }

    #if DEBUG
        /// How big the viewer shows what it shows, and for a page what's at the top of its view.
        func zoomStateForTesting() async -> String {
            let shown = ViewerZoom.showsSize(model.zoom, hovered: model.zoomHovered || model.zoomHoverForTesting)
            let row = shown ? ViewerZoom.percent(model.zoom) : "nothing"
            let saved = "row says \(row), saved \(SessionManager.shared.workspace.viewerZoom ?? 1)"
            switch zoomTarget {
            case .web:
                let script = """
                JSON.stringify({ y: Math.round(scrollY), width: innerWidth,
                  gutter: getComputedStyle(document.documentElement).getPropertyValue("--gutter").trim(),
                  top: ((document.elementFromPoint(innerWidth / 2, 4) || {}).textContent || "").trim().slice(0, 48) })
                """
                let page = await (try? webView?.evaluateJavaScript(script) as? String) ?? "no page"
                return "web \(webZoom) pageZoom \(webView?.pageZoom ?? 0) \(saved) page \(page)"
            case .pdf:
                guard let pdfView else { return "pdf none" }
                let relative = pdfView.scaleFactor / max(pdfView.scaleFactorForSizeToFit, 0.0001)
                return String(format: "pdf %.2f of fit, autoScales %@, %@", relative, "\(pdfView.autoScales)", saved)
            case .picture:
                guard let pictureView else { return "picture none" }
                return "picture magnification \(pictureView.magnification) image \(pictureView.documentView?.frame.size ?? .zero) \(saved)"
            case nil:
                return "nothing shown"
            }
        }
    #endif
}

import AppKit
import CalmModel
import Observation
import PDFKit
import WebKit

/// Find in a viewed file (FEATURES.md → F16, F10): the field in the viewer's header and what it
/// found. The viewer does the searching, each kind of file its own way (`FileViewer`): Calm's own
/// page marks and counts in the page, PDFKit searches a PDF, and an HTML or SVG file gets the web
/// view's find, which has no count. A picture has nothing to find.
@MainActor
@Observable
final class ViewerFindModel: FindFieldModel {
    enum Searcher {
        /// Calm's own page (Markdown, code, text): counts, marks and a map in the page.
        case page
        /// A PDF, through PDFKit: counts; the current match is PDFKit's selection.
        case pdf
        /// An HTML or SVG file in the web view: its find says only whether there is a match.
        case web
        /// A picture: nothing to find.
        case picture
    }

    private(set) var isOpen = false
    var query = "" {
        didSet {
            if isOpen, query != oldValue {
                found = nil // the web view's answer was for the old words
                onSearch?(query)
            }
        }
    }

    private(set) var total: Int?
    private(set) var current: Int?
    private(set) var isPattern = false
    /// The words aren't a pattern (yet): the count says so, and the page keeps its marks.
    private(set) var isPatternIncomplete = false
    /// The web view's answer, for a page whose find has no count.
    private(set) var found: Bool?
    /// The quiet note for ⌘F over a picture, until the next key or click.
    private(set) var showsPictureNote = false
    private(set) var focusRequest = 0
    var fieldFrame: CGRect?
    @ObservationIgnored var searcher: Searcher = .page
    @ObservationIgnored var onSearch: ((String) -> Void)?
    @ObservationIgnored var onStep: ((Bool) -> Void)?
    @ObservationIgnored var onClose: (() -> Void)?
    /// The viewer shows the session page (FEATURES.md → F16): Screen | Session shows, Session chosen.
    private(set) var showsScope = false
    /// Screen chosen on the session page: the window goes back to the live program.
    @ObservationIgnored var onScreen: (() -> Void)?

    var placeholder: String {
        showsScope ? "Find in this session" : "Find in this file"
    }

    var isSession: Bool {
        showsScope
    }

    func setScope(session: Bool) {
        if !session, showsScope {
            onScreen?()
        }
    }

    var countText: String {
        guard !query.isEmpty else { return "" }
        if isPatternIncomplete, supportsPattern {
            return "Incomplete pattern"
        }
        if searcher == .web {
            return found == false ? "No matches" : ""
        }
        guard let total else { return "" }
        guard total > 0 else { return "No matches" }
        guard let current else { return total == 1 ? "1 match" : "\(total) matches" }
        return "\(current + 1) of \(total)"
    }

    /// Down the file is forward: ↵ and ↓ go to the next match, ⇧↵ and ↑ to the one before.
    var upDisabled: Bool {
        if isPatternIncomplete, supportsPattern {
            return true
        }
        if searcher == .web {
            return found != true
        }
        guard let total, total > 0, let current else { return true }
        return current <= 0
    }

    var downDisabled: Bool {
        if isPatternIncomplete, supportsPattern {
            return true
        }
        if searcher == .web {
            return found != true
        }
        guard let total, total > 0, let current else { return true }
        return current >= total - 1
    }

    var upHelp: String {
        "Previous match (⇧↵ or ⌘⇧G)"
    }

    var downHelp: String {
        "Next match (↵ or ⌘G)"
    }

    var returnStepsUp: Bool {
        false
    }

    /// Calm's own page takes patterns; PDFKit and the web view's find take plain words only.
    var supportsPattern: Bool {
        searcher == .page
    }

    /// The page searches with a pattern only while the switch shows.
    var searchesPattern: Bool {
        isPattern && supportsPattern
    }

    func togglePattern() {
        guard supportsPattern else { return }
        isPattern.toggle()
        if isOpen {
            onSearch?(query)
        }
    }

    /// ⌘F: opens the field with the last words selected (a picture gets its note instead), or
    /// closes it; `words` (⌘E) replaces them.
    func toggle(words: String? = nil) {
        if searcher == .picture {
            showsPictureNote = true
            return
        }
        if isOpen, words == nil {
            close()
            return
        }
        isOpen = true
        focusRequest += 1
        if let words, !words.isEmpty {
            // ⌘E: the selected text is words, never a pattern.
            isPattern = false
            if words != query {
                query = words
                return
            }
        }
        if !query.isEmpty {
            onSearch?(query)
        }
    }

    func step(up: Bool) {
        guard isOpen, !query.isEmpty else { return }
        onStep?(up)
    }

    func close() {
        guard isOpen else { return }
        isOpen = false
        total = nil
        current = nil
        found = nil
        onClose?()
    }

    func hidePictureNote() {
        showsPictureNote = false
    }

    /// Opens the field on the session page with the terminal's words, as they were.
    func open(words: String, isPattern: Bool) {
        self.isPattern = isPattern
        isOpen = true
        focusRequest += 1
        if words != query {
            query = words
        } else if !query.isEmpty {
            onSearch?(query)
        }
    }

    /// The viewer went away or showed another file (`session` for the session page): find starts
    /// over, keeping the words.
    func reset(for searcher: Searcher, session: Bool = false) {
        showsScope = session
        isOpen = false
        total = nil
        current = nil
        found = nil
        showsPictureNote = false
        self.searcher = searcher
    }

    /// What the page or PDFKit found.
    func show(total: Int?, current: Int?) {
        isPatternIncomplete = false
        self.total = total
        self.current = current.flatMap { $0 >= 0 ? $0 : nil }
    }

    /// The page couldn't read the words as a pattern: they're half typed.
    func showIncompletePattern() {
        isPatternIncomplete = true
    }

    /// What the web view's find said.
    func show(found: Bool) {
        self.found = found
    }
}

// MARK: Searching

extension FileViewer {
    /// The model's callbacks, for the kind of file shown.
    func wireFind() {
        find.onSearch = { [weak self] words in self?.search(words) }
        find.onStep = { [weak self] up in self?.step(up: up) }
        find.onClose = { [weak self] in
            guard let self else { return }
            // The session page is for finding: its find closing (⌘F, the cap) leaves it.
            if isSessionPage {
                close()
            } else {
                clearFind()
            }
        }
    }

    private func search(_ words: String) {
        switch find.searcher {
        case .page:
            runPage("calmFind(\(Self.json(words)), \(Self.json(pageColors)), \(find.searchesPattern))")
        case .pdf:
            searchPDF(words)
        case .web:
            searchWeb(words, backwards: false)
        case .picture:
            break
        }
    }

    private func step(up: Bool) {
        switch find.searcher {
        case .page:
            runPage("calmFindStep(\(up ? -1 : 1))")
        case .pdf:
            guard !pdfMatches.isEmpty, let current = find.current else { return }
            selectPDFMatch(min(max(current + (up ? -1 : 1), 0), pdfMatches.count - 1))
        case .web:
            searchWeb(find.query, backwards: up)
        case .picture:
            break
        }
    }

    func clearFind() {
        switch find.searcher {
        case .page:
            runPage("calmFindClose()")
        case .pdf:
            clearPDFMarks()
            pdfView?.clearSelection()
        case .web:
            // An empty search clears the web view's own highlight.
            webView?.find("", configuration: WKFindConfiguration()) { _ in }
        case .picture:
            break
        }
    }

    // MARK: Calm's page

    /// Runs a find function in the page and shows the count it returns.
    private func runPage(_ script: String) {
        webView?.evaluateJavaScript(script) { [weak self] result, _ in
            MainActor.assumeIsolated { self?.showPageResult(result) }
        }
    }

    func showPageResult(_ result: Any?) {
        // Closing gets an answer too (no matches); the field is gone by then.
        guard find.isOpen, let state = result as? [String: Any] else { return }
        if state["invalid"] as? Bool == true {
            find.showIncompletePattern()
            return
        }
        find.show(total: state["total"] as? Int, current: state["current"] as? Int)
    }

    /// The page's find colors as CSS: the solid accent, the band, the map's track, box and a lone
    /// tick's strength (FindColors).
    private var pageColors: [String: String] {
        guard let colors = findColors else { return [:] }
        let text = NSColor(hex: colors.foreground) ?? .textColor
        return [
            "find": colors.solid, "find-band": colors.band, "find-tick": String(colors.tickAlpha),
            "find-track": Self.css(text.withAlphaComponent(0.06)), "find-box": Self.css(text.withAlphaComponent(0.3)),
        ]
    }

    // MARK: PDF

    /// PDFKit finds the words; the current match is its selection, and every other is underlined
    /// with a temporary annotation in the accent the light theme takes on a white page.
    private func searchPDF(_ words: String) {
        clearPDFMarks()
        guard let pdfView, let document = pdfView.document, !words.isEmpty else {
            pdfMatches = []
            find.show(total: words.isEmpty ? nil : 0, current: nil)
            return
        }
        pdfMatches = document.findString(words, withOptions: .caseInsensitive)
        guard !pdfMatches.isEmpty else {
            find.show(total: 0, current: nil)
            return
        }
        let accent = NSColor(hex: FindColors.solid(accent: findColors?.solid ?? "#4c6f93", background: "#ffffff")) ?? .systemBlue
        pdfMarks = pdfMatches.map { match in
            match.selectionsByLine().flatMap { line in
                line.pages.map { page in
                    let underline = PDFAnnotation(bounds: line.bounds(for: page), forType: .underline, withProperties: nil)
                    underline.color = accent
                    page.addAnnotation(underline)
                    return (page, underline)
                }
            }
        }
        find.show(total: pdfMatches.count, current: nil) // no match of these words is current yet
        // The first match on the page in view, or after it.
        let visible = pdfView.currentPage.flatMap { document.index(for: $0) } ?? 0
        let first = pdfMatches.firstIndex { match in
            match.pages.first.map { document.index(for: $0) >= visible } ?? false
        } ?? 0
        selectPDFMatch(first)
    }

    private func selectPDFMatch(_ index: Int) {
        guard let pdfView, pdfMatches.indices.contains(index) else { return }
        // The current match wears PDFKit's selection instead of its underline.
        if let previous = find.current, pdfMarks.indices.contains(previous) {
            for (page, underline) in pdfMarks[previous] {
                page.addAnnotation(underline)
            }
        }
        if pdfMarks.indices.contains(index) {
            for (page, underline) in pdfMarks[index] {
                page.removeAnnotation(underline)
            }
        }
        let match = pdfMatches[index]
        pdfView.setCurrentSelection(match, animate: false)
        pdfView.go(to: match)
        find.show(total: pdfMatches.count, current: index)
    }

    private func clearPDFMarks() {
        for (page, underline) in pdfMarks.joined() {
            page.removeAnnotation(underline)
        }
        pdfMarks = []
    }

    // MARK: HTML and SVG

    /// The web view's own find, for a page Calm didn't make: it marks the match and scrolls to it,
    /// and says only whether there is one.
    private func searchWeb(_ words: String, backwards: Bool) {
        guard let webView, !words.isEmpty else { return }
        let configuration = WKFindConfiguration()
        configuration.backwards = backwards
        configuration.caseSensitive = false
        configuration.wraps = false
        webView.find(words, configuration: configuration) { [weak self] result in
            MainActor.assumeIsolated {
                // A step past the last match finds nothing more, but the words are still there.
                if result.matchFound || self?.find.found != true {
                    self?.find.show(found: result.matchFound)
                }
            }
        }
    }

    private static func json(_ value: Any) -> String {
        guard JSONSerialization.isValidJSONObject([value]),
              let data = try? JSONSerialization.data(withJSONObject: [value]),
              let text = String(bytes: data, encoding: .utf8) else { return "null" }
        return String(text.dropFirst().dropLast()) // the value alone, out of its array
    }

    private static func css(_ color: NSColor) -> String {
        let color = color.usingColorSpace(.sRGB) ?? color
        return String(
            format: "rgba(%d, %d, %d, %.3f)", Int(color.redComponent * 255), Int(color.greenComponent * 255),
            Int(color.blueComponent * 255), color.alphaComponent,
        )
    }
}

/// The page's map: a click on a tick changes the current match there, and the page tells the field.
final class ViewerFindMessages: NSObject, WKScriptMessageHandler {
    weak var viewer: FileViewer?

    func userContentController(_: WKUserContentController, didReceive message: WKScriptMessage) {
        let body = UncheckedSendable(message.body)
        MainActor.assumeIsolated { viewer?.showPageResult(body.value) }
    }
}

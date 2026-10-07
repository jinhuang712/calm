import CalmModel
import Foundation
import Observation

/// What find searches: a pane, through libghostty's search binding actions (DESIGNS.md → Find).
@MainActor
protocol FindTarget: AnyObject {
    var id: UUID { get }
    @discardableResult
    func perform(_ action: String) -> Bool
    /// What the pane marks: the words searched (nil for none), whether they're a pattern, and the
    /// current match, counted from the newest (FindMarksView).
    func markFind(_ words: String?, selected: Int?, isPattern: Bool)
}

/// What a pane tells its window about find (part of TerminalSurfaceHost).
@MainActor
protocol FindHost: AnyObject {
    /// libghostty's report about the pane's search (FEATURES.md → F16).
    func surface(_ view: TerminalSurfaceView, didFind event: FindEvent)
    /// A key without ⌘ went to the pane: typing closes find.
    func surfaceDidType(_ view: TerminalSurfaceView)
}

/// A pane is what find searches: its id, and libghostty's search binding actions.
extension TerminalSurfaceView: FindTarget {}

/// What libghostty reports about a pane's search.
enum FindEvent: Equatable {
    /// `start_search` (⌘F) with no words, or `search_selection` (⌘E) with the selected text.
    case start(needle: String)
    /// The search ended (`end_search`, ⌘⇧F, or Calm ending it).
    case end
    /// How many matches the screen has; nil while unknown.
    case total(Int?)
    /// Which match is the current one, counted from the newest (0); nil when none is.
    case selected(Int?)
    /// The pane shows a full-screen program's screen (true), which keeps no scrollback, or its
    /// own again (false). Reported by the pane, not libghostty (engine patch 0018).
    case fullScreen(Bool)
    /// How many matches a pattern has, which the pane counts itself: libghostty searches plain
    /// words only.
    case counted(Int)
    /// A pattern's match the pane chose (a click on its map), counted from the newest.
    case chose(Int)
}

/// Find in a session (FEATURES.md → F16): the title strip's field and the one pane it searches.
/// libghostty does the searching; this keeps what the field shows and turns its keys into
/// binding actions on the pane. One window has one; the pane that has the keyboard is searched.
@MainActor
@Observable
final class FindModel: FindFieldModel {
    enum Direction {
        /// ↵, ⌘G, the ↑ arrow: back in time. libghostty's `navigate_search:next` runs newest to oldest.
        case older
        /// ⇧↵, ⌘⇧G, the ↓ arrow.
        case newer
    }

    private(set) var isOpen = false
    /// What the field shows. Each change searches again, while find is open.
    var query = "" {
        didSet {
            if isOpen, query != oldValue {
                search()
            }
        }
    }

    private(set) var total: Int?
    private(set) var selected: Int?
    /// `.*`: the words are a pattern, which Calm searches itself (DESIGNS.md → Find, regular
    /// expressions).
    private(set) var isPattern = false
    /// The words aren't a pattern (yet): the count says so, and the marks stay as they were.
    private(set) var isPatternIncomplete = false
    /// The searched pane shows a full-screen program's screen, which keeps no scrollback, so only
    /// what's on it is searched and the count says so.
    private(set) var isFullScreen = false
    /// The agent running in the searched pane, by name, for the note; nil for any other program.
    var agentName: String?
    /// Where the field is in the title strip (top left origin), for the note under it.
    var fieldFrame: CGRect?
    /// Bumped to put the keyboard in the field, with what's in it selected.
    private(set) var focusRequest = 0

    @ObservationIgnored private(set) weak var target: FindTarget?
    /// Each pane's last words, so ⌘F there brings them back (selected, so typing replaces them).
    @ObservationIgnored private var lastQueries: [UUID: (words: String, isPattern: Bool)] = [:]
    /// Set by a new search: the first total selects the newest match, so the count reads "1 of N".
    @ObservationIgnored private var selectsNewest = false

    /// "3 of 11", "No matches", or nothing before the first count; in a full-screen program,
    /// "3 of 11 on screen" and "None on screen".
    var countText: String {
        if isPatternIncomplete, !query.isEmpty {
            return "Incomplete pattern"
        }
        guard !query.isEmpty, let total else { return "" }
        guard total > 0 else { return isFullScreen ? "None on screen" : "No matches" }
        guard let selected else {
            return isFullScreen ? "\(total) on screen" : total == 1 ? "1 match" : "\(total) matches"
        }
        return "\(min(selected, total - 1) + 1) of \(total)" + (isFullScreen ? " on screen" : "")
    }

    /// The note under the field: a full-screen program's screen has none of the words, and the
    /// rest of what it showed isn't in the terminal (UIUX.md → Find).
    var showsNote: Bool {
        isOpen && isFullScreen && !query.isEmpty && total == 0
    }

    /// What the note says: an agent keeps its conversation, which ⌘K searches; Calm knows only
    /// agents' names, so any other program is "this program".
    var noteText: String {
        agentName.map { "\($0) keeps the conversation, not the terminal." }
            ?? "This program draws its own screen, so only what's on it can be searched."
    }

    var placeholder: String {
        "Find in this session"
    }

    /// Up the scrollback is back in time: ↑ is the older match.
    var upDisabled: Bool {
        olderDisabled
    }

    var downDisabled: Bool {
        newerDisabled
    }

    var upHelp: String {
        "Older match (↵ or ⌘G)"
    }

    var downHelp: String {
        "Newer match (⇧↵ or ⌘⇧G)"
    }

    var returnStepsUp: Bool {
        true
    }

    func step(up: Bool) {
        step(up ? .older : .newer)
    }

    var supportsPattern: Bool {
        true
    }

    /// `.*` or ⌥⌘R: plain words or a pattern, searched again.
    func togglePattern() {
        isPattern.toggle()
        if isOpen {
            search()
        }
    }

    /// The oldest match is current (it stops there, no wrapping), or there's nothing to go to.
    var olderDisabled: Bool {
        guard let total, total > 0 else { return true }
        guard let selected else { return false }
        return selected >= total - 1
    }

    var newerDisabled: Bool {
        guard let total, total > 0, let selected else { return true }
        return selected <= 0
    }

    /// Whether `target` is the pane being searched.
    func isSearching(_ target: FindTarget) -> Bool {
        isOpen && self.target === target
    }

    /// libghostty's report about `target`'s search.
    func handle(_ event: FindEvent, from target: FindTarget) {
        switch event {
        case let .start(needle):
            if needle.isEmpty {
                // ⌘F again closes it, from the field or from the terminal.
                if isSearching(target) {
                    close()
                } else {
                    let last = lastQueries[target.id]
                    open(target, query: last?.words ?? "", isPattern: last?.isPattern ?? false)
                }
            } else {
                // ⌘E: the selected text is words, never a pattern.
                open(target, query: needle, isPattern: false)
            }
        case .end:
            // Ended without the field asking (⌘⇧F, the user's own binding): just put it away.
            if isSearching(target) {
                finish()
            }
        case let .total(total):
            // In a pattern's search libghostty only paints the current match; the pane counts.
            guard isSearching(target), !isPattern else { return }
            self.total = total
            if selectsNewest, let total, total > 0, selected == nil {
                selectsNewest = false
                target.perform("navigate_search:next")
            }
        case let .selected(index):
            guard isSearching(target), !isPattern else { return }
            selected = index
            target.markFind(query.isEmpty ? nil : query, selected: index, isPattern: false)
        case let .counted(count):
            guard isSearching(target), isPattern else { return }
            // The newest match first, as with plain words. New output's matches are newer, so the
            // current one's number grows with them and it stays the same match, as libghostty
            // keeps its own; a count that shrank (the scrollback's top let go) keeps it in range.
            var chosen = selected
            if let current = selected, let before = total, count > before {
                chosen = current + count - before
            }
            total = count
            chosen = count > 0 ? min(chosen ?? 0, count - 1) : nil
            if chosen != selected {
                selected = chosen
                target.markFind(query, selected: chosen, isPattern: true)
            }
        case let .chose(index):
            guard isSearching(target), isPattern, let total, total > 0 else { return }
            selected = min(max(index, 0), total - 1)
            target.markFind(query, selected: selected, isPattern: true)
        case let .fullScreen(isFullScreen):
            guard isSearching(target) else { return }
            self.isFullScreen = isFullScreen
        }
    }

    func step(_ direction: Direction) {
        guard isOpen, let target else { return }
        guard isPattern else {
            target.perform(direction == .older ? "navigate_search:next" : "navigate_search:previous")
            return
        }
        // A pattern's matches are Calm's own: newest first, stopping at the ends.
        guard let total, total > 0, let selected else { return }
        let next = direction == .older ? min(selected + 1, total - 1) : max(selected - 1, 0)
        guard next != selected else { return }
        self.selected = next
        target.markFind(query, selected: next, isPattern: true)
    }

    /// Esc in the field, its ⌘F cap, or ⌘F again.
    func close() {
        guard isOpen, let target else { return finish() }
        finish()
        target.perform("end_search")
    }

    /// A key typed into `target` (not a ⌘ shortcut): back to work, so find closes, and the key
    /// still goes to the program.
    func didType(in target: FindTarget) {
        if isSearching(target) {
            close()
        }
    }

    /// The keyboard went to `target` (a click, ⌘[ ⌘]): find stays only on the pane it searches.
    func focusDidMove(to target: FindTarget) {
        if isOpen, self.target !== target {
            close()
        }
    }

    private func open(_ target: FindTarget, query: String, isPattern: Bool) {
        if isOpen, self.target !== target {
            close()
        }
        self.target = target
        isOpen = true
        self.isPattern = isPattern
        isFullScreen = false // until the pane says
        if self.query == query {
            search()
        } else {
            self.query = query
        }
        focusRequest += 1
    }

    private func search() {
        guard let target else { return }
        total = nil
        selected = nil
        isPatternIncomplete = false
        guard isPattern else {
            selectsNewest = !query.isEmpty
            // Everything after the colon is the text, colons and spaces included; empty stops it.
            target.perform("search:" + query)
            target.markFind(query.isEmpty ? nil : query, selected: nil, isPattern: false)
            return
        }
        // libghostty searches plain words only: its search stops, and the pane counts and marks.
        selectsNewest = false
        target.perform("search:")
        guard !query.isEmpty else {
            target.markFind(nil, selected: nil, isPattern: true)
            return
        }
        guard FindQuery(words: query, isPattern: true) != nil else {
            // Half typed (`warn(`): the last marks stay put and nothing jumps.
            isPatternIncomplete = true
            return
        }
        target.markFind(query, selected: nil, isPattern: true)
    }

    private func finish() {
        if let target {
            lastQueries[target.id] = (query, isPattern)
            target.markFind(nil, selected: nil, isPattern: isPattern)
        }
        isOpen = false
        target = nil
        total = nil
        selected = nil
        selectsNewest = false
        isPatternIncomplete = false
        isFullScreen = false
        agentName = nil
    }
}

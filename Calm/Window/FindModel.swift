import Foundation
import Observation

/// What find searches: a pane, through libghostty's search binding actions (DESIGNS.md → Find).
@MainActor
protocol FindTarget: AnyObject {
    var id: UUID { get }
    @discardableResult
    func perform(_ action: String) -> Bool
    /// What the pane marks: the words searched (nil for none) and the current match, counted from
    /// the newest (FindMarksView).
    func markFind(_ words: String?, selected: Int?)
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
}

/// Find in a session (FEATURES.md → F16): the title strip's field and the one pane it searches.
/// libghostty does the searching; this keeps what the field shows and turns its keys into
/// binding actions on the pane. One window has one; the pane that has the keyboard is searched.
@MainActor
@Observable
final class FindModel {
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
    /// Bumped to put the keyboard in the field, with what's in it selected.
    private(set) var focusRequest = 0

    @ObservationIgnored private(set) weak var target: FindTarget?
    /// Each pane's last words, so ⌘F there brings them back (selected, so typing replaces them).
    @ObservationIgnored private var lastQueries: [UUID: String] = [:]
    /// Set by a new search: the first total selects the newest match, so the count reads "1 of N".
    @ObservationIgnored private var selectsNewest = false

    /// "3 of 11", "No matches", or nothing before the first count.
    var countText: String {
        guard !query.isEmpty, let total else { return "" }
        guard total > 0 else { return "No matches" }
        guard let selected else { return total == 1 ? "1 match" : "\(total) matches" }
        return "\(min(selected, total - 1) + 1) of \(total)"
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
                    open(target, query: lastQueries[target.id] ?? "")
                }
            } else {
                open(target, query: needle)
            }
        case .end:
            // Ended without the field asking (⌘⇧F, the user's own binding): just put it away.
            if isSearching(target) {
                finish()
            }
        case let .total(total):
            guard isSearching(target) else { return }
            self.total = total
            if selectsNewest, let total, total > 0, selected == nil {
                selectsNewest = false
                target.perform("navigate_search:next")
            }
        case let .selected(index):
            guard isSearching(target) else { return }
            selected = index
            target.markFind(query.isEmpty ? nil : query, selected: index)
        }
    }

    func step(_ direction: Direction) {
        guard isOpen, let target else { return }
        target.perform(direction == .older ? "navigate_search:next" : "navigate_search:previous")
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

    private func open(_ target: FindTarget, query: String) {
        if isOpen, self.target !== target {
            close()
        }
        self.target = target
        isOpen = true
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
        selectsNewest = !query.isEmpty
        // Everything after the colon is the text, colons and spaces included; empty stops it.
        target.perform("search:" + query)
        target.markFind(query.isEmpty ? nil : query, selected: nil)
    }

    private func finish() {
        if let target {
            lastQueries[target.id] = query
            target.markFind(nil, selected: nil)
        }
        isOpen = false
        target = nil
        total = nil
        selected = nil
        selectsNewest = false
    }
}

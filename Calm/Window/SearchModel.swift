import AppKit
import CalmAgents
import CalmModel
import CalmSearch
import SwiftUI

/// ⌘K (FEATURES.md → F7, UIUX.md → Search): every past and present session, grouped like the
/// sidebar with the group you're in first. Every word typed shows in every result, marked; a
/// group past its share waits behind a row that opens five more at a time. With nothing typed,
/// a switcher of the sessions you could pick back up.
@MainActor
@Observable
final class SearchModel {
    struct Row: Identifiable {
        let item: SearchPanelModel.Item
        let group: SearchGroup
        /// Its open session's state; nil for a past session.
        let state: SessionState?

        var id: String {
            item.id
        }
    }

    /// What the arrow keys walk: sessions, and each group's last row.
    enum Entry: Hashable {
        case session(String)
        /// "13 more in calm", and Show less once the group is open.
        case more(SearchGroup.Key)
        /// An opened group showing all of it: "All 16 in calm", and Show less.
        case all(SearchGroup.Key)

        /// A group's last row, rather than a session.
        var isTail: Bool {
            if case .session = self {
                return false
            }
            return true
        }
    }

    /// Which half of a group's last row ↵ acts on.
    enum Side {
        case more
        case less
    }

    struct Section: Identifiable {
        let group: SearchGroup
        /// Nil with nothing typed: the switcher counts nothing.
        let counts: SearchGroupCounts?
        let rows: [Row]
        let total: Int
        let more: Int
        let folds: Bool

        var id: SearchGroup.Key {
            group.key
        }

        var tail: Entry? {
            more > 0 ? .more(group.key) : folds ? .all(group.key) : nil
        }
    }

    /// A line under a result's title, cut to fit.
    struct Line: Identifiable {
        let id: Int64
        let fromYou: Bool
        let parts: [SearchLineFit.Part]
    }

    var query = "" {
        didSet {
            guard query != oldValue else { return }
            expanded = [:]
            navigated = false
            schedule(refresh: false)
        }
    }

    private(set) var sections: [Section] = []
    private(set) var entries: [Entry] = []
    private(set) var selection: Entry?
    private(set) var side = Side.more
    /// The arrow keys have moved the selection since the query last changed: → and ← then
    /// belong to the list, not the caret.
    private(set) var navigated = false
    private(set) var terms: [String] = []
    /// Whether the index has answered yet, and whether it had anything at all.
    private(set) var answered = false
    private(set) var hasSessions = false
    /// Counts new answers, not groups opening or folding.
    private(set) var generation = 0
    /// Counts requests to bring a group's header to the top (⇥, a fold), with the group.
    private(set) var headerRequest: (count: Int, key: SearchGroup.Key?) = (0, nil)
    /// Counts "more"s, with the group: its last row stays where it was while rows come in above it.
    private(set) var moreRequest: (count: Int, key: SearchGroup.Key?) = (0, nil)

    /// The width of the text under a title, in points at the standard interface size; the view
    /// sets it from the panel's width.
    var textWidth: CGFloat = 606 {
        didSet {
            if textWidth != oldValue {
                lineCache = [:]
            }
        }
    }

    private var rows: [Row] = []
    private var expanded: [SearchGroup.Key: Int] = [:]
    private let grouping: SearchGrouping
    private let currentProject: String?
    @ObservationIgnored private var task: Task<Void, Never>?
    /// Filled while drawing, so it mustn't be observed.
    @ObservationIgnored private var lineCache: [String: [Line]] = [:]

    init(query: String = "", grouping: SearchGrouping, currentProject: String?) {
        self.query = query
        self.grouping = grouping
        self.currentProject = currentProject
        schedule(refresh: true)
    }

    /// Searches off the main thread, debounced while typing.
    private func schedule(refresh: Bool) {
        task?.cancel()
        let query = query
        let grouping = grouping
        let project = currentProject
        task = Task { [weak self] in
            if !refresh {
                try? await Task.sleep(for: .milliseconds(70))
            }
            guard !Task.isCancelled else { return }
            let found = await Task.detached(priority: .userInitiated) {
                SearchService.searchPanel(query, grouping: grouping, currentProject: project, refreshing: refresh)
            }.value
            guard !Task.isCancelled, let self else { return }
            let sessions = SessionManager.shared.workspace.sessions
            rows = found.map { result, group in
                let open = sessions.first { $0.runs(transcriptPath: result.transcriptPath, agentSessionID: result.agentSessionID) }
                return Row(item: SearchPanelModel.Item(result: result, openSession: open?.id), group: group, state: open?.state)
            }
            terms = query.split(whereSeparator: \.isWhitespace).map(String.init)
            lineCache = [:]
            answered = true
            hasSessions = hasSessions || !rows.isEmpty
            generation += 1
            rebuild()
        }
    }

    private func rebuild() {
        let keys = rows.map(\.group.key)
        let groups = terms.isEmpty
            ? SearchGroups.switcher(keys, open: rows.map { $0.state != nil }, current: grouping.current)
            : SearchGroups.grouped(keys, current: grouping.current, capped: Set(keys).count > 1, extra: expanded)
        sections = groups.map { group in
            let members = group.members.map { rows[$0] }
            return Section(
                group: members[0].group,
                counts: terms.isEmpty ? nil : SearchGroupCounts(members.map(\.state)),
                rows: Array(members.prefix(group.shown)),
                total: members.count, more: group.more, folds: group.folds,
            )
        }
        entries = sections.flatMap { section in section.rows.map { Entry.session($0.id) } + (section.tail.map { [$0] } ?? []) }
        if let selection, entries.contains(selection) {
            return
        }
        select(entries.first)
    }

    // MARK: Lines

    /// The lines under a row's title: the fewest that show every word the title and the group's
    /// name don't, each built around its words to fit the width.
    func lines(for row: Row) -> [Line] {
        guard !terms.isEmpty else { return [] }
        if let cached = lineCache[row.id] {
            return cached
        }
        let shown = Set(terms.filter { SearchMatch.contains(row.group.name, $0) || titleShows($0, in: row) })
        // A little room for the marks, which are drawn a weight heavier.
        let width = Double(textWidth) * 0.95
        let lines = row.item.result.linesToShow(terms: terms, shown: shown).map { line in
            Line(
                id: line.id, fromYou: line.role == .user,
                parts: SearchLineFit.parts(line.text, terms: line.terms, cutBefore: line.cutBefore, width: width) {
                    Self.width($0, size: 13)
                },
            )
        }
        lineCache[row.id] = lines
        return lines
    }

    /// Whether the title shows `term` whole before its time and the selected row's ↵.
    private func titleShows(_ term: String, in row: Row) -> Bool {
        let title = row.item.result.title
        guard let range = SearchMatch.firstRange(of: term, in: title) else { return false }
        let upTo = Self.width(String(title[..<range.upperBound]), size: 14.5, weight: .medium)
        let time = row.state != nil ? 12 : Self.width(WrittenTime.text(since: row.item.result.lastActive), size: 12)
        return upTo <= Double(textWidth) - time - 10 - 30 - 6
    }

    /// `text`'s width in the system font, in points at the standard interface size.
    static func width(_ text: String, size: CGFloat, weight: NSFont.Weight = .regular) -> Double {
        Double((text as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: size, weight: weight)]).width)
    }

    // MARK: Keys and clicks

    func step(_ delta: Int) {
        guard !entries.isEmpty else { return }
        navigated = true
        let index = selection.flatMap { entries.firstIndex(of: $0) } ?? (delta > 0 ? -1 : 0)
        select(entries[min(max(index + delta, 0), entries.count - 1)])
    }

    /// ⇥ to the next group's first row, ⇧⇥ back to this group's first row, then the one before;
    /// the group's header comes to the top.
    func jump(_ delta: Int) {
        let starts = sections.compactMap { $0.rows.first.map { Entry.session($0.id) } ?? $0.tail }
        guard !starts.isEmpty else { return }
        navigated = true
        let current = section(of: selection) ?? 0
        let target = delta > 0 ? min(current + 1, starts.count - 1)
            : selection == starts[current] ? max(current - 1, 0) : current
        select(starts[target])
        headerRequest = (headerRequest.count + 1, sections[target].group.key)
    }

    /// → and ←, on an opened group's last row: its Show less half, or back.
    func choose(_ side: Side) -> Bool {
        guard case let .more(key)? = selection, sections.first(where: { $0.group.key == key })?.folds == true, side != self.side else {
            return false
        }
        self.side = side
        return true
    }

    /// ↵, or a click (on `entry`, on its `side`): the session to go to or resume, or nil when the
    /// list changed instead.
    func activate(_ entry: Entry? = nil, side: Side? = nil) -> SearchPanelModel.Item? {
        guard let entry = entry ?? selection else { return nil }
        switch entry {
        case let .session(id):
            return rows.first { $0.id == id }?.item
        case let .more(key):
            if (side ?? (entry == selection ? self.side : .more)) == .less {
                fold(key)
            } else {
                showMore(key)
            }
        case let .all(key):
            fold(key)
        }
        return nil
    }

    /// Five more of a group. Its last row stays selected (and, in the view, under the pointer).
    func showMore(_ key: SearchGroup.Key) {
        expanded[key, default: 0] += SearchGroups.step
        rebuild()
        select(sections.first { $0.group.key == key }?.tail)
        moreRequest = (moreRequest.count + 1, key)
    }

    /// Back to the group's first few, its header at the top.
    func fold(_ key: SearchGroup.Key) {
        expanded[key] = nil
        rebuild()
        select(.more(key))
        headerRequest = (headerRequest.count + 1, key)
    }

    func select(_ entry: Entry?) {
        if entry != selection {
            side = .more
        }
        selection = entry
    }

    private func section(of entry: Entry?) -> Int? {
        switch entry {
        case let .session(id)?: sections.firstIndex { $0.rows.contains { $0.id == id } }
        case let .more(key)?, let .all(key)?: sections.firstIndex { $0.group.key == key }
        case nil: nil
        }
    }

    /// For self-tests: the groups with their counts, rows and lines, and what's selected.
    var descriptionForTesting: String {
        let groups = sections.map { section in
            let rows = section.rows.map { row in
                let lines = lines(for: row).map { line in
                    (line.fromYou ? "›" : "") + line.parts.map { part in
                        switch part {
                        case let .text(text): text
                        case .gap: "…"
                        }
                    }.joined()
                }
                return ([row.item.result.title + (row.state.map { " [\($0.rawValue)]" } ?? "")] + lines).joined(separator: " / ")
            }
            let tail = section.more > 0 ? " +\(section.more) more" : section.folds ? " (all, folds)" : ""
            return "\(section.group.name) {\(section.counts?.words ?? "")}\(tail): " + rows.joined(separator: " | ")
        }
        let selected = selection.map { "\($0)" } ?? "none"
        return "search: \"\(query)\" \(groups.count) groups, selected \(selected) side \(side) — " + groups.joined(separator: " ;; ")
    }
}

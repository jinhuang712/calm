import CalmModel
import Foundation

/// How ⌘K lays out its results (UIUX.md → Search): grouped like the sidebar, the group you're in
/// first and the rest in the order of their best match. With results in more than one group,
/// each shows a few and keeps the rest behind a row that shows five more at a time.
public enum SearchGroups {
    public struct Group<Key: Hashable>: Equatable {
        public let key: Key
        /// Positions in the results, best first.
        public let members: [Int]
        /// How many of `members` show.
        public let shown: Int
        /// Opened by hand past its share, so it can fold back.
        public let folds: Bool

        /// How many wait behind the group's "more" row.
        public var more: Int {
            members.count - shown
        }
    }

    /// What one "more" adds.
    public static let step = 5

    /// Groups `keys` (one per result, best result first). `capped` gives each group its share
    /// (`yours` for the current group, `others` for the rest) plus what `extra` opened; a group
    /// never waits behind "1 more", which would take a row to save none.
    public static func grouped<Key: Hashable>(
        _ keys: [Key],
        current: Key?,
        capped: Bool,
        extra: [Key: Int] = [:],
        yours: Int = 3,
        others: Int = 2,
    ) -> [Group<Key>] {
        ordered(keys, current: current).map { key, members in
            let share = key == current ? yours : others
            let cut = capped && members.count > share + 1
            var shown = cut ? share + (extra[key] ?? 0) : members.count
            if members.count - shown <= 1 {
                shown = members.count
            }
            return Group(key: key, members: members, shown: shown, folds: cut && (extra[key] ?? 0) > 0)
        }
    }

    /// What the empty field lists (a switcher, not a search): the sessions you could pick back up
    /// (`open` ones are in the sidebar already), most recent first, a few from the current
    /// group and fewer from each other, so it never opens as a wall of one project.
    public static func switcher<Key: Hashable>(
        _ keys: [Key],
        open: [Bool],
        current: Key?,
        yours: Int = 4,
        others: Int = 2,
        limit: Int = 11,
    ) -> [Group<Key>] {
        var taken: [Key: Int] = [:]
        var kept: [Int] = []
        for (index, key) in keys.enumerated() where !open[index] && kept.count < limit {
            let count = taken[key] ?? 0
            if count < (key == current ? yours : others) {
                taken[key] = count + 1
                kept.append(index)
            }
        }
        return ordered(kept.map { keys[$0] }, current: current).map { key, positions in
            let members = positions.map { kept[$0] }
            return Group(key: key, members: members, shown: members.count, folds: false)
        }
    }

    /// The groups in order of their first member, the current one first.
    private static func ordered<Key: Hashable>(_ keys: [Key], current: Key?) -> [(key: Key, members: [Int])] {
        var order: [Key] = []
        var members: [Key: [Int]] = [:]
        for (index, key) in keys.enumerated() {
            if members[key] == nil {
                order.append(key)
            }
            members[key, default: []].append(index)
        }
        if let current, let index = order.firstIndex(of: current) {
            order.insert(order.remove(at: index), at: 0)
        }
        return order.map { ($0, members[$0] ?? []) }
    }
}

/// What a group's header counts (UIUX.md → Search): its sessions open in Calm and doing
/// something (working, done, waiting on you or failed), open and idle, and past ones you could
/// resume. Three numbers at most, however long the history.
public struct SearchGroupCounts: Equatable, Sendable {
    public private(set) var open = 0
    public private(set) var idle = 0
    public private(set) var past = 0
    private var states: [SessionState: Int] = [:]

    /// One state per session: its open session's, or nil for a past one.
    public init(_ states: [SessionState?]) {
        for state in states {
            switch state {
            case nil: past += 1
            case .idle?: idle += 1
            case let state?:
                open += 1
                self.states[state, default: 0] += 1
            }
        }
    }

    /// "3 open (1 done, 2 working), 1 idle, 5 past": the header in words, for its tooltip and
    /// VoiceOver. The open ones are told apart unless they're all working.
    public var words: String {
        var parts: [String] = []
        if open > 0 {
            let kinds: [(state: SessionState, name: String)] = [
                (.needsYou, "needs you"),
                (.failed, "failed"),
                (.done, "done"),
                (.working, "working"),
            ]
            let present = kinds.filter { states[$0.state] != nil }
            let detail = present.map { "\(states[$0.state] ?? 0) \($0.name)" }.joined(separator: ", ")
            parts.append(present.map(\.state) == [.working] ? "\(open) open" : "\(open) open (\(detail))")
        }
        if idle > 0 {
            parts.append("\(idle) idle")
        }
        if past > 0 {
            parts.append("\(past) past")
        }
        return parts.joined(separator: ", ")
    }
}

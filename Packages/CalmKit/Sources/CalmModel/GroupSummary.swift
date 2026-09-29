/// What a folded group's one line shows (UIUX.md → Session cards): the states going on in it,
/// most urgent first, each as its marks. Up to three sessions in a state get a mark each, few
/// enough to take in without counting; past that, one mark and the number. Idle sessions show
/// only when nothing else is going on, so a quiet group still says it isn't empty.
public struct GroupSummary: Equatable, Sendable {
    /// One state's part of the line.
    public struct Run: Equatable, Sendable {
        public let state: SessionState
        public let count: Int

        /// Whether the number stands beside a single mark, instead of a mark per session.
        public var showsCount: Bool {
            count > GroupSummary.markLimit
        }

        /// How many marks to draw.
        public var marks: Int {
            showsCount ? 1 : count
        }
    }

    /// The eye takes in up to about four things at once without counting (subitizing); three
    /// stays well inside that.
    public static let markLimit = 3

    /// The order the eye should meet them in: what needs you, then what went wrong, then what's
    /// finished, then what's still going.
    static let order: [SessionState] = [.needsYou, .failed, .done, .working, .idle]

    /// What the line draws.
    public let runs: [Run]
    /// Every state in the group, idle included: what the words say (VoiceOver, the tooltip).
    public let tally: [Run]

    public init(_ states: [SessionState]) {
        tally = Self.order.compactMap { state in
            let count = states.count { $0 == state }
            return count > 0 ? Run(state: state, count: count) : nil
        }
        let going = tally.filter { $0.state != .idle }
        runs = going.isEmpty ? tally : going
    }

    /// A folded group never hides a *needs you*: the whole line takes its tint.
    public var needsYou: Bool {
        tally.contains { $0.state == .needsYou }
    }
}

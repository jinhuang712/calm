/// A step of shrink to fit (specs/UIUX.md → Session cards): one size for the quiet cards and one for
/// the busy ones. Quiet cards fold first, so a card that is doing something or waits for a look
/// keeps its lines longest. The whole group folding as one moved every card at each step, even the
/// working ones, while an idle card's recap line was what could go.
public struct CardFold: Hashable, Sendable, CustomStringConvertible {
    public typealias Size = CalmSettings.SessionCardSize

    /// The size of an idle card with no shells running.
    public let quiet: Size
    /// The size of every other card: working, waiting for a look, or idle with shells running.
    public let busy: Size

    /// Every card at one size.
    public init(_ size: Size) {
        self.init(quiet: size, busy: size)
    }

    public init(quiet: Size, busy: Size) {
        self.quiet = quiet
        self.busy = busy
    }

    /// Whether a card in this state folds first: idle with nothing left running.
    public static func isQuiet(state: SessionState, shellsRunning: Bool) -> Bool {
        state == .idle && !shellsRunning
    }

    /// The size a card in this state is drawn at.
    public func size(state: SessionState, shellsRunning: Bool) -> Size {
        Self.isQuiet(state: state, shellsRunning: shellsRunning) ? quiet : busy
    }

    /// For the trace: `full`, or `full (idle compact)` while only the quiet cards are folded.
    public var description: String {
        quiet == busy ? busy.rawValue : "\(busy.rawValue) (idle \(quiet.rawValue))"
    }
}

extension CardFold: CardFitStep {
    /// From the chosen size down, a size at a time. Before the busy cards take a smaller size the
    /// quiet ones do, when that makes them shorter. Full's idle card has a recap line and
    /// Compact's is the title alone, so from Full the quiet cards fold to Compact first. Compact
    /// and Minimal idle cards are both the title alone, so that step is one for all.
    public static func steps(from largest: Size) -> [CardFold] {
        var steps: [CardFold] = []
        for size in Size.steps(from: largest) {
            if let last = steps.last,
               SessionCardLayout(size: last.quiet, state: .idle) != SessionCardLayout(size: size, state: .idle) {
                steps.append(CardFold(quiet: size, busy: last.busy))
            }
            steps.append(CardFold(size))
        }
        return steps
    }
}

import Foundation

/// What a macOS notification says (UIUX.md → Notifications): a mark for the state and the
/// session's name as the title, and what the agent said as the body. The app's icon already says
/// it's Calm, so neither the project nor the agent is named.
///
/// The message is taken as it is: an agent's prose was made plain when it reached Calm
/// (`MessageText.recap`), and a command someone is asked to allow must not be touched.
public struct NotificationText: Equatable, Sendable {
    public var title: String
    public var body: String

    /// How much a body may hold, in columns (a wide character, such as a Chinese one, takes two).
    /// About two lines of a banner: macOS cuts a third with "…" wherever it falls.
    public static let bodyWidth = 100

    /// - Parameters:
    ///   - state: what happened, or nil for a notice that isn't a state change (`calm notify`, or
    ///     a plain shell's own notification), which gets no mark.
    ///   - sessionName: the name the session shows everywhere else.
    ///   - message: what the agent (or program) said; it may be nil.
    public init(state: SessionState?, sessionName: String, message: String?) {
        title = [state.flatMap(Self.mark(for:)), sessionName].compactMap(\.self).joined(separator: " ")
        let text = message.map { Self.summary($0, asking: state == .needsYou) } ?? ""
        // A body that only says the title again is left out.
        body = text.caseInsensitiveCompare(sessionName) == .orderedSame ? "" : text
    }

    /// The emoji that leads a title. Emoji are the one way to give a banner color: macOS sets
    /// its text in fixed styles. Working and idle never notify.
    static func mark(for state: SessionState) -> String? {
        switch state {
        case .needsYou: "\u{270B}" // ✋
        case .done: "\u{2705}" // ✅
        case .failed: "\u{26A0}\u{FE0F}" // ⚠️ (the selector makes it the emoji, not the text sign)
        case .working, .idle: nil
        }
    }

    /// What to show of a message: for *needs you*, the last question (the ask usually comes
    /// last, after whatever led up to it); otherwise, or with no question, its first sentences
    /// while they fit.
    static func summary(_ message: String, asking: Bool) -> String {
        let sentences = MessageText.sentences(in: MessageText.flat(message))
        if asking, let question = sentences.last(where: MessageText.isQuestion) {
            return MessageText.fit(question, width: bodyWidth)
        }
        var result = ""
        for sentence in sentences {
            let joined = result.isEmpty ? sentence : result + MessageText.sentenceGap(after: result) + sentence
            if MessageText.width(of: joined) > bodyWidth {
                if result.isEmpty {
                    result = MessageText.fit(sentence, width: bodyWidth)
                }
                break
            }
            result = joined
        }
        return result
    }
}

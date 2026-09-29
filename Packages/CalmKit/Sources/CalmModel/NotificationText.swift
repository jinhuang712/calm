import Foundation

/// What a macOS notification says (UIUX.md → Notifications): a mark for the state and the
/// session's name as the title, and what the agent said, in plain words, as the body. The app's
/// icon already says it's Calm, so neither the project nor the agent is named.
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
    ///   - message: what the agent (or program) said; it may be Markdown, and may be nil.
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

    // MARK: Summary

    private static let terminators = Set(".?!…。？！")
    /// A sentence ends at these without a space after them.
    private static let wideTerminators = Set("。？！")
    private static let closers = Set("\"')]}”’」』）")

    /// What to show of a message: for *needs you*, the last question (the ask usually comes
    /// last, after whatever led up to it); otherwise, or with no question, its first sentences
    /// while they fit.
    static func summary(_ message: String, asking: Bool) -> String {
        let (body, headings) = sentences(of: message)
        // A message that is only headings still says something.
        let units = body.isEmpty ? headings : body
        if asking, let question = units.last(where: isQuestion) {
            return fit(question)
        }
        var result = ""
        for unit in units {
            // Chinese sentences run on without a space after 。？！
            let gap = lastMark(of: result).map(wideTerminators.contains) == true ? "" : " "
            let joined = result.isEmpty ? unit : result + gap + unit
            if width(of: joined) > bodyWidth {
                if result.isEmpty {
                    result = fit(unit)
                }
                break
            }
            result = joined
            // A line that doesn't end a sentence (a list item, a label) isn't glued to the next.
            if !endsSentence(unit) {
                break
            }
        }
        return result
    }

    /// The message's sentences in order, Markdown taken out, with its headings apart: a heading
    /// is a label ("Short answer"), not something to say.
    private static func sentences(of message: String) -> (body: [String], headings: [String]) {
        var body: [String] = []
        var headings: [String] = []
        var inFence = false
        for rawLine in message.split(whereSeparator: \.isNewline) {
            var line = rawLine.trimmingCharacters(in: .whitespaces)
            // Code is not something to read in a banner.
            if line.hasPrefix("```") || line.hasPrefix("~~~") {
                inFence.toggle()
                continue
            }
            if inFence {
                continue
            }
            while line.hasPrefix(">") {
                line = String(line.dropFirst()).trimmingCharacters(in: .whitespaces)
            }
            // Rules and table rows.
            if line.isEmpty || line.hasPrefix("|") || line.wholeMatch(of: /([-*_])(\s*\1){2,}/) != nil {
                continue
            }
            let heading = line.prefixMatch(of: /#{1,6}\s+/) != nil
            line = String(line.replacing(/^(#{1,6}|[-*+]|\d{1,3}[.)])\s+(\[[ xX]\]\s+)?/, with: ""))
            line = plain(line)
            guard !line.isEmpty else { continue }
            if heading {
                headings.append(line)
            } else {
                body.append(contentsOf: sentences(in: line))
            }
        }
        return (body, headings)
    }

    /// One line without its inline Markdown. Underscores inside words (`snake_case`) stay.
    private static func plain(_ line: String) -> String {
        line
            .replacing(/!?\[([^\]]*)\]\([^)]*\)/) { $0.1 }
            .replacing(/<(https?:\/\/[^>\s]+)>/) { $0.1 }
            .replacing(/`+([^`]*)`+/) { $0.1 }
            .replacing(/(\*\*|__|~~)(.+?)\1/) { $0.2 }
            // Regex has no lookbehind: the character before the opening mark is captured and put back.
            .replacing(/(^|[^\w*])\*([^\s*](?:[^*]*[^\s*])?)\*(?![\w*])/) { $0.1 + $0.2 }
            .replacing(/(^|\W)_([^\s_](?:[^_]*[^\s_])?)_(?!\w)/) { $0.1 + $0.2 }
            .replacing(/\s+/, with: " ")
            .trimmingCharacters(in: .whitespaces)
    }

    /// Splits at ". ", "? ", "! " and the Chinese 。？！ (which need no space after them). A dot
    /// inside a word or a file name ("Calm.app", "v1.2") isn't a sentence's end.
    private static func sentences(in line: String) -> [String] {
        let characters = Array(line)
        var result: [String] = []
        var current = ""
        var index = 0
        while index < characters.count {
            let character = characters[index]
            current.append(character)
            index += 1
            guard terminators.contains(character) else { continue }
            // A closing quote or bracket belongs to the sentence it closes.
            while index < characters.count, closers.contains(characters[index]) {
                current.append(characters[index])
                index += 1
            }
            if index == characters.count || characters[index].isWhitespace || wideTerminators.contains(character) {
                result.append(current.trimmingCharacters(in: .whitespaces))
                current = ""
            }
        }
        let rest = current.trimmingCharacters(in: .whitespaces)
        if !rest.isEmpty {
            result.append(rest)
        }
        return result
    }

    private static func lastMark(of sentence: String) -> Character? {
        sentence.last { !closers.contains($0) }
    }

    private static func endsSentence(_ sentence: String) -> Bool {
        lastMark(of: sentence).map(terminators.contains) ?? false
    }

    private static func isQuestion(_ sentence: String) -> Bool {
        lastMark(of: sentence).map { $0 == "?" || $0 == "？" } ?? false
    }

    // MARK: Fitting

    private static func width(of text: String) -> Int {
        text.reduce(0) { $0 + width(of: $1) }
    }

    /// Two columns for East Asian wide characters and emoji, one for the rest.
    private static func width(of character: Character) -> Int {
        guard let value = character.unicodeScalars.first?.value else { return 1 }
        switch value {
        case 0x1100 ... 0x115F, 0x2E80 ... 0xA4CF, 0xAC00 ... 0xD7A3, 0xF900 ... 0xFAFF,
             0xFE30 ... 0xFE6F, 0xFF00 ... 0xFF60, 0xFFE0 ... 0xFFE6, 0x1F300 ... 0x1FAFF, 0x20000 ... 0x3FFFD:
            return 2
        default:
            return 1
        }
    }

    /// A sentence cut to `bodyWidth`, at a word where there is one, ending in "…".
    private static func fit(_ sentence: String) -> String {
        guard width(of: sentence) > bodyWidth else { return sentence }
        var used = 0
        var end = sentence.startIndex
        for index in sentence.indices {
            let columns = width(of: sentence[index])
            // One column stays for the ellipsis.
            if used + columns > bodyWidth - 1 {
                break
            }
            used += columns
            end = sentence.index(after: index)
        }
        var head = sentence[..<end]
        // Back to the last space, unless that would throw away more than half.
        if let space = head.lastIndex(of: " "), head.distance(from: head.startIndex, to: space) >= head.count / 2 {
            head = head[..<space]
        }
        while let last = head.last, ",;:–—- \t".contains(last) {
            head = head.dropLast()
        }
        return head + "…"
    }
}

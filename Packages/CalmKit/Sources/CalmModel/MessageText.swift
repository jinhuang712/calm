import Foundation

/// What an agent said, in plain words, for the places that show it in a line or two: a session
/// card's recap, the arrival card and a notification's body (UIUX.md → Session cards,
/// Notifications). Agents write Markdown; a card is not a page.
///
/// This is for *prose*. Text that Calm formats itself, or that quotes a command someone is asked
/// to allow, is not Markdown and must reach the screen as it is: a `*` in `find -name '*.py'` is
/// a glob, and hiding the backticks of `` echo `date` `` would hide what runs.
public enum MessageText {
    /// How much a recap may hold, in columns (a wide character, such as a Chinese one, takes two).
    /// A card shows two lines of it; the rest is only what a wider sidebar can use.
    public static let recapWidth = 280

    /// A message as one line of plain text, or nil when nothing is left.
    ///
    /// - Structure is always removed: fenced code, rules and tables are dropped, headings (labels,
    ///   such as "Short answer") are dropped unless they are all there is, and the marks of
    ///   lists and quotes go. Markdown that reached Calm already flattened onto one line ("## A
    ///   text ### B more") is split at its heading marks, which leaves the label glued to the
    ///   first sentence: a flat line doesn't say where a heading ends.
    /// - Decoration (backticks, `**bold**`, `~~strike~~`, links) goes too, unless `asking`: an ask
    ///   may quote a command, and its marks can matter. Only marks that clearly wrap words are
    ///   read as decoration, so globs (`**/dist`), `2*3` and `__init__` stay as they are.
    public static func recap(_ message: String?, asking: Bool = false, width: Int = recapWidth) -> String? {
        guard let message else { return nil }
        let units = units(of: message, asking: asking)
        guard !units.isEmpty else { return nil }
        return fit(join(units), width: width)
    }

    /// The message on one line, otherwise as it is: for text that isn't Markdown.
    static func flat(_ message: String) -> String {
        message
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .replacing(/\s+/, with: " ")
    }

    // MARK: Units

    /// One sentence, or one line that isn't one (a list item, a label).
    struct Unit: Equatable {
        var text: String
        /// The first sentence of a list item.
        var isItem: Bool
    }

    static func units(of message: String, asking: Bool) -> [Unit] {
        var body: [Unit] = []
        var headings: [Unit] = []
        var inFence = false
        for rawLine in message.split(whereSeparator: \.isNewline) {
            var line = rawLine.trimmingCharacters(in: .whitespaces)
            // Code is not something to read in a card.
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
            for segment in line.split(separator: /\s+(?=#{2,6}\s)/) {
                // A heading mark, then perhaps a list mark ("### 1. Title"), then perhaps a task box.
                let marker = segment.prefixMatch(of: /(#{1,6}\s+)?(?:([-*+]|\d{1,3}[.)])\s+)?(\[[ xX]\]\s+)?/)
                let isHeading = marker?.output.1 != nil
                let isItem = marker?.output.2 != nil && !isHeading
                var text = marker.map { String(segment[$0.range.upperBound...]) } ?? String(segment)
                text = asking ? collapsed(text) : plain(text)
                guard !text.isEmpty else { continue }
                let sentences = sentences(in: text)
                // A heading that says nothing but its label is dropped; a "heading" with sentences
                // in it is a flattened heading and its text, which is the message.
                if isHeading, !sentences.contains(where: endsSentence) {
                    headings.append(Unit(text: text, isItem: false))
                } else {
                    body.append(contentsOf: sentences.enumerated().map { Unit(text: $1, isItem: isItem && $0 == 0) })
                }
            }
        }
        return body.isEmpty ? headings : body
    }

    private static func join(_ units: [Unit]) -> String {
        var result = ""
        var previous: Unit?
        for unit in units {
            result += previous.map { gap(from: $0, to: unit) } ?? ""
            result += unit.text
            previous = unit
        }
        return result
    }

    /// Sentences run on with a space, Chinese ones without; list items are told apart by ";", and a
    /// list that ends gets its full stop, so what follows starts a sentence of its own.
    private static func gap(from previous: Unit, to unit: Unit) -> String {
        if let mark = lastMark(of: previous.text) {
            if wideTerminators.contains(mark) {
                return ""
            }
            if terminators.contains(mark) || mark == ":" || mark == "：" {
                return " "
            }
        }
        if unit.isItem {
            return "; "
        }
        return previous.isItem ? ". " : " "
    }

    // MARK: Plain text

    private static let terminators = Set(".?!…。？！")
    /// A sentence ends at these without a space after them.
    private static let wideTerminators = Set("。？！")
    private static let closers = Set("\"')]}”’」』）")

    /// One line without its decoration.
    private static func plain(_ line: String) -> String {
        var spans: [String] = []
        let text = protectingCode(in: line) { spans.append($0) }
        var result = String(text.replacing(/!?\[([^\]]*)\]\([^)\s]*\)/) { $0.1 })
        result = String(result.replacing(/<(https?:\/\/[^>\s]+)>/) { $0.1 })
        for marker in ["**", "~~"] {
            result = unwrapping(marker, in: result)
        }
        for (index, span) in spans.enumerated() {
            result = result.replacingOccurrences(of: placeholder(index), with: span)
        }
        return collapsed(result)
    }

    private static func collapsed(_ text: String) -> String {
        text.replacing(/\s+/, with: " ").trimmingCharacters(in: .whitespaces)
    }

    private static func placeholder(_ index: Int) -> String {
        "\u{E000}\(index)\u{E001}"
    }

    /// Takes backtick spans out (`` `x` ``, ``` ``x`y`` ```), so what is inside is never read as
    /// decoration (`` `**/dist` ``), and puts a placeholder where each was. A tick with no
    /// partner stays as it is.
    private static func protectingCode(in line: String, span: (String) -> Void) -> String {
        let characters = Array(line)
        var result = ""
        var index = 0
        var count = 0
        while index < characters.count {
            guard characters[index] == "`" else {
                result.append(characters[index])
                index += 1
                continue
            }
            var run = 0
            while index + run < characters.count, characters[index + run] == "`" {
                run += 1
            }
            if let close = closingRun(of: run, in: characters, from: index + run) {
                span(String(characters[(index + run) ..< close]))
                result += placeholder(count)
                count += 1
                index = close + run
            } else {
                result += String(repeating: "`", count: run)
                index += run
            }
        }
        return result
    }

    private static func closingRun(of length: Int, in characters: [Character], from start: Int) -> Int? {
        var index = start
        while index < characters.count {
            guard characters[index] == "`" else {
                index += 1
                continue
            }
            var run = 0
            while index + run < characters.count, characters[index + run] == "`" {
                run += 1
            }
            if run == length {
                return index
            }
            index += run
        }
        return nil
    }

    /// A character that belongs to a word, for telling emphasis from a glob or an exponent.
    private static func isWordish(_ character: Character) -> Bool {
        character.isLetter || character.isNumber || character == "\u{E000}" || character == "\u{E001}"
    }

    /// Removes `marker` pairs that clearly wrap words: an opening one after a space, a quote or the
    /// start, and before a letter, digit, quote, bracket or code; a closing one after something
    /// that isn't a space and before the end, a space or a mark. `**/dist`, `2**3` and `a**` stay.
    private static func unwrapping(_ marker: String, in text: String) -> String {
        let characters = Array(text)
        let mark = Array(marker)
        func matches(at index: Int) -> Bool {
            index + mark.count <= characters.count && Array(characters[index ..< index + mark.count]) == mark
        }
        func closing(after start: Int) -> Int? {
            var position = start + 1
            while position + mark.count <= characters.count {
                if matches(at: position), !characters[position - 1].isWhitespace {
                    let next = position + mark.count < characters.count ? characters[position + mark.count] : nil
                    if next.map({ !isWordish($0) && $0 != mark[0] }) ?? true {
                        return position
                    }
                }
                position += 1
            }
            return nil
        }

        var result: [Character] = []
        var index = 0
        while index < characters.count {
            defer { index += 1 }
            guard matches(at: index) else {
                result.append(characters[index])
                continue
            }
            let before = index > 0 ? characters[index - 1] : nil
            let after = index + mark.count < characters.count ? characters[index + mark.count] : nil
            let startsWord = before.map { !isWordish($0) && $0 != mark[0] } ?? true
            let wrapsWord = after.map { isWordish($0) || "\"'“‘([".contains($0) } ?? false
            guard startsWord, wrapsWord, let close = closing(after: index + mark.count) else {
                result.append(characters[index])
                continue
            }
            result += characters[(index + mark.count) ..< close]
            index = close + mark.count - 1
        }
        return String(result)
    }

    // MARK: Sentences

    /// Splits at ". ", "? ", "! " and the Chinese 。？！ (which need no space after them). A dot
    /// inside a word or a file name ("Calm.app", "v1.2") isn't a sentence's end.
    static func sentences(in line: String) -> [String] {
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

    static func endsSentence(_ sentence: String) -> Bool {
        lastMark(of: sentence).map(terminators.contains) ?? false
    }

    static func isQuestion(_ sentence: String) -> Bool {
        lastMark(of: sentence).map { $0 == "?" || $0 == "？" } ?? false
    }

    /// What goes between two sentences: a space, or nothing after a Chinese full stop.
    static func sentenceGap(after sentence: String) -> String {
        lastMark(of: sentence).map(wideTerminators.contains) == true ? "" : " "
    }

    // MARK: Fitting

    static func width(of text: String) -> Int {
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

    /// Text cut to `width` columns, at a word where there is one, ending in "…".
    static func fit(_ text: String, width limit: Int) -> String {
        guard width(of: text) > limit else { return text }
        var used = 0
        var end = text.startIndex
        for index in text.indices {
            let columns = width(of: text[index])
            // One column stays for the ellipsis.
            if used + columns > limit - 1 {
                break
            }
            used += columns
            end = text.index(after: index)
        }
        var head = text[..<end]
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

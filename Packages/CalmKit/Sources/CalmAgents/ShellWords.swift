import Foundation

/// Splits a command line into words as the shell would, for the plain lines config.toml holds
/// (`claude --model opus --append-system-prompt 'be brief'`): blanks separate words, and quotes and
/// backslashes keep them together. Nil for a line that needs more of the shell than that (a
/// variable, a pipe, a second command, a glob, `~`), which Calm doesn't take apart. CalmKit has no
/// dependencies, and a package for these few lines would be the first.
enum ShellWords {
    /// Unquoted, each of these means the shell would do more than split words.
    private static let shellSyntax: Set<Character> = ["$", "`", ";", "&", "|", "<", ">", "(", ")", "*", "?", "[", "{", "\n"]

    static func split(_ line: String) -> [String]? {
        let characters = Array(line)
        var words: [String] = []
        var word = ""
        var inWord = false
        var index = 0
        while index < characters.count {
            let character = characters[index]
            index += 1
            if character == " " || character == "\t" {
                if inWord {
                    words.append(word)
                    word = ""
                    inWord = false
                }
            } else if character == "'" {
                guard let end = characters[index...].firstIndex(of: "'") else { return nil }
                word += String(characters[index ..< end])
                index = end + 1
                inWord = true
            } else if character == "\"" {
                guard let (quoted, end) = doubleQuoted(characters, from: index) else { return nil }
                word += quoted
                index = end
                inWord = true
            } else if character == "\\" {
                guard index < characters.count else { return nil }
                word.append(characters[index])
                index += 1
                inWord = true
            } else if shellSyntax.contains(character) || !inWord && (character == "~" || character == "#") {
                return nil
            } else {
                word.append(character)
                inWord = true
            }
        }
        if inWord {
            words.append(word)
        }
        return words
    }

    /// The text of a double-quoted string that starts at `start`, and the index after its closing
    /// quote. A backslash keeps only `$`, `` ` ``, `"` and `\` from meaning anything; a variable or a
    /// command inside is more than words.
    private static func doubleQuoted(_ characters: [Character], from start: Int) -> (String, Int)? {
        var text = ""
        var index = start
        while index < characters.count {
            let character = characters[index]
            index += 1
            switch character {
            case "\"":
                return (text, index)
            case "$", "`":
                return nil
            case "\\" where index < characters.count && "$`\"\\".contains(characters[index]):
                text.append(characters[index])
                index += 1
            default:
                text.append(character)
            }
        }
        return nil
    }
}

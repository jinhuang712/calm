import Foundation

/// The words after `calm new`. Either a first message for ⌘N's agent, or `--command`: a whole
/// command, for a session that needs its own start options (specs/CLI.md).
///
/// `--command` is an option and not a guess at the message: "claude 的更新日志看一下" is a
/// message, and a first word that names an agent can't tell the two apart.
public struct NewArguments: Equatable, Sendable {
    public static let usage = #"""
    calm new "<prompt>" [--in <folder>] [--model <name>] [--background]
    calm new --command "<command>" [--in <folder>] [--background]
    """#

    public var folder: String
    public var background = false
    public var model: String?
    public var command: String?
    /// Nil with `--command`, whose message, if any, is part of the command.
    public var message: String?

    /// A word the arguments can't take: what to say, with the usage.
    public struct Wrong: Error, Equatable, Sendable {
        public var reason: String
    }

    public static func parse(_ words: [String], currentFolder: String) -> Result<NewArguments, Wrong> {
        var parsed = NewArguments(folder: currentFolder)
        var prompt: [String] = []
        var iterator = words.makeIterator()
        while let word = iterator.next() {
            switch word {
            case "--background":
                parsed.background = true
            case "--in":
                guard let value = iterator.next() else { return .failure(Wrong(reason: usage)) }
                parsed.folder = value.hasPrefix("/") || value.hasPrefix("~")
                    ? value
                    : (currentFolder as NSString).appendingPathComponent(value)
            case "--model":
                guard let value = iterator.next(), !value.isEmpty, !value.hasPrefix("-") else {
                    return .failure(Wrong(reason: usage))
                }
                parsed.model = value
            case "--command":
                guard let value = iterator.next(), !isBlank(value) else {
                    return .failure(Wrong(reason: "give a command\n\(usage)"))
                }
                parsed.command = value
            default:
                guard !word.hasPrefix("--") else { return .failure(Wrong(reason: "unknown option '\(word)'\n\(usage)")) }
                prompt.append(word)
            }
        }
        if parsed.command != nil {
            guard prompt.isEmpty, parsed.model == nil else {
                return .failure(Wrong(reason: "--command runs as written: put the message and the model in it\n\(usage)"))
            }
            return .success(parsed)
        }
        guard !prompt.isEmpty else { return .failure(Wrong(reason: "give a first message\n\(usage)")) }
        parsed.message = prompt.joined(separator: " ")
        return .success(parsed)
    }

    public static func isBlank(_ command: String) -> Bool {
        command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

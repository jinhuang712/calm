import CalmControl
import Foundation

/// `calm new "<prompt>" [--in <folder>] [--background]`: a clean session in a folder, running ⌘N's
/// agent with `prompt` as its first message, and prints its id (CLI.md). It needs no session, so
/// it works from a script outside Calm. It starts Calm when Calm isn't running, as `calm list` does.
enum NewCommand {
    static let usage = #"calm new "<prompt>" [--in <folder>] [--background]"#

    static func run(_ words: [String]) -> Never {
        var background = false
        var folder = FileManager.default.currentDirectoryPath
        var prompt: [String] = []
        var iterator = words.makeIterator()
        while let word = iterator.next() {
            switch word {
            case "--background":
                background = true
            case "--in":
                guard let value = iterator.next() else { fail(usage, code: 64) }
                folder = value.hasPrefix("/") || value.hasPrefix("~")
                    ? value
                    : (FileManager.default.currentDirectoryPath as NSString).appendingPathComponent(value)
            default:
                guard !word.hasPrefix("--") else { fail("unknown option '\(word)'\n\(usage)", code: 64) }
                prompt.append(word)
            }
        }
        guard !prompt.isEmpty else { fail("give a first message\n\(usage)", code: 64) }
        let response = send(ControlRequest(cmd: .new, path: folder, message: prompt.joined(separator: " "), background: background))
        guard response.ok, let created = response.sessions?.first else {
            fail(response.error ?? "Calm didn't start it")
        }
        print(created.id)
        exit(0)
    }
}

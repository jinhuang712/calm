import CalmControl
import Foundation

/// `calm fork ["<prompt>"] [--background] [--in <folder>] [--session <id>]`: forks this session's
/// conversation into a new session of its own and prints that session's id (CLI.md). The words
/// that aren't options are the prompt. It never starts Calm: a session to fork is in a running one.
enum ForkCommand {
    static let usage = #"calm fork ["<prompt>"] [--background] [--in <folder>] [--session <id>]"#

    static func run(_ words: [String]) -> Never {
        var background = false
        var folder: String?
        var session = ProcessInfo.processInfo.environment["CALM_SESSION_ID"].flatMap { $0.isEmpty ? nil : $0 }
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
            case "--session":
                guard let value = iterator.next() else { fail(usage, code: 64) }
                session = value
            default:
                guard !word.hasPrefix("--") else { fail("unknown option '\(word)'\n\(usage)", code: 64) }
                prompt.append(word)
            }
        }
        guard let session else {
            fail("not in a Calm session: run it in one of Calm's shells, or give --session <id>")
        }
        let request = ControlRequest(
            cmd: .fork, path: folder, session: session, message: prompt.isEmpty ? nil : prompt.joined(separator: " "),
            background: background,
        )
        let response: ControlResponse
        do {
            response = try ControlClient.send(request, timeout: 5)
        } catch {
            fail("\(error)")
        }
        guard response.ok, let forked = response.sessions?.first else {
            fail(response.error ?? "Calm didn't fork it")
        }
        print(forked.id)
        exit(0)
    }
}

import CalmControl
import Foundation

/// `calm new "<prompt>"` or `calm new --command "<command>"`: a clean session in a folder, running
/// ⌘N's agent with `prompt` as its first message, or `command` as written, and prints its id
/// (specs/CLI.md). It needs no session, so it works from a script outside Calm. It starts Calm when
/// Calm isn't running, as `calm list` does.
enum NewCommand {
    static func run(_ words: [String]) -> Never {
        let parsed: NewArguments
        switch NewArguments.parse(words, currentFolder: FileManager.default.currentDirectoryPath) {
        case let .success(arguments): parsed = arguments
        case let .failure(wrong): fail(wrong.reason, code: 64)
        }
        let response = send(ControlRequest(
            cmd: .new,
            path: parsed.folder,
            message: parsed.message,
            background: parsed.background,
            model: parsed.model,
            command: parsed.command,
        ))
        guard response.ok, let created = response.sessions?.first else {
            fail(response.error ?? "Calm didn't start it")
        }
        print(created.id)
        exit(0)
    }
}

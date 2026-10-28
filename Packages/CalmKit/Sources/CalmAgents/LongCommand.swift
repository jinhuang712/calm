import Foundation

/// A command too long to type into a new shell. The shell isn't at its prompt yet when Calm types
/// (resume, fork, `calm new`), so the terminal is still in line mode, which keeps 1023 bytes and
/// drops the rest, the Return too (macOS MAX_CANON; seen 2026-10-29: a 1.2 KB `calm new` prompt
/// cut mid-character and never run). A long command goes to a private file instead, and the line
/// typed is `source '<file>'`: the interactive shell still runs it, so PATH, mise and direnv apply
/// and the shell stays when the agent exits.
public enum LongCommand {
    /// Bytes a command may have and still be typed as it is. Well under the line limit, which the
    /// shell's own echo of a long line and a few keystrokes before it also use.
    public static let limit = 800

    /// What to type for `command`: itself when short, else a `source` of a file in `directory`
    /// that holds it. The file removes itself first thing (zsh reads all of a sourced file before
    /// running it, and an open file may be removed anyway), so no prompt stays on disk. Falls back
    /// to the command itself when the file can't be written.
    public static func typed(_ command: String, in directory: URL) -> String {
        guard command.utf8.count > limit else { return command }
        let file = directory.appending(path: UUID().uuidString + ".sh")
        let quoted = shellQuoted(file.path)
        let script = "command rm -f -- \(quoted)\n\(command)\n"
        do {
            try FileManager.default.createDirectory(
                at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700],
            )
            try Data(script.utf8).write(to: file, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
        } catch {
            return command
        }
        return "source \(quoted)"
    }
}

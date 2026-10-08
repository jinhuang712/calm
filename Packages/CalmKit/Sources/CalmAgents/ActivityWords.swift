import Foundation

/// English for the working line, shared by agents' adapters: an agent's own description of a
/// command ("Run the tests") as what it's doing ("Running the tests"), and a command's program.
enum ActivityWords {
    /// "Run the full test suite" → "Running the full test suite". Only when the first word is a
    /// verb on the list: a description that starts any other way ("No-op …", "Full rebuild")
    /// stays as it is, which reads fine and is never wrong English.
    static func ongoing(_ description: String) -> String? {
        let text = description.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        let space = text.firstIndex(where: \.isWhitespace) ?? text.endIndex
        var first = String(text[..<space])
        let rest = text[space...]
        // "Lint, build and test" → "Linting, build and test": the comma stays where it was.
        let tail = String(first.reversed().prefix { ",:;".contains($0) }.reversed())
        first.removeLast(tail.count)
        // "Re-run", "Fast-forward", "Self-test": the last part is the verb, after a prefix that
        // makes one ("Pre-commit checks" and "Run-time check" are nouns, and stay as they are).
        let parts = first.split(separator: "-", omittingEmptySubsequences: false).map(String.init)
        guard let last = parts.last, verbs.contains(last.lowercased()),
              parts.dropLast().allSatisfy({ verbPrefixes.contains($0.lowercased()) })
        else { return text }
        let verb = (parts.dropLast() + [ing(last)]).joined(separator: "-")
        return verb + tail + rest
    }

    /// A verb's -ing form, keeping its capital: "Run" → "Running", "Write" → "Writing".
    static func ing(_ verb: String) -> String {
        let lower = verb.lowercased()
        let stem = if doubled.contains(lower) {
            verb + String(verb.last ?? Character(" "))
        } else if lower.hasSuffix("e"), !lower.hasSuffix("ee"), !lower.hasSuffix("ye"), !lower.hasSuffix("oe"), lower.count > 2 {
            String(verb.dropLast())
        } else {
            verb
        }
        return stem + "ing"
    }

    /// The program a shell command runs, past `cd`, variable settings and wrappers, with its
    /// subcommand when it has one: "cd app && swift test --filter X" → "swift test".
    static func program(_ command: String) -> String? {
        let segments = command.split { "\n;&|".contains($0) }
        for segment in segments {
            var words = segment.split(whereSeparator: \.isWhitespace).map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "\"'()")) }
            while let first = words.first, first.isEmpty || isSetting(first) || wrappers.contains(first) || first.hasPrefix("-") {
                words.removeFirst()
            }
            guard let first = words.first, !skipped.contains(first), !first.hasPrefix("#") else { continue }
            let name = URL(filePath: first).lastPathComponent
            if words.count > 1, isSubcommand(words[1]) {
                return "\(name) \(words[1])"
            }
            return name
        }
        return nil
    }

    private static func isSetting(_ word: String) -> Bool {
        guard let equals = word.firstIndex(of: "="), equals > word.startIndex else { return false }
        return word[..<equals].allSatisfy { $0.isLetter || $0.isNumber || $0 == "_" }
    }

    /// `git status`, `swift test`, `mise run`: a plain lowercase word, not a flag, a path or a file.
    private static func isSubcommand(_ word: String) -> Bool {
        word.count <= 20 && word.first?.isLowercase == true && word.allSatisfy { $0.isLowercase || $0.isNumber || $0 == "-" }
    }

    /// Words that only set a command up: what follows is the program.
    private static let wrappers: Set = ["env", "time", "sudo", "exec", "nohup", "command", "taskpolicy", "caffeinate"]
    /// Commands that only move or set the shell up: the next one is what runs.
    private static let skipped: Set = ["cd", "pushd", "popd", "export", "source", ".", "set", "unset", "true", ":"]

    /// The verbs agents start their descriptions with, from 23,674 of Claude Code's Bash calls in
    /// the author's transcripts (2026-10-09), and the common ones beside them.
    static let verbs: Set = [
        "add", "amend", "analyse", "analyze", "append", "apply", "archive", "back", "benchmark", "branch", "break", "build",
        "bump", "calculate", "call", "capture", "check", "checkout", "classify", "clean", "clear", "clone", "close", "collect",
        "commit", "compare", "compile", "compose", "compress", "compute", "configure", "confirm", "continue", "convert", "copy",
        "correct", "count", "create", "crop", "debug", "decode", "delete", "deploy", "describe", "detect", "diagnose", "diff",
        "disable", "document", "download", "downscale", "drive", "drop", "dump", "edit", "enable", "encode", "explain",
        "export", "extract", "fetch", "filter", "find", "finish", "fix", "format", "forward", "gather", "generate", "get",
        "grep", "group", "identify", "import", "index", "inspect", "install", "keep", "kill", "land", "launch", "lint", "list",
        "load", "locate", "log", "look", "make", "map", "mark", "measure", "merge", "move", "open", "outline", "package",
        "parse", "patch", "ping", "plan", "point", "poll", "post", "prepare", "preview", "print", "probe", "profile", "prune",
        "publish", "pull", "push", "query", "read", "rebase", "rebuild", "recheck", "record", "recreate", "refresh",
        "regenerate", "reinstall", "release", "reload", "remove", "rename", "render", "repeat", "replace", "replay", "reproduce",
        "rerun", "reset", "resize", "resolve", "restart", "restore", "retest", "retry", "revert", "review", "rewrite", "run",
        "sample", "save", "scan", "screenshot", "search", "see", "send", "serve", "set", "show", "sign", "size", "skip",
        "snapshot", "sort", "split", "squash", "stage", "start", "stop", "strip", "summarise", "summarize", "survey",
        "switch", "sync", "tag", "take", "test", "tidy", "time", "touch", "trace", "track", "trim", "trust", "try",
        "typecheck", "uninstall", "unzip", "update", "upgrade", "upload", "use", "validate", "verify", "vet", "view", "wait",
        "watch", "wire", "write", "zip",
    ]

    /// What comes before a hyphen in a verb: "Re-run", "Fast-forward", "Dry-run", "Double-check".
    private static let verbPrefixes: Set = ["re", "fast", "self", "dry", "smoke", "double", "cherry", "mutation", "cross"]

    /// Verbs that double their last letter: "running", "stopping", "snapshotting".
    private static let doubled: Set = [
        "begin", "chop", "commit", "crop", "cut", "debug", "drop", "format", "get", "grep", "hit", "let", "log", "map", "omit", "pin",
        "plan", "pop", "prep", "put", "rerun", "reset", "run", "scan", "screenshot", "set", "ship", "skip", "snapshot",
        "split", "stop", "strip", "submit", "swap", "tag", "trim", "unzip", "vet", "wrap", "zip",
    ]
}

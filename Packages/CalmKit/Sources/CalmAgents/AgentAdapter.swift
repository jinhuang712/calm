import CalmModel
import Foundation

/// What a foreground process looks like: enough to tell which agent, if any, it is.
public struct ProcessSnapshot: Sendable, Equatable {
    public var processID: Int32
    public var executablePath: String
    public var arguments: [String]

    public init(processID: Int32, executablePath: String, arguments: [String]) {
        self.processID = processID
        self.executablePath = executablePath
        self.arguments = arguments
    }

    /// Script runtimes: for these, the script they run names the program.
    static let runtimes: Set<String> = ["node", "bun", "deno", "tsx"]

    private static func basename(_ path: String) -> String {
        (path as NSString).lastPathComponent
    }

    /// The runtime's script, when the executable is a script runtime (`node …/bin/pi`).
    var scriptPath: String? {
        guard Self.runtimes.contains(Self.basename(executablePath)) || Self.runtimes.contains(Self.basename(arguments.first ?? "")) else {
            return nil
        }
        // The first argument after the runtime that isn't an option.
        return arguments.dropFirst().first { !$0.hasPrefix("-") }
    }

    /// Names the process goes by: its executable, argv[0], and a runtime's script.
    var names: Set<String> {
        var names: Set<String> = [Self.basename(executablePath)]
        if let first = arguments.first {
            names.insert(Self.basename(first))
        }
        if let scriptPath {
            let script = Self.basename(scriptPath)
            names.insert(script)
            names.insert((script as NSString).deletingPathExtension)
        }
        names.remove("")
        return names
    }
}

/// One agent's knowledge (DESIGNS.md → Agents). Adding an agent means adding an adapter;
/// the core never special-cases one.
public protocol AgentAdapter: Sendable {
    var kind: AgentKind { get }
    /// Executable or script names the agent runs as.
    var commandNames: Set<String> { get }
    /// Name prefixes of native binaries (e.g. per-platform builds such as `codex-aarch64-apple-darwin`).
    var commandPrefixes: [String] { get }
    /// Path fragments of the agent's package, when a script runtime (node, bun) runs it.
    var packagePaths: [String] { get }
    /// Subcommands that start one of the agent's background helpers rather than a session.
    var helperSubcommands: Set<String> { get }
}

public extension AgentAdapter {
    var commandPrefixes: [String] {
        []
    }

    var helperSubcommands: Set<String> {
        []
    }

    func matches(_ process: ProcessSnapshot) -> Bool {
        if process.arguments.count > 1, helperSubcommands.contains(process.arguments[1]) {
            return false
        }
        let names = process.names
        if !names.isDisjoint(with: commandNames) {
            return true
        }
        if names.contains(where: { name in commandPrefixes.contains { name.hasPrefix($0) } }) {
            return true
        }
        let paths = [process.executablePath, process.scriptPath ?? ""]
        return paths.contains { path in packagePaths.contains { path.contains($0) } }
    }
}

public enum Agents {
    public static let adapters: [any AgentAdapter] = [
        ClaudeCodeAdapter(),
        CodexAdapter(),
        OpenCodeAdapter(),
        PiAdapter(),
        OmpAdapter(),
    ]

    /// The agent a foreground process is, if any.
    public static func detect(_ process: ProcessSnapshot) -> AgentKind? {
        adapters.first { $0.matches(process) }?.kind
    }

    public static func adapter(for kind: AgentKind) -> (any AgentAdapter)? {
        adapters.first { $0.kind == kind }
    }
}

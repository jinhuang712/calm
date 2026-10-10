import CalmAgents
import CalmModel
import Foundation
import OSLog

/// Connects agents' hooks to Calm (FEATURES.md → F5, DESIGNS.md → Agents).
///
/// Claude Code's hooks ship as a plugin in `~/Library/Application Support/Calm/agents/claude-code`
/// (rewritten at each launch) and are loaded through `CLAUDE_CODE_PLUGIN_DIRS` in the shells Calm
/// starts: nothing is written to the user's Claude settings, and Claude sessions outside Calm
/// never see it. `hooks = false` under `[agents.claude-code]` in config.toml turns it off.
///
/// An agent the user connected through a file (pi's extension) keeps that file current: at each
/// launch Calm rewrites its own file if this version's differs. It never adds one: connecting is
/// the user's choice, in Settings → Agents. A connected agent that reads a theme file (OpenCode)
/// also gets Calm's theme, rewritten whenever the colors on screen change.
@MainActor
enum AgentIntegrations {
    private static let log = Logger(subsystem: "com.jinhuang.calm", category: "agents")

    /// Whether Calm writes into agents' own config folders. Unit tests never do, and self-tests
    /// don't unless asked (`CALM_AGENT_FILES=none` otherwise): they run with the user's real home,
    /// where a test theme would restyle the user's OpenCode.
    private static var writesAgentFiles: Bool {
        let environment = ProcessInfo.processInfo.environment
        return environment["XCTestConfigurationFilePath"] == nil && environment["CALM_AGENT_FILES"] != "none"
    }

    /// In Calm's support folder, so a self-test's or a unit test's Calm writes its own and never the
    /// real Calm's (CalmDefaults.isolatedDirectory).
    static var claudeCodePluginDirectory: URL {
        ClaudeCodeAdapter.pluginDirectory(in: CalmDefaults.directory)
    }

    /// Writes the plugin files, so a moved or updated app still leaves a valid plugin behind for
    /// shells that outlive it (they run under zmx).
    static func prepare() {
        let directory = claudeCodePluginDirectory
        for (path, contents) in ClaudeCodeAdapter.pluginFiles() {
            let url = directory.appending(path: path)
            do {
                try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try contents.write(to: url, atomically: true, encoding: .utf8)
            } catch {
                log.error("couldn't write \(url.path, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }
        refreshConnectedFiles()
        syncThemeFiles()
        syncSendKeys(on: SessionManager.shared.settings.sendWithCommandReturn)
    }

    /// Send with ⌘ Return (FEATURES.md → F5): puts Calm's bindings into each installed agent's own
    /// key settings while the setting is on, and takes them out while it's off (`SendKeysFile`,
    /// which only ever adds and removes Calm's own). At launch, so an agent installed since gets
    /// them, and whenever the setting changes. Returns where each agent stands, for Settings.
    @discardableResult
    static func syncSendKeys(
        on: Bool,
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        inherited: [String: String] = ProcessInfo.processInfo.environment,
    ) -> [AgentKind: SendKeysFile.State] {
        var states: [AgentKind: SendKeysFile.State] = [:]
        for (kind, keys) in sendKeys(home: home, inherited: inherited) {
            guard writesAgentFiles else {
                states[kind] = SendKeysFile.state(of: keys)
                continue
            }
            do {
                if on {
                    states[kind] = try SendKeysFile.turnOn(keys)
                } else {
                    try SendKeysFile.turnOff(keys)
                    states[kind] = SendKeysFile.state(of: keys)
                }
            } catch {
                let reason = error.localizedDescription
                log.error("couldn't change \(keys.file.path, privacy: .public): \(reason, privacy: .public)")
                states[kind] = .unreadable
            }
        }
        return states
    }

    /// The installed agents that can send with ⌘ Return (their config folder is there), in the
    /// order Calm lists agents, with their bindings.
    static func sendKeys(
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        inherited: [String: String] = ProcessInfo.processInfo.environment,
    ) -> [(kind: AgentKind, keys: SendKeys)] {
        Agents.adapters.compactMap { adapter in
            guard let keys = adapter.sendKeys(home: home, inherited: inherited),
                  FileManager.default.fileExists(atPath: keys.file.deletingLastPathComponent().path)
            else { return nil }
            return (adapter.kind, keys)
        }
    }

    /// Writes, rewrites or removes each connected agent's theme file for the colors on screen
    /// (`AgentSetupFiles.syncTheme`). Called at launch, on every config reload and appearance
    /// change, and after Connect or Disconnect; a file that's already right is left untouched.
    static func syncThemeFiles() {
        guard writesAgentFiles else { return }
        let home = FileManager.default.homeDirectoryForCurrentUser
        let colors = TerminalTheme.onScreen()
        for adapter in Agents.adapters where adapter.themeFilePath != nil {
            do {
                if try AgentSetupFiles.syncTheme(for: adapter, colors: colors, home: home) {
                    log.info("synced \(adapter.kind.rawValue, privacy: .public)'s theme")
                }
            } catch {
                let reason = error.localizedDescription
                log.error("couldn't sync \(adapter.kind.rawValue, privacy: .public)'s theme: \(reason, privacy: .public)")
            }
        }
    }

    /// The agents that trust the scratch folders, found or made so since launch.
    private static var trustingScratch: Set<AgentKind> = []

    /// Scratch folders are Calm's own and start empty, so an agent that asks before it works in a
    /// new folder (Claude Code) is told once that their root is trusted (FEATURES.md → F2). Called
    /// at each new scratch session, before its agent starts and whichever agent that is, so one the
    /// user starts there by hand doesn't ask either; after it succeeds, it costs nothing.
    static func trustScratchFolders(
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        inherited: [String: String] = ProcessInfo.processInfo.environment,
    ) {
        guard writesAgentFiles else { return }
        for adapter in Agents.adapters where !trustingScratch.contains(adapter.kind) {
            guard let trust = adapter.trust(ScratchFolders.root, home: home, inherited: inherited) else { continue }
            switch trust {
            case .alreadyTrusted:
                trustingScratch.insert(adapter.kind)
            case .added:
                trustingScratch.insert(adapter.kind)
                log.info("\(adapter.kind.rawValue, privacy: .public) now trusts the scratch folders")
            case let .unchanged(reason):
                log.info("\(adapter.kind.rawValue, privacy: .public) doesn't trust the scratch folders yet: \(reason, privacy: .public)")
            }
        }
    }

    /// Brings the files Calm wrote into agents' config folders up to date (see above).
    private static func refreshConnectedFiles() {
        guard writesAgentFiles else { return }
        let home = FileManager.default.homeDirectoryForCurrentUser
        for adapter in Agents.adapters {
            guard case let .files(files) = adapter.setup else { continue }
            do {
                for path in try AgentSetupFiles.refresh(files, home: home) {
                    log.info("updated \(path, privacy: .public)")
                }
            } catch {
                let reason = error.localizedDescription
                log.error("couldn't update \(adapter.kind.rawValue, privacy: .public)'s file: \(reason, privacy: .public)")
            }
        }
    }

    /// Variables for a new session's shell: Claude Code's hooks and what each adapter asks for
    /// (OpenCode's theme). Read at each new session, so a change to an agent's config applies to
    /// the next one.
    static func environment(
        settings: CalmSettings,
        inherited: [String: String] = ProcessInfo.processInfo.environment,
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
    ) -> [String: String] {
        var environment = claudeCodeEnvironment(settings: settings, inherited: inherited)
        for adapter in Agents.adapters {
            environment.merge(adapter.shellEnvironment(home: home, inherited: inherited)) { current, _ in current }
        }
        return environment
    }

    /// Adds Calm's plugin to `CLAUDE_CODE_PLUGIN_DIRS`, keeping the user's own directories.
    private static func claudeCodeEnvironment(settings: CalmSettings, inherited: [String: String]) -> [String: String] {
        guard settings.bool("agents.claude-code.hooks", default: true) else { return [:] }
        let ours = claudeCodePluginDirectory.path
        let existing = inherited["CLAUDE_CODE_PLUGIN_DIRS"].flatMap { $0.isEmpty ? nil : $0 }
        guard existing?.split(separator: ":").contains(Substring(ours)) != true else { return [:] }
        return ["CLAUDE_CODE_PLUGIN_DIRS": existing.map { "\($0):\(ours)" } ?? ours]
    }
}

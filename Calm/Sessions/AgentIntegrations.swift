import CalmAgents
import CalmModel
import Foundation
import OSLog

/// Connects agents' hooks to Calm (FEATURES.md → F5, DESIGNS.md → Agents).
///
/// Claude Code's hooks ship as a plugin in `~/Library/Application Support/Calm/agents/claude-code`
/// (rewritten at each launch) and are loaded through `CLAUDE_CODE_PLUGIN_DIRS` in the shells Calm
/// starts: nothing is written to the user's Claude settings, and Claude sessions outside Calm
/// never see it. `claude-code-hooks = false` under `[agents]` in config.toml turns it off.
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

    static var claudeCodePluginDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: "Calm/agents/claude-code")
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
        guard settings.bool("agents.claude-code-hooks", default: true) else { return [:] }
        let ours = claudeCodePluginDirectory.path
        let existing = inherited["CLAUDE_CODE_PLUGIN_DIRS"].flatMap { $0.isEmpty ? nil : $0 }
        guard existing?.split(separator: ":").contains(Substring(ours)) != true else { return [:] }
        return ["CLAUDE_CODE_PLUGIN_DIRS": existing.map { "\($0):\(ours)" } ?? ours]
    }
}

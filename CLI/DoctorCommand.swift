import CalmAgents
import CalmControl
import CalmModel
import Foundation

/// `calm doctor`: gathers what `Doctor` checks, from the Calm that answers, this Mac's processes
/// and files, and this shell, then prints the verdicts. It reads; it never changes anything.
enum DoctorCommand {
    static func run(_ words: [String], cliVersion: String) -> Never {
        let json = words.contains("--json")
        if let unknown = words.first(where: { $0 != "--json" }) {
            fail("unknown option '\(unknown)'", code: 64)
        }
        let checks = Doctor.checks(facts(cliVersion: cliVersion))
        print(json ? Doctor.json(checks) : Doctor.text(checks))
        exit(checks.contains { $0.verdict == .problem } ? 1 : 0)
    }

    static func facts(cliVersion: String) -> Doctor.Facts {
        let environment = ProcessInfo.processInfo.environment
        let sessionID = environment["CALM_SESSION_ID"].flatMap { $0.isEmpty ? nil : $0 }
        let executable = Bundle.main.executableURL ?? URL(filePath: CommandLine.arguments[0])
        let home = FileManager.default.homeDirectoryForCurrentUser
        let settings = CalmSettings.load()
        let agents = agents(home: home, settings: settings)
        var facts = Doctor.Facts(
            answer: answer(session: sessionID),
            cliVersion: cliVersion,
            cliApp: CalmLaunch.app(containing: executable)?.path,
            pathCalm: calmOnPath(environment["PATH"] ?? ""),
            agents: agents,
            sessionID: sessionID,
        )
        if case let .answered(info) = facts.answer {
            let app = URL(filePath: info.bundlePath)
            let plist = NSDictionary(contentsOf: app.appending(path: "Contents/Info.plist"))
            let name = plist?["CFBundleExecutable"] as? String ?? "Calm"
            let appExecutable = realPath(app.appending(path: "Contents/MacOS/\(name)").path)
            facts.started = ProcessInspector.startDate(of: info.processID)
            facts.copies = ProcessInspector.processes(running: appExecutable)
            facts.installedVersion = plist?["CFBundleShortVersionString"] as? String
            // install.sh builds right before it copies, and ditto keeps the build's time.
            facts.installedAt = (try? FileManager.default.attributesOfItem(atPath: appExecutable))?[.modificationDate] as? Date
        }
        // Calm's Claude Code plugin reaches Claude only through this shell's plugin folders.
        let claudeHooksOn = agents.contains { $0.link == .plugin(written: true, on: true) }
        if sessionID != nil, claudeHooksOn {
            let folders = (environment["CLAUDE_CODE_PLUGIN_DIRS"] ?? "").split(separator: ":").map(String.init)
            facts.claudePluginInShell = folders.contains(ClaudeCodeAdapter.pluginDirectory.path)
        }
        return facts
    }

    private static func answer(session: String?) -> Doctor.Answer {
        do {
            let response = try ControlClient.send(ControlRequest(cmd: .info, session: session), timeout: 2)
            if response.ok, let info = response.info {
                return .answered(info)
            }
            return .refused(response.error ?? "it gave no answer to `info`")
        } catch let error as ControlClient.ClientError {
            if case let .notRunning(socket) = error {
                return .notRunning(socket: socket)
            }
            return .silent(error.description)
        } catch {
            return .silent("its reply couldn't be read")
        }
    }

    /// The agents whose config folder is there, and how each reports, as Settings → Agents sees it.
    private static func agents(home: URL, settings: CalmSettings) -> [Doctor.Agent] {
        Agents.adapters.compactMap { adapter in
            guard let folder = adapter.configFolder, FileManager.default.fileExists(atPath: home.appending(path: folder).path)
            else { return nil }
            let link: Doctor.AgentLink = switch adapter.currentSetup(home: home) {
            case .automatic:
                // Calm's own plugin, loaded in its shells: Claude Code's.
                .plugin(
                    written: ClaudeCodeAdapter.pluginFiles().keys.allSatisfy { path in
                        FileManager.default.fileExists(atPath: ClaudeCodeAdapter.pluginDirectory.appending(path: path).path)
                    },
                    on: settings.bool("agents.claude-code.hooks", default: true),
                )
            case .notifications:
                .notifications
            case let .files(files):
                .files(filesState(files, home: home))
            case let .hint(text):
                .hint(text)
            }
            return Doctor.Agent(name: adapter.kind.displayName, link: link)
        }
    }

    private static func filesState(_ files: [String: String], home: URL) -> Doctor.FilesState {
        switch AgentSetupFiles.state(of: files, home: home) {
        case .connected:
            let current = files.allSatisfy { path, contents in
                (try? String(contentsOf: home.appending(path: path), encoding: .utf8)) == contents
            }
            return current ? .connected : .outdated
        case .notInstalled:
            return .notConnected
        case let .conflict(path):
            return .conflict(path)
        }
    }

    /// The first `calm` on `PATH`, links resolved.
    private static func calmOnPath(_ path: String) -> String? {
        for folder in path.split(separator: ":") {
            let candidate = "\(folder)/calm"
            if FileManager.default.isExecutableFile(atPath: candidate) {
                return realPath(candidate)
            }
        }
        return nil
    }
}

/// The path with every link resolved, as the kernel names it (`/private/tmp`, not `/tmp`), so
/// it compares with `proc_pidpath` and `log`'s process paths. Foundation's resolving drops
/// `/private`.
func realPath(_ path: String) -> String {
    guard let resolved = realpath(path, nil) else { return path }
    defer { free(resolved) }
    return String(cString: resolved)
}

import CalmAgents
import CalmControl
import CalmModel
import Foundation

/// `calm config`: lists, reads and changes Calm's settings in config.toml (`Agents.settingsKeys`:
/// Calm's own, and each agent's options for ⌘N, which the adapters declare), one line at a time
/// as Settings writes them, then asks the running Calm to apply them as
/// Reload Configuration does. It never starts Calm: a change waits for its next launch.
enum ConfigCommand {
    static let usage = "calm config [list [--json] | get <key> | set <key> <value…> | unset <key>]"

    static func run(_ words: [String]) -> Never {
        switch words.first {
        case nil, "list":
            let rest = words.dropFirst()
            guard rest.allSatisfy({ $0 == "--json" }) else { fail(usage, code: 64) }
            list(json: rest.contains("--json"))
        case "help", "--help", "-h":
            print(usage)
        case "get":
            guard words.count == 2 else { fail(usage, code: 64) }
            print(CalmSettings.load().value(of: key(words[1])))
        case "set":
            guard words.count >= 3 else { fail(usage, code: 64) }
            let key = key(words[1])
            // The rest of the line is the value, so a command needs no quotes:
            // `calm config set agents.claude-code.command claude -w`.
            let value = words.dropFirst(2).joined(separator: " ")
            switch CalmSettings.change(value, for: key, themes: themeNames()) {
            case let .success(.write(value)):
                write(key, value)
                print("\(key.name) = \(value)")
            case .success(.remove):
                write(key, nil)
                print(backToDefault(key))
            case let .failure(error):
                fail(error.description, code: 64)
            }
            applyInRunningCalm()
        case "unset":
            guard words.count == 2 else { fail(usage, code: 64) }
            let key = key(words[1])
            write(key, nil)
            print(backToDefault(key))
            applyInRunningCalm()
        default:
            fail(usage, code: 64)
        }
        exit(0)
    }

    /// A key whose default is no value (the theme) is just unset.
    private static func backToDefault(_ key: CalmSettings.Key) -> String {
        key.defaultValue.isEmpty ? "\(key.name) is unset" : "\(key.name) = \(key.defaultValue) (the default)"
    }

    private static func key(_ name: String) -> CalmSettings.Key {
        guard let key = Agents.settingsKey(named: name) else {
            fail("no setting named '\(name)': `calm config list` shows them", code: 64)
        }
        return key
    }

    /// Every setting, its value in force and what it takes; a set value is the one without
    /// "(default)". Keys config.toml has that Calm doesn't read, and lines it can't read, follow.
    private static func list(json: Bool) {
        let settings = CalmSettings.load()
        let known = Set(Agents.settingsKeys.map(\.name))
        let unknown = settings.values.keys.filter { !known.contains($0) }.sorted()
        if json {
            printJSON(settings, unknown: unknown)
            return
        }
        let shown = Agents.settingsKeys.map { settings.value(of: $0).isEmpty ? "(unset)" : settings.value(of: $0) }
        let width = Agents.settingsKeys.map(\.name.count).max() ?? 0
        let valueWidth = shown.map(\.count).max() ?? 0
        for (key, value) in zip(Agents.settingsKeys, shown) {
            let isSet = settings.values[key.name] != nil
            let name = key.name.padding(toLength: width, withPad: " ", startingAt: 0)
            let padded = value.padding(toLength: valueWidth, withPad: " ", startingAt: 0)
            print("\(name) = \(padded)  \(isSet ? "         " : "(default)")  \(key.takes)")
        }
        if !unknown.isEmpty {
            warn("config.toml also has \(unknown.joined(separator: ", ")), which Calm doesn't read")
        }
        for problem in settings.problems {
            warn("config.toml, \(problem)")
        }
    }

    private static func printJSON(_ settings: CalmSettings, unknown: [String]) {
        struct Entry: Encodable {
            let key: String
            let value: String
            let isSet: Bool
            let defaultValue: String
            let takes: String
            let about: String
        }
        struct Output: Encodable {
            let v = 1
            let settings: [Entry]
            let unknown: [String]
            let problems: [String]
        }
        let entries = Agents.settingsKeys.map { key in
            Entry(
                key: key.name, value: settings.value(of: key), isSet: settings.values[key.name] != nil,
                defaultValue: key.defaultValue, takes: key.takes, about: key.about,
            )
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let output = Output(settings: entries, unknown: unknown, problems: settings.problems)
        print((try? encoder.encode(output)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}")
    }

    /// Writes the line, or removes it for the default.
    private static func write(_ key: CalmSettings.Key, _ value: String?) {
        do {
            try CalmSettings.save(key.name, value)
        } catch {
            fail("couldn't write \(CalmSettings.standardURL.path): \(error.localizedDescription)")
        }
    }

    /// Has the running Calm read config.toml again, as Reload Configuration does. After the line
    /// saying what was written, so a warning here reads as a note on it: stdout is flushed first,
    /// since piped it would otherwise come out after the warning on stderr.
    private static func applyInRunningCalm() {
        fflush(stdout)
        do {
            let response = try ControlClient.send(ControlRequest(cmd: .reload), timeout: 2)
            if !response.ok {
                warn("Calm didn't apply it (\(response.error ?? "no reason given")): Calm → Reload Configuration (⌘⇧,) does")
            }
        } catch let error as ControlClient.ClientError {
            if case .notRunning = error {
                warn("Calm isn't running; it applies when Calm starts")
            } else {
                warn("Calm didn't answer: Calm → Reload Configuration (⌘⇧,) applies it")
            }
        } catch {
            warn("Calm's answer couldn't be read: Calm → Reload Configuration (⌘⇧,) applies it")
        }
    }

    /// The themes there are: the ones in the app this calm came with, and the user's own. Nil
    /// outside an app, where the built-in ones can't be listed.
    private static func themeNames() -> [String]? {
        let executable = Bundle.main.executableURL ?? URL(filePath: CommandLine.arguments[0])
        guard let app = CalmLaunch.app(containing: executable) else { return nil }
        let builtIn = app.appending(path: "Contents/Resources/Themes", directoryHint: .isDirectory)
        return ThemeLibrary(folders: [builtIn, ThemeLibrary.userFolder]).themes.map(\.name)
    }
}

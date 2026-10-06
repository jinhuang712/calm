@testable import CalmAgents
import Foundation
import Testing

/// Send with ⌘ Return: what Calm writes into each agent's own key settings, and that it only ever
/// adds and removes its own bindings. The bindings themselves were checked against the installed
/// agents in a pty (see `SendKeys`); these check the files.
struct SendKeysTests {
    private let home = URL(filePath: "/Users/me", directoryHint: .isDirectory)

    private func folder() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "calm-send-keys-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func json(_ url: URL) throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
    }

    // MARK: Where

    @Test func `each agent's file, and the variables that move it`() throws {
        let claude = try #require(ClaudeCodeAdapter().sendKeys(home: home, inherited: [:]))
        #expect(claude.file.path == "/Users/me/.claude/keybindings.json")
        #expect(claude.appliesLive)
        let moved = try #require(ClaudeCodeAdapter().sendKeys(home: home, inherited: ["CLAUDE_CONFIG_DIR": "/tmp/claude"]))
        #expect(moved.file.path == "/tmp/claude/keybindings.json")

        let pi = try #require(PiAdapter().sendKeys(home: home, inherited: [:]))
        #expect(pi.file.path == "/Users/me/.pi/agent/keybindings.json")
        #expect(try #require(PiAdapter().sendKeys(home: home, inherited: ["PI_CODING_AGENT_DIR": "/tmp/pi"])).file.path
            == "/tmp/pi/keybindings.json")

        let openCode = try #require(OpenCodeAdapter().sendKeys(home: home, inherited: [:]))
        #expect(openCode.file.path == "/Users/me/.config/opencode/cli.json")
        #expect(!openCode.appliesLive)
    }

    @Test func `none for Codex: its keymap can't bind ⌘`() {
        #expect(CodexAdapter().sendKeys(home: home, inherited: [:]) == nil)
    }

    // MARK: Claude Code

    @Test func `a new keybindings.json for Claude Code holds Calm's two blocks`() throws {
        let keys = try #require(try ClaudeCodeAdapter().sendKeys(home: folder(), inherited: [:]))
        #expect(SendKeysFile.state(of: keys) == .off)
        #expect(try SendKeysFile.turnOn(keys) == .on)
        let file = try json(keys.file)
        let bindings = try #require(file["bindings"] as? [[String: Any]])
        #expect(bindings.count == 2)
        #expect(bindings[0]["context"] as? String == "Chat")
        #expect(bindings[0]["bindings"] as? [String: String] == ["enter": "chat:newline", "cmd+enter": "chat:queueSubmit"])
        #expect(bindings[1]["bindings"] as? [String: String] == ["enter": "autocomplete:accept"])
        #expect(file["$schema"] as? String == "https://www.schemastore.org/claude-code-keybindings.json")
        #expect(SendKeysFile.state(of: keys) == .on)

        // Off again: a file that held only Calm's blocks goes.
        try SendKeysFile.turnOff(keys)
        #expect(!FileManager.default.fileExists(atPath: keys.file.path))
        #expect(SendKeysFile.state(of: keys) == .off)
    }

    @Test func `the user's own blocks stay, after Calm's, and come back as they were`() throws {
        let keys = try #require(try ClaudeCodeAdapter().sendKeys(home: folder(), inherited: [:]))
        let own = """
        {
          "$schema": "https://www.schemastore.org/claude-code-keybindings.json",
          "bindings": [
            { "context": "Chat", "bindings": { "ctrl+e": "chat:externalEditor", "ctrl+s": null } },
            { "context": "Global", "bindings": { "ctrl+t": "app:toggleTodos" } }
          ]
        }
        """
        try FileManager.default.createDirectory(at: keys.file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try own.write(to: keys.file, atomically: true, encoding: .utf8)
        let before = try json(keys.file)

        #expect(try SendKeysFile.turnOn(keys) == .on)
        let bindings = try #require(try json(keys.file)["bindings"] as? [[String: Any]])
        #expect(bindings.map { $0["context"] as? String } == ["Chat", "Autocomplete", "Chat", "Global"])
        #expect(bindings[2]["bindings"] as? NSDictionary == ["ctrl+e": "chat:externalEditor", "ctrl+s": NSNull()] as NSDictionary)

        // Turning it on twice changes nothing; off gives back the user's file as it was.
        let once = try String(contentsOf: keys.file, encoding: .utf8)
        try SendKeysFile.turnOn(keys)
        #expect(try String(contentsOf: keys.file, encoding: .utf8) == once)
        try SendKeysFile.turnOff(keys)
        #expect(try NSDictionary(dictionary: json(keys.file)).isEqual(to: before))
    }

    @Test func `a block of the user's for Return in the prompt wins, and says so`() throws {
        let keys = try #require(try ClaudeCodeAdapter().sendKeys(home: folder(), inherited: [:]))
        try FileManager.default.createDirectory(at: keys.file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try #"{"bindings":[{"context":"Chat","bindings":{"Return":"chat:submit"}}]}"#.write(
            to: keys.file,
            atomically: true,
            encoding: .utf8,
        )
        #expect(try SendKeysFile.turnOn(keys) == .ownKeys)
        #expect(SendKeysFile.state(of: keys) == .ownKeys)

        // The same binding as Calm's isn't the user overriding it.
        try #"{"bindings":[{"context":"Chat","bindings":{"enter":"chat:newline"}}]}"#.write(
            to: keys.file,
            atomically: true,
            encoding: .utf8,
        )
        #expect(try SendKeysFile.turnOn(keys) == .on)
    }

    @Test func `keystrokes compare as Claude Code reads them`() {
        #expect(SendKeysFile.normalized("Super+Return") == "cmd+enter")
        #expect(SendKeysFile.normalized("command+enter") == "cmd+enter")
        #expect(SendKeysFile.normalized("shift+ctrl+K") == "ctrl+shift+k")
        #expect(SendKeysFile.normalized("enter") == "enter")
    }

    // MARK: pi and OpenCode

    @Test func `pi gets its three actions, beside the user's own`() throws {
        let keys = try #require(try PiAdapter().sendKeys(home: folder(), inherited: [:]))
        try FileManager.default.createDirectory(at: keys.file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try #"{"app.model.select": "ctrl+l"}"#.write(to: keys.file, atomically: true, encoding: .utf8)

        #expect(try SendKeysFile.turnOn(keys) == .on)
        let file = try json(keys.file)
        #expect(file["tui.input.submit"] as? [String] == ["super+enter", "enter", "ctrl+s"])
        #expect(file["tui.input.newLine"] as? [String] == ["enter", "shift+enter", "ctrl+j"])
        #expect(file["tui.select.confirm"] as? [String] == ["enter", "super+enter"])
        #expect(file["app.model.select"] as? String == "ctrl+l")

        try SendKeysFile.turnOff(keys)
        #expect(try NSDictionary(dictionary: json(keys.file)).isEqual(to: ["app.model.select": "ctrl+l"]))
    }

    @Test func `a key the user set for one of the actions leaves pi alone`() throws {
        let keys = try #require(try PiAdapter().sendKeys(home: folder(), inherited: [:]))
        try FileManager.default.createDirectory(at: keys.file.deletingLastPathComponent(), withIntermediateDirectories: true)
        let own = #"{"tui.input.newLine": ["shift+enter"]}"#
        try own.write(to: keys.file, atomically: true, encoding: .utf8)

        #expect(try SendKeysFile.turnOn(keys) == .ownKeys)
        #expect(try String(contentsOf: keys.file, encoding: .utf8) == own)
        try SendKeysFile.turnOff(keys)
        #expect(try String(contentsOf: keys.file, encoding: .utf8) == own)
    }

    @Test func `in cli.json OpenCode's go under keybinds, and the rest stays`() throws {
        let keys = try #require(try OpenCodeAdapter().sendKeys(home: folder(), inherited: [:]))
        try FileManager.default.createDirectory(at: keys.file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try #"{"theme": {"name": "system"}, "keybinds": {"app.exit": "ctrl+q"}, "scroll_speed": 3}"#
            .write(to: keys.file, atomically: true, encoding: .utf8)

        #expect(try SendKeysFile.turnOn(keys) == .on)
        let file = try json(keys.file)
        let keybinds = try #require(file["keybinds"] as? [String: String])
        #expect(keybinds == [
            "app.exit": "ctrl+q",
            "input.submit": "super+return",
            "input.newline": "return,shift+return,ctrl+return,alt+return,ctrl+j",
        ])
        #expect(file["scroll_speed"] as? Int == 3)

        try SendKeysFile.turnOff(keys)
        let after = try json(keys.file)
        #expect(after["keybinds"] as? [String: String] == ["app.exit": "ctrl+q"])
        #expect((after["theme"] as? [String: String]) == ["name": "system"])
    }

    @Test func `a cli.json Calm created goes again when it's off`() throws {
        let keys = try #require(try OpenCodeAdapter().sendKeys(home: folder(), inherited: [:]))
        try SendKeysFile.turnOn(keys)
        #expect(SendKeysFile.state(of: keys) == .on)
        try SendKeysFile.turnOff(keys)
        #expect(!FileManager.default.fileExists(atPath: keys.file.path))
    }

    // MARK: Files Calm leaves alone

    @Test func `a file with comments or broken JSON is left as it is`() throws {
        for adapter in [OpenCodeAdapter() as any AgentAdapter, PiAdapter(), ClaudeCodeAdapter()] {
            let keys = try #require(try adapter.sendKeys(home: folder(), inherited: [:]))
            try FileManager.default.createDirectory(at: keys.file.deletingLastPathComponent(), withIntermediateDirectories: true)
            for text in ["// mine\n{\"theme\": {\"name\": \"calm\"}}\n", "{\"keybinds\": ", "[1, 2]"] {
                try text.write(to: keys.file, atomically: true, encoding: .utf8)
                #expect(try SendKeysFile.turnOn(keys) == .unreadable)
                try SendKeysFile.turnOff(keys)
                #expect(try String(contentsOf: keys.file, encoding: .utf8) == text)
                #expect(SendKeysFile.state(of: keys) == .unreadable)
            }
        }
    }

    // MARK: The text

    @Test func `the files read as people write them`() {
        let text = JSONText.text([
            "bindings": [["bindings": ["enter": "chat:newline"], "context": "Chat"]],
            "$schema": "https://example.com/a.json",
            "keys": ["enter", "shift+enter"],
            "on": true,
            "size": 3,
        ] as [String: Any])
        #expect(text == """
        {
          "$schema": "https://example.com/a.json",
          "bindings": [
            {
              "context": "Chat",
              "bindings": {
                "enter": "chat:newline"
              }
            }
          ],
          "keys": ["enter", "shift+enter"],
          "on": true,
          "size": 3
        }
        """)
    }
}

@testable import CalmAgents
import CalmModel
import Foundation
import Testing

struct OpenCodeThemeTests {
    private let adapter = OpenCodeAdapter()
    private let variable = "OPENCODE_CLI_CONFIG_CONTENT"

    private func temporaryHome() throws -> URL {
        let home = FileManager.default.temporaryDirectory.appending(path: "calm-home-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        return home
    }

    private func write(_ text: String, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
    }

    private func cliConfig(in home: URL) -> URL {
        home.appending(path: ".config/opencode/cli.json")
    }

    @Test func `with no cli config, OpenCode is asked for its system theme`() throws {
        let home = try temporaryHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let environment = adapter.shellEnvironment(home: home, inherited: [:])
        let value = try #require(environment[variable])
        let config = try #require(try JSONSerialization.jsonObject(with: Data(value.utf8)) as? [String: [String: String]])
        #expect(config == ["theme": ["name": "system"]])
        #expect(environment.count == 1)
    }

    @Test func `a real cli config that names no theme still gets the system theme`() throws {
        let home = try temporaryHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let fixture = try #require(Bundle.module.url(forResource: "cli", withExtension: "json", subdirectory: "Fixtures/opencode"))
        try FileManager.default.createDirectory(at: cliConfig(in: home).deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: fixture, to: cliConfig(in: home))
        #expect(adapter.shellEnvironment(home: home, inherited: [:])[variable] == OpenCodeAdapter.systemTheme)
    }

    @Test func `a theme the user named is left alone`() throws {
        let home = try temporaryHome()
        defer { try? FileManager.default.removeItem(at: home) }
        try write(#"{ "theme": { "name": "tokyonight", "mode": "dark" } }"#, to: cliConfig(in: home))
        #expect(adapter.shellEnvironment(home: home, inherited: [:]).isEmpty)
    }

    @Test func `the config is read as JSONC, with comments and trailing commas`() throws {
        let home = try temporaryHome()
        defer { try? FileManager.default.removeItem(at: home) }
        try write("""
        {
          // picked in OpenCode
          "theme": { "name": "nord", },
        }
        """, to: cliConfig(in: home))
        #expect(adapter.shellEnvironment(home: home, inherited: [:]).isEmpty)
    }

    @Test func `a mode alone, a null name or an unreadable file names no theme`() throws {
        let home = try temporaryHome()
        defer { try? FileManager.default.removeItem(at: home) }
        for text in [#"{ "theme": { "mode": "light" } }"#, #"{ "theme": { "name": null } }"#, #"{ "theme": "#, ""] {
            try write(text, to: cliConfig(in: home))
            #expect(adapter.shellEnvironment(home: home, inherited: [:])[variable] == OpenCodeAdapter.systemTheme, "\(text)")
        }
    }

    @Test func `the user's own inline config wins`() throws {
        let home = try temporaryHome()
        defer { try? FileManager.default.removeItem(at: home) }
        #expect(adapter.shellEnvironment(home: home, inherited: [variable: #"{"animations":false}"#]).isEmpty)
        // OpenCode ignores an empty value, so Calm may still set one.
        #expect(adapter.shellEnvironment(home: home, inherited: [variable: ""])[variable] == OpenCodeAdapter.systemTheme)
    }

    @Test func `the config is found where OpenCode looks for it`() {
        let home = URL(filePath: "/Users/someone")
        #expect(OpenCodeAdapter.cliConfigURL(home: home, inherited: [:]).path == "/Users/someone/.config/opencode/cli.json")
        #expect(OpenCodeAdapter.cliConfigURL(home: home, inherited: ["XDG_CONFIG_HOME": "/xdg"]).path == "/xdg/opencode/cli.json")
        let both = ["XDG_CONFIG_HOME": "/xdg", "OPENCODE_CONFIG_DIR": "/custom"]
        #expect(OpenCodeAdapter.cliConfigURL(home: home, inherited: both).path == "/custom/cli.json")
        let empty = ["XDG_CONFIG_HOME": "", "OPENCODE_CONFIG_DIR": ""]
        #expect(OpenCodeAdapter.cliConfigURL(home: home, inherited: empty).path == "/Users/someone/.config/opencode/cli.json")
    }

    @Test func `other agents add nothing to the shell`() throws {
        let home = try temporaryHome()
        defer { try? FileManager.default.removeItem(at: home) }
        for adapter in Agents.adapters where adapter.kind != .openCode {
            #expect(adapter.shellEnvironment(home: home, inherited: [:]).isEmpty, "\(adapter.kind)")
        }
    }
}

@testable import Calm
import CalmModel
import Foundation
import Testing

@MainActor
struct AgentIntegrationsTests {
    private func temporaryHome() throws -> URL {
        let home = FileManager.default.temporaryDirectory.appending(path: "calm-home-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        return home
    }

    @Test func `a new session's shell gets Claude Code's hooks and OpenCode's theme`() throws {
        let home = try temporaryHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let environment = AgentIntegrations.environment(settings: CalmSettings(), inherited: [:], home: home)
        #expect(environment["CLAUDE_CODE_PLUGIN_DIRS"] == AgentIntegrations.claudeCodePluginDirectory.path)
        #expect(environment["OPENCODE_CLI_CONFIG_CONTENT"] == #"{"theme":{"name":"system"}}"#)
    }

    @Test func `turning Claude Code's hooks off leaves OpenCode's theme`() throws {
        let home = try temporaryHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let settings = CalmSettings(text: "[agents.claude-code]\nhooks = false\n")
        let environment = AgentIntegrations.environment(settings: settings, inherited: [:], home: home)
        #expect(environment["CLAUDE_CODE_PLUGIN_DIRS"] == nil)
        #expect(environment["OPENCODE_CLI_CONFIG_CONTENT"] != nil)
    }
}

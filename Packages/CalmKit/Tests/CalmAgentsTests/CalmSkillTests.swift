@testable import CalmAgents
import Foundation
import Testing

/// DESIGNS.md → Each agent learns the `calm` command through its own skill door: one Agent Skills file for all four agents.
struct CalmSkillTests {
    private let lines = CalmSkill.text.split(separator: "\n", omittingEmptySubsequences: false)

    @Test func `the frontmatter is what every agent reads`() throws {
        #expect(lines.first == "---")
        #expect(lines.count { $0 == "---" } == 2)
        // pi and the Agent Skills format want the name to match the folder (`skills/calm/`).
        #expect(lines.contains("name: \(CalmSkill.name)"))
        // In every session's context. pi cuts at 1,024 characters, Claude Code at 1,536; it stays far below.
        let description = try #require(lines.first { $0.hasPrefix("description: ") })
        #expect(description.count < 400)
        // It would make Claude Code ask before loading the skill, and no other agent reads it.
        #expect(!lines.contains { $0.hasPrefix("allowed-tools:") })
    }

    @Test func `the marker tells Calm's file from the user's`() {
        #expect(CalmSkill.text.contains(AgentSetup.marker))
    }

    @Test func `it keeps an agent from moving the user or reporting for Calm`() {
        // An agent must not move the user's attention (specs/CLI.md → Not planned).
        #expect(CalmSkill.text.contains("calm fork --background"))
        #expect(CalmSkill.text.contains("Do not run `calm status` or `calm notify`"))
        // A permission rule can allow `calm …`, never `"$CALM_CLI" …`, and an agent that joins both asks.
        #expect(CalmSkill.text.contains("Do not join the two in one command."))
        // A fork is looked up when asked, never waited on (specs/CLI.md → Not planned: `calm wait`).
        #expect(CalmSkill.text.contains("`calm show <session id>` gives its state and last reply. Do not wait or poll for it."))
    }
}

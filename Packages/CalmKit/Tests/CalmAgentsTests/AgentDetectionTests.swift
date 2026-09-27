@testable import CalmAgents
import CalmModel
import Foundation
import Testing

struct AgentDetectionTests {
    private func process(_ executable: String, _ arguments: [String]) -> ProcessSnapshot {
        ProcessSnapshot(processID: 1, executablePath: executable, arguments: arguments)
    }

    @Test func `native binaries by name`() {
        #expect(Agents.detect(process("/Users/me/.local/bin/claude", ["claude"])) == .claudeCode)
        #expect(Agents.detect(process("/opt/homebrew/bin/codex", ["codex", "--full-auto"])) == .codex)
        #expect(Agents.detect(process("/Users/me/.opencode/bin/opencode", ["opencode"])) == .openCode)
        #expect(Agents.detect(process("/Users/me/.bun/bin/omp", ["omp"])) == .omp)
    }

    @Test func `per-platform builds and launchers`() {
        let codexBinary = "/usr/local/lib/node_modules/@openai/codex/vendor/aarch64-apple-darwin/codex/codex-aarch64-apple-darwin"
        #expect(Agents.detect(process(codexBinary, [codexBinary])) == .codex)
        #expect(Agents.detect(process("/usr/local/bin/node", ["node", "/usr/local/lib/node_modules/@openai/codex/bin/codex.js"])) == .codex)
    }

    @Test func `scripts run by node or bun`() {
        let claudeScript = "/usr/local/lib/node_modules/@anthropic-ai/claude-code/cli.js"
        #expect(Agents.detect(process("/opt/homebrew/bin/node", ["node", "--no-warnings", claudeScript])) == .claudeCode)
        #expect(Agents.detect(process("/opt/homebrew/bin/node", ["node", "/opt/homebrew/bin/pi"])) == .pi)
        let piScript = "/Users/me/.npm-global/lib/node_modules/@mariozechner/pi-coding-agent/dist/cli.js"
        #expect(Agents.detect(process("/opt/homebrew/bin/node", ["node", piScript])) == .pi)
        #expect(Agents.detect(process("/Users/me/.bun/bin/bun", ["bun", "/Users/me/src/oh-my-pi/packages/cli/src/index.ts"])) == .omp)
    }

    @Test func `other programs are not agents`() {
        #expect(Agents.detect(process("/usr/bin/vim", ["vim", "claude.md"])) == nil)
        #expect(Agents.detect(process("/opt/homebrew/bin/node", ["node", "server.js"])) == nil)
        #expect(Agents.detect(process("/bin/sleep", ["sleep", "30"])) == nil)
        // A script named after an agent, given as an argument to an unrelated program, doesn't count.
        #expect(Agents.detect(process("/usr/bin/less", ["less", "/tmp/codex"])) == nil)
    }

    @Test func `argument buffers from the kernel`() {
        var bytes = withUnsafeBytes(of: Int32(3)) { Array($0) }
        bytes += Array("/opt/homebrew/bin/node".utf8) + [0, 0, 0, 0]
        for argument in ["node", "/opt/homebrew/bin/pi", "--continue"] {
            bytes += Array(argument.utf8) + [0]
        }
        bytes += Array("HOME=/Users/me".utf8) + [0]
        let snapshot = ProcessInspector.parseArguments(bytes, processID: 42)
        #expect(snapshot?.executablePath == "/opt/homebrew/bin/node")
        #expect(snapshot?.arguments == ["node", "/opt/homebrew/bin/pi", "--continue"])
        #expect(ProcessInspector.parseArguments([1, 0], processID: 1) == nil)
    }

    @Test func `this process can be inspected`() throws {
        let snapshot = try #require(ProcessInspector.snapshot(of: getpid()))
        #expect(!snapshot.executablePath.isEmpty)
        #expect(!snapshot.arguments.isEmpty)
    }

    @Test func `every agent has an adapter`() {
        for kind in AgentKind.allCases {
            #expect(Agents.adapter(for: kind) != nil)
        }
    }
}

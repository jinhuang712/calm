import CalmControl
import Testing

struct StatusArgumentsTests {
    @Test func `a state and a message`() {
        let parsed = StatusArguments.parse(["needs-you", "Allow", "Bash"], defaultSession: "S1")
        #expect(parsed.session == "S1")
        #expect(parsed.words == ["needs-you", "Allow", "Bash"])
        #expect(parsed.agent == nil)
    }

    @Test func `options may come before the state`() {
        let parsed = StatusArguments.parse(
            ["--agent", "pi", "--transcript", "/x/a b.jsonl", "--agent-session", "abc", "working"], defaultSession: "S1",
        )
        #expect(parsed.agent == "pi")
        #expect(parsed.transcript == "/x/a b.jsonl")
        #expect(parsed.agentSession == "abc")
        #expect(parsed.words == ["working"])
    }

    @Test func `--session overrides the session Calm started the shell in`() {
        #expect(StatusArguments.parse(["--session", "S2", "done"], defaultSession: "S1").session == "S2")
    }

    @Test func `an empty or missing default session is none`() {
        #expect(StatusArguments.parse(["done"], defaultSession: "").session == nil)
        #expect(StatusArguments.parse(["done"], defaultSession: nil).session == nil)
    }

    @Test func `an option missing its value is dropped, not taken for the state`() {
        let parsed = StatusArguments.parse(["working", "--transcript"], defaultSession: nil)
        #expect(parsed.transcript == nil)
        #expect(parsed.words == ["working"])
    }

    @Test func `options that aren't ours stay in the message`() {
        #expect(StatusArguments.parse(["needs-you", "--force", "is", "risky"], defaultSession: nil).words == [
            "needs-you",
            "--force",
            "is",
            "risky",
        ])
    }
}

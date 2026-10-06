import CalmControl
import Foundation
import Testing

struct CLIOutputTests {
    @Test func `a session is one line of tab-separated fields`() {
        let session = ControlResponse.SessionInfo(
            id: "A1", title: "Fix flaky test", project: "calm", directory: "/dev/calm", state: "needs-you", agent: "Claude Code",
        )
        #expect(CLIOutput.line(for: session) == "calm\tFix flaky test\tneeds-you\tClaude Code\t/dev/calm")
    }

    @Test func `a session with no agent shows a dash`() {
        let session = ControlResponse.SessionInfo(id: "A2", title: "zsh", project: "home", directory: "/Users/me", state: "idle")
        #expect(CLIOutput.line(for: session) == "home\tzsh\tidle\t-\t/Users/me")
    }

    @Test func `ages round down to the largest whole unit`() {
        #expect(CLIOutput.age(seconds: 59) == "0m")
        #expect(CLIOutput.age(seconds: 1800) == "30m")
        #expect(CLIOutput.age(seconds: 3599) == "59m")
        #expect(CLIOutput.age(seconds: 3600) == "1h")
        #expect(CLIOutput.age(seconds: 86399) == "23h")
        #expect(CLIOutput.age(seconds: 86400) == "1d")
        #expect(CLIOutput.age(seconds: 3 * 86400 + 7200) == "3d")
    }

    @Test func `a time ahead of this clock is 0m`() {
        #expect(CLIOutput.age(seconds: -600) == "0m")
    }

    @Test func `a search result is its metadata, then its matching text on one indented line`() {
        let now = Date(timeIntervalSince1970: 100_000)
        let hit = ControlResponse.SearchHit(
            title: "Fix the auth race", agent: "Claude Code", directory: "/Users/me/dev/calm", lastActive: 100_000 - 1800,
            snippet: "found the \u{2}race\u{3} in\nTokenStore", transcript: "/t.jsonl",
        )
        #expect(CLIOutput.lines(for: hit, now: now, styled: false) == [
            "30m\tClaude Code\tcalm\tFix the auth race",
            "    found the race in TokenStore",
        ])
    }

    @Test func `a result ends with its conversation's id, for calm show`() {
        let hit = ControlResponse.SearchHit(
            title: "Fix", agent: "Codex", directory: "/x/api", lastActive: 0, snippet: "", transcript: "/t.jsonl",
            conversation: "019a7c11-aaaa",
        )
        #expect(CLIOutput.lines(for: hit, now: Date(timeIntervalSince1970: 60), styled: false) == ["1m\tCodex\tapi\tFix\t019a7c11-aaaa"])
    }

    @Test func `a result with no folder shows a dash, and no matching text adds no line`() {
        let hit = ControlResponse.SearchHit(
            title: "Old one", agent: "Codex", directory: nil, lastActive: 0, snippet: "", transcript: "/t.jsonl",
        )
        #expect(CLIOutput.lines(for: hit, now: Date(timeIntervalSince1970: 3 * 86400), styled: false) == ["3d\tCodex\t-\tOld one"])
    }

    @Test func `on a terminal the metadata is dim, the title and the matches bold`() {
        let hit = ControlResponse.SearchHit(
            title: "Fix", agent: "pi", directory: "/x/calm", lastActive: 0, snippet: "the \u{2}race\u{3}", transcript: "/t.jsonl",
        )
        #expect(CLIOutput.lines(for: hit, now: Date(timeIntervalSince1970: 120), styled: true) == [
            "\u{1B}[2m2m\tpi\tcalm\u{1B}[0m\t\u{1B}[1mFix\u{1B}[0m",
            "    the \u{1B}[1mrace\u{1B}[0m",
        ])
    }
}

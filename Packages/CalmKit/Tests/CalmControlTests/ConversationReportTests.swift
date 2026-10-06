import CalmControl
import Foundation
import Testing

struct ConversationReportTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func report(prompts: Int = 5) -> ConversationReport {
        var messages: [ConversationReport.Message] = []
        for number in 1 ... prompts {
            messages.append(.init(fromUser: true, text: "prompt \(number)"))
            messages.append(.init(fromUser: false, text: "reply \(number)\nsecond line"))
        }
        return ConversationReport(
            id: "0f9c2a7e-1111", title: "Fix the flaky auth test", agent: "Claude Code",
            folder: "/Users/me/dev/calm", branch: "wt-auth-fix",
            started: now.timeIntervalSince1970 - 3 * 86400, lastActive: now.timeIntervalSince1970 - 7200,
            openIn: "a1b2c3d4", openState: "done", recap: "Fixed the race in TokenStore.", tasks: "4/5 · Opening the PR",
            resume: "claude --resume '0f9c2a7e-1111'", fork: "claude --resume '0f9c2a7e-1111' --fork-session",
            transcript: "/Users/me/.claude/projects/-Users-me-dev-calm/0f9c2a7e-1111.jsonl", messages: messages,
        )
    }

    @Test func `the summary says what it was for, where it got to, and how to go back`() {
        let text = report().text(now: now, width: 80, home: "/Users/me")
        #expect(text == """
        Fix the flaky auth test · Claude Code
        ~/dev/calm · on wt-auth-fix
        Started 3 d ago · last active 2 h ago · 5 prompts, 5 replies
        Open in session a1b2c3d4 · done

        Asked
          prompt 1

        Recent prompts
          3  prompt 3
          4  prompt 4
          5  prompt 5

        Recap
          Fixed the race in TokenStore.

        Tasks  4/5 · Opening the PR

        Last reply
          reply 5
          second line

        Resume      claude --resume '0f9c2a7e-1111'
        Fork        claude --resume '0f9c2a7e-1111' --fork-session
        Transcript  ~/.claude/projects/-Users-me-dev-calm/0f9c2a7e-1111.jsonl
        Id          0f9c2a7e-1111
        """)
    }

    @Test func `with few prompts, the recent ones don't repeat the first`() {
        let text = report(prompts: 2).text(now: now, home: "/Users/me")
        #expect(text.contains("Recent prompts\n  2  prompt 2\n\n"))
        #expect(!report(prompts: 1).text(now: now).contains("Recent prompts"))
    }

    @Test func `--prompts lists every prompt, --all the whole conversation`() {
        let prompts = report(prompts: 3).text(.prompts, now: now)
        #expect(prompts.contains("Prompts\n  1  prompt 1\n  2  prompt 2\n  3  prompt 3\n\n"))
        let all = report(prompts: 2).text(.all, now: now)
        #expect(all.contains("You\n  prompt 1\n\nClaude Code\n  reply 1\n  second line\n\nYou\n  prompt 2"))
        #expect(!all.contains("Recap"))
    }

    @Test func `a long prompt is cut to the width, on one line`() {
        var long = report(prompts: 2)
        long.messages[2].text = String(repeating: "word ", count: 40) + "\nnext line"
        let line = long.text(now: now, width: 40).split(separator: "\n").first { $0.hasPrefix("  2  ") }
        #expect(line?.count == 40)
        #expect(line?.hasSuffix("…") == true)
    }

    @Test func `parts with nothing in them are left out`() {
        let bare = ConversationReport(
            id: "abc", title: "Untitled", agent: "pi", lastActive: now.timeIntervalSince1970 - 30,
            transcript: "/x/abc.jsonl", messages: [.init(fromUser: true, text: "hello")],
        )
        #expect(bare.text(now: now) == """
        Untitled · pi
        Last active 30 s ago · 1 prompt, 0 replies

        Asked
          hello

        Transcript  /x/abc.jsonl
        Id          abc
        """)
    }

    @Test func `a conversation known only from the prompt history says so`() {
        var gone = report(prompts: 2)
        gone.fromHistory = true
        gone.transcriptGone = true
        gone.resume = nil
        gone.fork = nil
        let text = gone.text(now: now)
        #expect(text.contains("Only its prompts are known: the agent deleted its transcript."))
        #expect(text.contains("(deleted)"))
        #expect(!text.contains("Resume"))
    }
}

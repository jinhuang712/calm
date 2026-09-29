@testable import CalmModel
import Testing

struct NotificationTextTests {
    private func body(_ message: String?, _ state: SessionState? = .done) -> String {
        NotificationText(state: state, sessionName: "Fix login", message: message).body
    }

    // MARK: Title

    @Test func `the title is a mark for the state, then the session's name`() {
        func title(_ state: SessionState?) -> String {
            NotificationText(state: state, sessionName: "Fix login", message: nil).title
        }
        #expect(title(.needsYou) == "✋ Fix login")
        #expect(title(.done) == "✅ Fix login")
        #expect(title(.failed) == "⚠️ Fix login")
        // Not a state change (`calm notify`): just the name.
        #expect(title(nil) == "Fix login")
    }

    @Test func `the warning sign is the emoji, not the text sign`() {
        let scalars = NotificationText(state: .failed, sessionName: "x", message: nil).title.unicodeScalars.map(\.value)
        #expect(scalars.prefix(2) == [0x26A0, 0xFE0F])
    }

    // MARK: Body

    @Test func `no message, no body`() {
        #expect(body(nil).isEmpty)
        #expect(body("").isEmpty)
        #expect(body("  \n ").isEmpty)
    }

    @Test func `a body that only repeats the title is left out`() {
        #expect(body("fix login").isEmpty)
    }

    @Test func `a plain message stays as it is`() {
        #expect(body("Allow Bash: rm -rf build/", .needsYou) == "Allow Bash: rm -rf build/")
        #expect(body("Finished after 12 s") == "Finished after 12 s")
    }

    @Test func `headings are dropped and the first sentences that fit are kept`() {
        // What OpenCode's answer looked like in a banner: markers showing, cut in the middle of a word.
        let message = """
        ## Short answer
        Nothing looks broken. Two separate things on that card are easy to misread.

        ### 1. "Not running" is correct right now
        The agent isn't attached to a terminal in Calm, so the card can't know it's busy.
        """
        #expect(body(message) == "Nothing looks broken. Two separate things on that card are easy to misread.")
    }

    @Test func `a message that is only headings still says something`() {
        #expect(body("## Summary") == "Summary")
    }

    @Test func `a question wins when the agent asks`() {
        let message = """
        I found two migrations that look unused.

        - 0004_users.sql
        - 0007_old.sql

        Should I delete the old migration too?
        """
        #expect(body(message, .needsYou) == "Should I delete the old migration too?")
    }

    @Test func `the last question is the ask, even with options after it`() {
        let message = "Which approach do you prefer?\n1. Rewrite it\n2. Patch it"
        #expect(body(message, .needsYou) == "Which approach do you prefer?")
    }

    @Test func `a finished turn leads with the result, not the question it ends with`() {
        let message = """
        Renamed the config keys and updated every caller in the project so the old names no longer appear anywhere. \
        Want me to add a migration for existing config files?
        """
        let text = body(message, .done)
        #expect(text.hasPrefix("Renamed the config keys"))
        #expect(!text.contains("migration"))
    }

    @Test func `a line that isn't a sentence isn't glued to the next`() {
        #expect(body("Two things to check:\n- the token\n- the clock") == "Two things to check:")
    }

    @Test func `inline Markdown is taken out`() {
        let message = "**Done.** Updated `README.md`, _both_ *guides* and [the docs](https://example.com/docs). ~~Old~~ ![logo](x.png)"
        #expect(body(message) == "Done. Updated README.md, both guides and the docs. Old logo")
    }

    @Test func `underscores and stars inside words stay`() {
        #expect(body("Renamed snake_case_name in file_name.py and 2*3 stays") == "Renamed snake_case_name in file_name.py and 2*3 stays")
    }

    @Test func `code blocks, rules, quotes and tables are not read out`() {
        let message = """
        Run this first:
        ```sh
        rm -rf build
        ```
        ---
        | a | b |
        > Then retry?
        """
        #expect(body(message, .needsYou) == "Then retry?")
    }

    @Test func `a message that is only code says nothing`() {
        #expect(body("```\nrm -rf build\n```").isEmpty)
    }

    @Test func `a dot inside a name doesn't end a sentence`() {
        #expect(body("Open Calm.app v1.2 now?", .needsYou) == "Open Calm.app v1.2 now?")
    }

    @Test func `a long sentence is cut at a word, with an ellipsis`() {
        let message = """
        This sentence keeps going and going without ever reaching a full stop \
        because the agent had a great deal to say about it
        """
        let text = body(message)
        #expect(text.hasSuffix("…"))
        #expect(text.count <= NotificationText.bodyWidth)
        // Not in the middle of a word.
        #expect(text.dropLast().split(separator: " ").allSatisfy { message.contains($0) })
        #expect(!text.dropLast().hasSuffix(" "))
    }

    @Test func `text with no spaces is cut where it stands`() {
        let text = body(String(repeating: "a", count: 300))
        #expect(text == String(repeating: "a", count: NotificationText.bodyWidth - 1) + "…")
    }

    // MARK: Chinese

    @Test func `sentences in Chinese end at their own marks`() {
        #expect(body("已经修好了。还要我加测试吗？", .needsYou) == "还要我加测试吗？")
        #expect(body("已经修好了。还要我加测试吗？", .done) == "已经修好了。还要我加测试吗？")
    }

    @Test func `wide characters take two columns`() {
        let text = body(String(repeating: "字", count: 80))
        #expect(text == String(repeating: "字", count: 49) + "…")
    }
}

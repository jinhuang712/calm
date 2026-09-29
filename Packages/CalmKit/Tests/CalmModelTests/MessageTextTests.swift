@testable import CalmModel
import Testing

struct MessageTextTests {
    private func recap(_ message: String?, asking: Bool = false) -> String? {
        MessageText.recap(message, asking: asking)
    }

    // MARK: Nothing to say

    @Test func `no message, no recap`() {
        #expect(recap(nil) == nil)
        #expect(recap("") == nil)
        #expect(recap("  \n \n") == nil)
    }

    @Test func `a message that is only code says nothing`() {
        #expect(recap("```\nrm -rf build\n```") == nil)
    }

    @Test func `a plain message stays as it is`() {
        #expect(recap("Finished after 12 s") == "Finished after 12 s")
        #expect(recap("Moved the token refresh behind the retry loop.") == "Moved the token refresh behind the retry loop.")
    }

    // MARK: Structure

    @Test func `headings are dropped and the paragraphs run on`() {
        let message = """
        ## Short answer
        Nothing looks broken. Two separate things on that card are easy to misread.

        ### 1. "Not running" is correct right now
        The agent isn't attached to a terminal in Calm, so the card can't know it's busy.
        """
        #expect(recap(message) == """
        Nothing looks broken. Two separate things on that card are easy to misread. \
        The agent isn't attached to a terminal in Calm, so the card can't know it's busy.
        """)
    }

    @Test func `a message that is only headings still says something`() {
        #expect(recap("## Summary") == "Summary")
    }

    /// The opening is the text of a real banner (an OpenCode answer, already one line when it
    /// reached Calm); the rest continues it.
    @Test func `markdown that arrived on one line is split at its heading marks`() {
        let message = """
        ## Short answer Nothing looks broken. Two separate things on that card are easy to misread. \
        ### 1. "Not running" is correct right now The agent isn't attached to a terminal in Calm, so the card can't tell.
        """
        // The label stays glued to the first sentence: a flat line doesn't say where a heading ends.
        #expect(recap(message) == """
        Short answer Nothing looks broken. Two separate things on that card are easy to misread. \
        "Not running" is correct right now The agent isn't attached to a terminal in Calm, so the card can't tell.
        """)
    }

    @Test func `list items are told apart, and the list's end is a full stop`() {
        #expect(recap("Two things to check:\n- the token\n- the clock") == "Two things to check: the token; the clock")
        let message = """
        I found two migrations that look unused.

        - 0004_users.sql
        - 0007_old.sql

        Should I delete the old migration too?
        """
        #expect(recap(message) ==
            "I found two migrations that look unused. 0004_users.sql; 0007_old.sql. Should I delete the old migration too?")
    }

    @Test func `numbers and task boxes are list marks`() {
        #expect(recap("Next:\n1. Rewrite it\n2) Patch it\n- [x] Ship it") == "Next: Rewrite it; Patch it; Ship it")
    }

    @Test func `hard-wrapped lines are one sentence`() {
        #expect(recap("Renamed the config keys\nand updated every caller.") == "Renamed the config keys and updated every caller.")
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
        #expect(recap(message) == "Run this first: Then retry?")
    }

    @Test func `a dot inside a name doesn't end a sentence`() {
        #expect(recap("Open Calm.app v1.2 now?") == "Open Calm.app v1.2 now?")
    }

    // MARK: Decoration

    @Test func `decoration is taken out`() {
        let message = "**Done.** Updated `README.md`, _both_ *guides* and [the docs](https://example.com/docs). ~~Old~~ ![logo](x.png)"
        // Single stars and underscores stay: only marks that clearly wrap words are decoration.
        #expect(recap(message) == "Done. Updated README.md, _both_ *guides* and the docs. Old logo")
    }

    @Test func `bold around code, and code around marks`() {
        #expect(recap("**Fixed `foo`** today") == "Fixed foo today")
        // What is in backticks is what was meant.
        #expect(recap("Updated `**/dist` and `**/build`") == "Updated **/dist and **/build")
        #expect(recap("Run ``echo `date` `` once") == "Run echo `date` once")
    }

    @Test func `a mark with no partner stays`() {
        #expect(recap("**not closed") == "**not closed")
        #expect(recap("a ` tick") == "a ` tick")
    }

    @Test func `an ask keeps its inline marks`() {
        let ask = "Allow Bash: echo `date` and **/dist and **bold**"
        #expect(recap(ask, asking: true) == ask)
    }

    @Test func `structure goes from an ask too`() {
        #expect(recap("## Question\nShould I go on?", asking: true) == "Should I go on?")
    }

    /// Commands are not Markdown, whether or not the state says they are an ask.
    @Test func `globs, exponents and dunders are not decoration`() {
        for text in [
            "Allow Bash: find . -name '*.py' -o -name '*.js'",
            "Allow Bash: rm -rf **/node_modules **/dist",
            "Allow Bash: ls *.md *.txt",
            "Allow Bash: echo $((2*3)) and $((4*5)) and 2**3",
            "Allow Bash: grep -r snake_case_name src/ | grep _private_",
            "Edit __init__.py and __main__.py",
            "Renamed snake_case_name in file_name.py",
        ] {
            #expect(recap(text) == text)
            #expect(recap(text, asking: true) == text)
        }
    }

    // MARK: Chinese

    @Test func `sentences in Chinese run on without a space`() {
        #expect(recap("已经修好了。\n还要我加测试吗？") == "已经修好了。还要我加测试吗？")
    }

    // MARK: Size

    @Test func `a long recap is cut at a word, with an ellipsis`() throws {
        let message = String(repeating: "and so it goes on ", count: 40)
        let text = try #require(recap(message))
        #expect(text.hasSuffix("…"))
        #expect(MessageText.width(of: text) <= MessageText.recapWidth)
        // Not in the middle of a word.
        #expect(text.dropLast().split(separator: " ").allSatisfy { ["and", "so", "it", "goes", "on"].contains($0) })
    }

    @Test func `wide characters take two columns`() throws {
        let text = try #require(recap(String(repeating: "字", count: 200)))
        #expect(text == String(repeating: "字", count: 139) + "…")
    }

    // MARK: Twice

    /// A message is made plain where it reaches Calm and may be shown by something that reads it
    /// again (a notification): reading it twice must change nothing.
    @Test func `a recap is unchanged by another`() throws {
        for message in [
            "## Short answer\nNothing looks broken. **Two** things are `easy` to misread.",
            "Two things to check:\n- the token\n- the clock\n\nShould I go on?",
            "## A Text one ### B more. ### 1. \"Quoted\" and more",
            "Allow Bash: find . -name '*.py'",
            "已经修好了。还要我加测试吗？",
            String(repeating: "and so it goes on ", count: 40),
        ] {
            for asking in [false, true] {
                let once = try #require(recap(message, asking: asking))
                #expect(recap(once, asking: asking) == once)
            }
        }
    }
}

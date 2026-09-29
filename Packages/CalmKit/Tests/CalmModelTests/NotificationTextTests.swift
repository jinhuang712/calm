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

    /// What someone is asked to allow must reach the banner exactly: nothing here is Markdown.
    @Test func `a command is never read as Markdown`() {
        for command in [
            "Allow Bash: find . -name '*.py' -o -name '*.js'",
            "Allow Bash: rm -rf **/node_modules **/dist",
            "Allow Bash: echo `date` > out.txt",
            "Allow Bash: grep -r snake_case_name src/ | grep _private_",
            "Allow Bash: # step 1 ls",
            "Allow Bash: echo $((2*3)) and $((4*5))",
        ] {
            #expect(body(command, .needsYou) == command)
        }
    }

    @Test func `a question wins when the agent asks`() {
        let message = "I found two migrations that look unused. Should I delete the old migration too?"
        #expect(body(message, .needsYou) == "Should I delete the old migration too?")
    }

    @Test func `the last question is the ask`() {
        let message = "Is it the token? Or the clock? Tell me which."
        #expect(body(message, .needsYou) == "Or the clock?")
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

    @Test func `the first sentences are kept while they fit`() {
        #expect(body("One. Two. Three.") == "One. Two. Three.")
        let first = "A sentence of some length that says one thing."
        let second = "Another sentence saying a second thing."
        let third = "A third that no longer fits in the banner at all, however it is worded."
        #expect(body("\(first) \(second) \(third)") == "\(first) \(second)")
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

    // MARK: From an agent's words

    /// The opening is the text of a real banner (an OpenCode answer, already one line when it
    /// reached Calm); the rest continues it.
    private static let flattenedAnswer = """
    ## Short answer Nothing looks broken. Two separate things on that card are easy to misread. \
    ### 1. "Not running" is correct right now The agent isn't attached to a terminal in Calm, so the card can't tell.
    """

    @Test func `an agent's Markdown, flattened, reaches the banner without its marks`() {
        for state in [SessionState.needsYou, .done] {
            let message = MessageText.recap(Self.flattenedAnswer, asking: state == .needsYou)
            let text = body(message, state)
            #expect(!text.contains("#"))
            // What is asked for is the sentences, not a label glued to them: a flat line doesn't
            // say where a heading ends (MessageText).
            #expect(text.hasSuffix("Two separate things on that card are easy to misread."))
        }
    }

    @Test func `an agent's list and question come out as the question`() {
        let message = MessageText.recap("""
        I found two migrations that look unused.

        - 0004_users.sql
        - 0007_old.sql

        Should I delete the old migration too?
        """, asking: true)
        #expect(body(message, .needsYou) == "Should I delete the old migration too?")
    }
}

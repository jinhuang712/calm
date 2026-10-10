@testable import CalmAgents
import Testing

/// ⌘N's command as the shell would split it, so a resume can read options out of it.
struct ShellWordsTests {
    @Test func `blanks separate words, quotes and backslashes keep them together`() {
        #expect(ShellWords.split("claude  --model opus\t-w") == ["claude", "--model", "opus", "-w"])
        #expect(ShellWords.split("claude --append-system-prompt 'be brief'") == ["claude", "--append-system-prompt", "be brief"])
        #expect(ShellWords.split(#"claude --settings "{\"a\": 1}""#) == ["claude", "--settings", #"{"a": 1}"#])
        #expect(ShellWords.split(#"pi --name it\'s"#) == ["pi", "--name", "it's"])
        #expect(ShellWords.split("codex -c model=o3''") == ["codex", "-c", "model=o3"])
        #expect(ShellWords.split("pi --name ''") == ["pi", "--name", ""])
        #expect(ShellWords.split("") == [])
    }

    @Test func `a line that needs more of the shell isn't taken apart`() {
        for line in [
            "claude $FLAGS", "claude \"$FLAGS\"", "claude `flags`", "claude; echo", "claude && echo", "claude | tee",
            "claude > log", "claude --add-dir ~/x", "claude --add-dir *", "claude # note", "claude 'open", "claude \"open",
            "claude \\", "claude\necho",
        ] {
            #expect(ShellWords.split(line) == nil, "\(line)")
        }
        // Inside a word or quoted, they're only characters.
        #expect(ShellWords.split("claude --name a#b '$HOME' \"~/x\"") == ["claude", "--name", "a#b", "$HOME", "~/x"])
    }
}

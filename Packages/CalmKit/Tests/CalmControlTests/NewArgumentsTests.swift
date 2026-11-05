import CalmControl
import Testing

struct NewArgumentsTests {
    private func parse(_ words: String...) -> Result<NewArguments, NewArguments.Wrong> {
        NewArguments.parse(words, currentFolder: "/here")
    }

    private func reason(_ result: Result<NewArguments, NewArguments.Wrong>) -> String? {
        if case let .failure(wrong) = result {
            wrong.reason
        } else {
            nil
        }
    }

    @Test func `the words that are not options are the first message`() throws {
        let parsed = try parse("fix", "--background", "the", "--model", "opus", "bug").get()
        #expect(parsed.message == "fix the bug")
        #expect(parsed.model == "opus")
        #expect(parsed.background)
        #expect(parsed.command == nil)
        #expect(parsed.folder == "/here")
    }

    @Test func `a relative folder starts from the current one`() throws {
        #expect(try parse("hi", "--in", "sub").get().folder == "/here/sub")
        #expect(try parse("hi", "--in", "/there").get().folder == "/there")
        #expect(try parse("hi", "--in", "~/there").get().folder == "~/there")
    }

    @Test func `a command is kept as written, with its quotes`() throws {
        let command = "claude --system-prompt-file ./p.md --strict-mcp-config '开始写 第三章'"
        let parsed = try parse("--in", "/novels", "--background", "--command", command).get()
        #expect(parsed.command == command)
        #expect(parsed.message == nil)
        #expect(parsed.folder == "/novels")
        #expect(parsed.background)
    }

    @Test func `a message that starts with an agent's name stays a message`() throws {
        let parsed = try parse("claude 的更新日志看一下").get()
        #expect(parsed.message == "claude 的更新日志看一下")
        #expect(parsed.command == nil)
    }

    @Test func `a command takes no message and no model`() {
        #expect(reason(parse("--command", "claude", "hi"))?.contains("--command runs as written") == true)
        #expect(reason(parse("--command", "claude", "--model", "opus"))?.contains("--command runs as written") == true)
    }

    @Test func `a missing or blank command fails`() {
        #expect(reason(parse("--command"))?.hasPrefix("give a command") == true)
        #expect(reason(parse("--command", " \n"))?.hasPrefix("give a command") == true)
    }

    @Test func `no message fails, and so do an unknown option and a bad model`() {
        #expect(reason(parse("--background"))?.hasPrefix("give a first message") == true)
        #expect(reason(parse("hi", "--nope"))?.hasPrefix("unknown option '--nope'") == true)
        #expect(reason(parse("hi", "--model", "--opus")) != nil)
        #expect(reason(parse("hi", "--in")) != nil)
    }
}

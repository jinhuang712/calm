import CalmControl
import Testing

struct SearchRouteTests {
    private let hit = ControlResponse.SearchHit(
        title: "Fix the auth race", agent: "Claude Code", directory: "/dev/calm", lastActive: 0, snippet: "", transcript: "/t.jsonl",
    )

    @Test func `the results Calm finds are the results`() {
        let answer = Result<ControlResponse, any Error>.success(ControlResponse.success(results: [hit]))
        #expect(SearchRoute.from(answer) == .results([hit]))
    }

    @Test func `an answer without results is none found`() {
        let answer = Result<ControlResponse, any Error>.success(ControlResponse.success())
        #expect(SearchRoute.from(answer) == .results([]))
    }

    @Test func `a refusal from Calm is said, not searched around`() {
        let answer = Result<ControlResponse, any Error>.success(.failure("This Calm is older than the calm command; update Calm."))
        #expect(SearchRoute.from(answer) == .refused("This Calm is older than the calm command; update Calm."))
    }

    @Test func `with Calm not running, the index is how search works`() {
        let answer = Result<ControlResponse, any Error>.failure(ControlClient.ClientError.notRunning("/x/calm.sock"))
        #expect(SearchRoute.from(answer) == .index(notice: nil))
    }

    @Test func `a Calm that doesn't answer is said, then the index searched`() {
        let answer = Result<ControlResponse, any Error>.failure(ControlClient.ClientError.io("no response from Calm"))
        #expect(SearchRoute.from(answer) == .index(notice: "Calm didn't answer, so this searched the index directly."))
    }
}

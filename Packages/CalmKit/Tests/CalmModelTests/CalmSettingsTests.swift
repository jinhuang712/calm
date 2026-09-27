@testable import CalmModel
import Testing

struct CalmSettingsTests {
    @Test func `defaults apply when the file is empty`() {
        #expect(CalmSettings(text: "").autoGrouping == true)
    }

    @Test func `booleans, strings, comments and sections`() {
        let settings = CalmSettings(text: """
        # Calm settings
        auto-grouping = false   # keep sessions where I put them
        editor = "zed"

        [agents]
        notify = "needs-you"
        """)
        #expect(settings.autoGrouping == false)
        #expect(settings.string("editor") == "zed")
        #expect(settings.string("agents.notify") == "needs-you")
        #expect(settings.problems.isEmpty)
    }

    @Test func `a # inside quotes is not a comment`() {
        #expect(CalmSettings(text: #"title = "a # b""#).string("title") == "a # b")
    }

    @Test func `malformed lines are reported, not fatal`() {
        let settings = CalmSettings(text: "auto-grouping = off\nthis is wrong\n")
        #expect(settings.autoGrouping == false)
        #expect(settings.problems == ["line 2: expected key = value"])
    }

    @Test func `unknown values fall back to the default`() {
        #expect(CalmSettings(text: "auto-grouping = maybe").autoGrouping == true)
    }

    @Test func `motion level reads full, reduced or off`() {
        #expect(CalmSettings(text: "").motion == .full)
        #expect(CalmSettings(text: "motion = Reduced").motion == .reduced)
        #expect(CalmSettings(text: "motion = off").motion == .off)
        #expect(CalmSettings(text: "motion = wild").motion == .full)
    }
}

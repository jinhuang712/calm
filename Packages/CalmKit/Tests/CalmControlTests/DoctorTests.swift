import CalmControl
import Foundation
import Testing

struct DoctorTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let app = "/Applications/Calm.app"

    private func info(version: String = "0.1.0", session: ControlResponse.SessionReport? = nil) -> ControlResponse.AppInfo {
        ControlResponse.AppInfo(processID: 14094, bundlePath: app, version: version, session: session)
    }

    /// A Calm that is well: one copy, started after its install, this CLI its own and on PATH.
    private func healthy() -> Doctor.Facts {
        Doctor.Facts(
            answer: .answered(info()),
            started: now.addingTimeInterval(-600),
            copies: [14094],
            installedVersion: "0.1.0",
            installedAt: now.addingTimeInterval(-3600),
            cliVersion: "0.1.0",
            cliApp: app,
            pathCalm: "\(app)/Contents/Resources/bin/calm",
            now: now,
        )
    }

    private func problems(_ facts: Doctor.Facts) -> [Doctor.Check] {
        Doctor.checks(facts).filter { $0.verdict == .problem }
    }

    @Test func `a healthy Calm has no problems`() {
        let checks = Doctor.checks(healthy())
        #expect(checks.allSatisfy { $0.verdict == .ok })
        #expect(checks.first?.text.hasPrefix("Calm 0.1.0 answers on its socket (process 14094, running since") == true)
    }

    @Test func `no Calm running says so and checks nothing that needs it`() {
        var facts = healthy()
        facts.answer = .notRunning(socket: "/x/calm.sock")
        let found = problems(facts)
        #expect(found.map(\.text) == ["Calm isn't running (no socket at /x/calm.sock)."])
        #expect(found.first?.hint == "Open Calm.")
    }

    @Test func `a Calm that doesn't answer, and one too old to know info`() {
        var facts = healthy()
        facts.answer = .silent("no response from Calm")
        #expect(problems(facts).first?.text == "Calm doesn't answer on its socket (no response from Calm).")
        facts.answer = .refused("Couldn't read the request.")
        #expect(problems(facts).first?.text == "The Calm answering is older than this calm: Couldn't read the request.")
    }

    /// The incident of 2026-09-29: a second copy took the socket and every hook went to it.
    @Test func `two copies of Calm are a problem`() {
        var facts = healthy()
        facts.copies = [14094, 15210]
        #expect(problems(facts).map(\.text) == [
            "2 copies of Calm are running from /Applications/Calm.app (processes 14094, 15210).",
        ])
    }

    @Test func `an install after Calm started asks for a restart`() {
        var facts = healthy()
        facts.installedAt = now.addingTimeInterval(-60)
        let found = problems(facts)
        #expect(found.count == 1)
        #expect(found.first?.text.hasPrefix("A newer Calm was installed at") == true)
        #expect(found.first?.hint?.hasPrefix("Calm → Restart Calm") == true)
    }

    @Test func `another version on disk asks for a restart too`() {
        var facts = healthy()
        facts.installedVersion = "0.2.0"
        #expect(problems(facts).map(\.text) == ["Calm 0.1.0 is running; 0.2.0 is installed."])
    }

    @Test func `a calm from another app, or of another version, is a problem`() {
        var facts = healthy()
        facts.cliApp = "/Users/me/dev/calm/build/Calm Dev.app"
        #expect(problems(facts).first?.text
            == "This calm comes with /Users/me/dev/calm/build/Calm Dev.app, but the Calm answering runs from /Applications/Calm.app.")
        facts = healthy()
        facts.cliVersion = "0.2.0"
        #expect(problems(facts).map(\.text) == ["This calm is 0.2.0, the Calm answering is 0.1.0."])
    }

    @Test func `the calm on PATH: missing is a note, someone else's is a problem`() {
        var facts = healthy()
        facts.pathCalm = nil
        let missing = Doctor.checks(facts).first { $0.text.hasPrefix("No calm on PATH.") }
        #expect(missing?.verdict == .note)
        // A downloaded Calm has no install.sh, so the hint links this Calm's own calm.
        #expect(missing?.hint?.contains("ln -sf '/Applications/Calm.app/Contents/Resources/bin/calm' ~/.local/bin/calm") == true)
        #expect(problems(facts).isEmpty)
        facts.pathCalm = "/opt/old/Calm.app/Contents/Resources/bin/calm"
        #expect(problems(facts).first?.text
            == "The calm on PATH (/opt/old/Calm.app/Contents/Resources/bin/calm) isn't this Calm's (/Applications/Calm.app).")
    }

    /// Found running it for real: with nothing answering and a calm outside any app, "the calm on
    /// PATH is this Calm's" claimed what nothing could show.
    @Test func `with no Calm answering, nothing is claimed about whose calm it is`() {
        var facts = healthy()
        facts.answer = .refused("Couldn't read the request.")
        facts.cliApp = nil
        let checks = Doctor.checks(facts)
        #expect(checks.contains(Doctor.Check(.note, "The calm on PATH is /Applications/Calm.app/Contents/Resources/bin/calm.")))
        #expect(!checks.contains { $0.text.contains("this Calm's") || $0.text.contains("the Calm answering") })

        facts.cliApp = app
        #expect(Doctor.checks(facts).contains(Doctor.Check(.ok, "This calm (0.1.0) comes with /Applications/Calm.app.")))
    }

    @Test func `agents: what's broken is a problem, what's a choice is a note`() {
        var facts = healthy()
        facts.agents = [
            Doctor.Agent(name: "Claude Code", link: .plugin(written: true, on: true)),
            Doctor.Agent(name: "Codex", link: .notifications),
            Doctor.Agent(name: "pi", link: .files(.connected)),
            Doctor.Agent(name: "OpenCode", link: .files(.notConnected)),
        ]
        let checks = Doctor.checks(facts).suffix(4)
        #expect(checks.map(\.verdict) == [.ok, .note, .ok, .note])
        #expect(checks.last?.text == "OpenCode: not connected (Settings → Agents).")

        facts.agents = [
            Doctor.Agent(name: "Claude Code", link: .plugin(written: false, on: true)),
            Doctor.Agent(name: "OpenCode", link: .files(.conflict(".config/opencode/plugins/calm/tui.ts"))),
            Doctor.Agent(name: "pi", link: .files(.outdated)),
        ]
        #expect(problems(facts).map(\.text) == [
            "Claude Code: Calm's plugin isn't there (~/Library/Application Support/Calm/agents/claude-code).",
            "OpenCode: a file Calm didn't write is in the way (~/.config/opencode/plugins/calm/tui.ts).",
        ])
        facts.agents = [Doctor.Agent(name: "Claude Code", link: .plugin(written: true, on: false))]
        #expect(Doctor.checks(facts).last?.verdict == .note)
    }

    @Test func `this session: what Calm knows of it, and who last reported`() {
        var facts = healthy()
        facts.sessionID = "43E23209-0E03-4B1C-9C8F-C856FE7FAAAA"
        facts.answer = .answered(info(session: ControlResponse.SessionReport(
            state: "working", agent: "Claude Code", reportSource: "hook", reportedAt: now.timeIntervalSince1970 - 4,
        )))
        #expect(Doctor.checks(facts).last?.text == "This session (43e23209): working, Claude Code, last reported by a hook 4 s ago.")

        facts.answer = .answered(info(session: ControlResponse.SessionReport(state: "idle")))
        #expect(Doctor.checks(facts).last?.text == "This session (43e23209): idle, nothing reported yet.")

        facts.answer = .answered(info())
        #expect(problems(facts).map(\.text) == ["The Calm answering doesn't know this session (43e23209)."])
    }

    @Test func `a shell without Calm's Claude plugin is a problem`() {
        var facts = healthy()
        facts.sessionID = "43e23209"
        facts.answer = .answered(info(session: ControlResponse.SessionReport(state: "idle")))
        facts.claudePluginInShell = false
        #expect(problems(facts).map(\.text) == ["This shell doesn't load Calm's Claude Code plugin, so Claude here won't report."])
    }

    @Test func `text marks each check, with what to do under a problem, and json carries a version`() {
        let checks = [
            Doctor.Check(.ok, "Fine."),
            Doctor.Check(.problem, "Broken.", hint: "Fix it."),
            Doctor.Check(.note, "By the way."),
        ]
        #expect(Doctor.text(checks) == "✓ Fine.\n✗ Broken.\n    Fix it.\n· By the way.")
        let json = Doctor.json(checks)
        #expect(json.contains(#""v" : 1"#))
        #expect(json.contains(#""verdict" : "problem""#))
    }
}

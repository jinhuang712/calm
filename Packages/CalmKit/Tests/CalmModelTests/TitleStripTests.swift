@testable import CalmModel
import Foundation
import Testing

struct TitleStripTests {
    private let home = "/Users/ada"

    private func session(_ title: String, in folder: String) -> Session {
        Session(projectID: UUID(), title: title, workingDirectory: folder)
    }

    @Test func `the home folder is written as a tilde`() {
        #expect(WorkspacePath.abbreviated("/Users/ada", home: home) == "~")
        #expect(WorkspacePath.abbreviated("/Users/ada/dev/calm/", home: home) == "~/dev/calm")
        #expect(WorkspacePath.abbreviated("/Users/adam/dev", home: home) == "/Users/adam/dev")
        #expect(WorkspacePath.abbreviated("/opt/tools", home: home) == "/opt/tools")
    }

    @Test func `the folder comes first, then the title`() {
        let strip = session("zsh", in: "/Users/ada/dev/calm").titleStrip(agentTitle: "Fix the login loop", home: home)
        #expect(strip.folder == "~/dev/calm")
        #expect(strip.title == "Fix the login loop")
    }

    @Test func `a title that only repeats the folder is left out`() {
        for title in ["", "~/dev/calm", "calm", "/Users/ada/dev/calm", "…/dev/calm", ".../calm"] {
            let strip = session(title, in: "/Users/ada/dev/calm").titleStrip(agentTitle: nil, home: home)
            #expect(strip.folder == "~/dev/calm")
            #expect(strip.title == nil, "title \(title)")
        }
        #expect(session("~", in: "/Users/ada").titleStrip(agentTitle: nil, home: home).title == nil)
        #expect(session("…/other/calm", in: "/Users/ada/dev/calm").titleStrip(agentTitle: nil, home: home).title == "…/other/calm")
    }

    @Test func `a scratch session shows no folder`() {
        var scratch = session("zsh", in: "/Users/ada/Library/Calm/Scratch/1")
        scratch.scratchFolder = "/Users/ada/Library/Calm/Scratch/1"
        let strip = scratch.titleStrip(agentTitle: nil, home: home)
        #expect(strip.folder == nil)
        #expect(strip.title?.hasPrefix("Scratch · ") == true)
    }
}

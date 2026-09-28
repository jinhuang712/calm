@testable import CalmModel
import Foundation
import Testing

struct GhosttyConfigTextTests {
    @Test func `the first family after the last reset is the main font`() throws {
        let url = try #require(Bundle.module.url(forResource: "fonts", withExtension: "txt", subdirectory: "Fixtures/ghostty-config"))
        let text = try String(contentsOf: url, encoding: .utf8)
        #expect(GhosttyConfigText.fontFamily(in: text) == "JetBrains Mono")
    }

    @Test func `no font-family means Ghostty's default`() {
        #expect(GhosttyConfigText.fontFamily(in: "theme = Rose Pine\nfont-size = 13\n") == nil)
        #expect(GhosttyConfigText.fontFamily(in: "") == nil)
    }

    @Test func `a reset with nothing after it leaves the default`() {
        #expect(GhosttyConfigText.fontFamily(in: "font-family = Menlo\nfont-family =\n") == nil)
    }

    @Test func `style keys and comments don't count`() {
        let text = "font-family-italic = Iosevka\n# font-family = Fira Code\nfont-family=SF Mono\n"
        #expect(GhosttyConfigText.fontFamily(in: text) == "SF Mono")
    }
}

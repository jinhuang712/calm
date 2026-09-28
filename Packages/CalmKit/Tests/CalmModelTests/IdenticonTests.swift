@testable import CalmModel
import Testing

struct IdenticonTests {
    private func rows(_ name: String) -> [String] {
        Identicon(name: name).cells.map { String($0.map { $0 ? "#" : "." }) }
    }

    @Test func `the same name always gets the same mark`() {
        // Pinned, so a change to the hash (which would redraw every project) is deliberate.
        #expect(rows("calm") == [".###.", "#.#.#", "#...#", ".###.", "....."])
        #expect(Identicon(name: "Calm") == Identicon(name: "calm"))
    }

    @Test func `marks mirror left to right`() {
        for name in ["calm", "ghostty", "dotfiles", "api-gateway", "zmx", "笔记"] {
            for row in Identicon(name: name).cells {
                #expect(row == row.reversed())
            }
        }
    }

    @Test func `marks are never nearly empty or nearly full`() {
        for index in 0 ..< 500 {
            let filled = Identicon(name: "project-\(index)").cells.map { $0.prefix(3).count(where: \.self) }.reduce(0, +)
            #expect((5 ... 11).contains(filled))
        }
    }

    @Test func `similar names look apart`() {
        #expect(Identicon(name: "calm") != Identicon(name: "calm-docs"))
        #expect(Identicon(name: "api") != Identicon(name: "apj"))
    }
}

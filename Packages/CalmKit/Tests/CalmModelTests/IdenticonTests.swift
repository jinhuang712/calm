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

    @Test func `hues come from the soft set and spread out`() {
        let hues = (0 ..< 200).map { Identicon(name: "project-\($0)").hue }
        #expect(hues.allSatisfy { hue in Identicon.hues.contains { abs($0 / 360 - hue) < 1e-9 } })
        // Every hue gets used, none by more than a third of the names.
        let counts = Dictionary(grouping: hues, by: \.self).mapValues(\.count)
        #expect(counts.count == Identicon.hues.count)
        #expect(counts.values.allSatisfy { $0 < 70 })
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

    @Test func `a seed gives the same name another mark, the same one each time`() {
        let seeded = Identicon(name: "calm", seed: 42)
        #expect(seeded == Identicon(name: "calm", seed: 42))
        #expect(seeded != Identicon(name: "calm"))
        // Different seeds mostly differ (a few may land on the same mark by chance).
        let marks = Set((0 ..< 50).map { Identicon(name: "calm", seed: $0).cells })
        #expect(marks.count > 40)
    }
}

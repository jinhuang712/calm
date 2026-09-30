import CalmAgents
import CalmModel
@testable import CalmSearch
import Foundation
import Testing

struct SearchLayoutTests {
    // MARK: Matching

    @Test func `short letters and digits match where words start`() {
        #expect(SearchMatch.startsWords("d"))
        #expect(SearchMatch.startsWords("4k"))
        #expect(!SearchMatch.startsWords("dra"))
        #expect(!SearchMatch.startsWords("终端")) // no spaces between words: anywhere
        #expect(!SearchMatch.startsWords("_x"))
        #expect(SearchMatch.contains("Draft notes", "d"))
        #expect(!SearchMatch.contains("hardware", "d"))
        #expect(SearchMatch.contains("the (default) one", "d"))
        #expect(SearchMatch.contains("snake_case", "ca"))
        #expect(SearchMatch.contains("hardware", "dwa"))
        #expect(SearchMatch.contains("把终端的主题", "终端"))
        #expect(SearchMatch.contains("Café au lait", "cafe"))
    }

    @Test func `marks are every match of every word, merged`() {
        let text = "hello hell help"
        let marked = SearchMatch.ranges(of: ["hel", "hello"], in: text).map { String(text[$0]) }
        #expect(marked == ["hello", "hel", "hel"])
        #expect(SearchMatch.ranges(of: ["d"], in: "add a draft").map { String("add a draft"[$0]) } == ["d"])
    }

    // MARK: Lines

    private func line(_ id: Int64, _ terms: [String]) -> SearchResult.Line {
        SearchResult.Line(id: id, role: .user, text: "line \(id)", terms: terms)
    }

    private func result(lines: [SearchResult.Line]) -> SearchResult {
        var result = SearchResult(
            transcriptPath: "/t", agent: .claudeCode, directory: "/d", title: "Title", lastActive: Date(), snippet: "", score: 0,
        )
        result.lines = lines
        return result
    }

    @Test func `the fewest lines that show every word`() {
        let both = result(lines: [line(1, ["hello"]), line(2, ["fail"]), line(3, ["hello", "fail"])])
        #expect(both.linesToShow(terms: ["hello", "fail"], shown: []).map(\.id) == [3])
        let apart = result(lines: [line(5, ["fail"]), line(2, ["hello"])])
        // Two words in two messages: both, in the order they were said.
        #expect(apart.linesToShow(terms: ["hello", "fail"], shown: []).map(\.id) == [2, 5])
        // A word the title shows needs no line; with every word shown, one line for context.
        #expect(apart.linesToShow(terms: ["hello", "fail"], shown: ["hello"]).map(\.id) == [5])
        #expect(apart.linesToShow(terms: ["hello"], shown: ["hello"]).map(\.id) == [2])
        #expect(result(lines: []).linesToShow(terms: ["x"], shown: []).isEmpty)
        let many = result(lines: (1 ... 5).map { line(Int64($0), ["w\($0)"]) })
        #expect(many.linesToShow(terms: (1 ... 5).map { "w\($0)" }, shown: []).count == 3)
    }

    /// One point per character.
    private let characters: (String) -> Double = { Double($0.count) }

    private func shown(_ parts: [SearchLineFit.Part]) -> String {
        parts.map { part in
            switch part {
            case let .text(text): text
            case .gap: "…"
            }
        }.joined(separator: "|")
    }

    @Test func `a line is built around its words`() {
        let text = "the service has three endpoints: health, metrics and greet, and the greet handler only then says hello in your language"
        let parts = SearchLineFit.parts(text, terms: ["endpoints", "hello"], width: 60, measure: characters)
        let built = shown(parts)
        #expect(built.contains("endpoints"))
        #expect(built.contains("hello"))
        #expect(parts.first == .gap) // opens mid-message
        #expect(parts.contains(.gap) && parts.count >= 4) // the stretch between them is left out
        // With room, the whole thing, as it is.
        #expect(SearchLineFit.parts(text, terms: ["the"], width: 500, measure: characters) == [.text(text)])
        // A message that went on before the excerpt opens with a gap even at its first word.
        #expect(SearchLineFit.parts("hello there", terms: ["hello"], cutBefore: true, width: 50, measure: characters).first == .gap)
    }

    @Test func `context goes before a word does`() {
        let text = "one two three four five six seven target eight nine ten"
        let tight = shown(SearchLineFit.parts(text, terms: ["target"], width: 8, measure: characters))
        #expect(tight.hasPrefix("…|target"))
        let roomy = shown(SearchLineFit.parts(text, terms: ["target"], width: 40, measure: characters))
        #expect(roomy.hasPrefix("…|five six seven target"))
        // A word no line could hold is cut into, just before the match.
        let long = String(repeating: "x", count: 80) + "needle" + String(repeating: "y", count: 40)
        let cut = shown(SearchLineFit.parts(long, terms: ["needle"], width: 20, measure: characters))
        #expect(cut.hasPrefix("…|xxxxxxxxxxxxneedle"))
    }

    // MARK: Groups

    @Test func `groups: yours first, a few each, the rest behind more`() {
        let keys = ["a", "calm", "calm", "b", "calm", "calm", "calm", "calm", "a", "a", "a"]
        let groups = SearchGroups.grouped(keys, current: "calm", capped: true)
        #expect(groups.map(\.key) == ["calm", "a", "b"])
        #expect(groups.map(\.shown) == [3, 2, 1])
        #expect(groups.map(\.more) == [3, 2, 0])
        #expect(groups[0].members == [1, 2, 4, 5, 6, 7])
        #expect(!groups[0].folds)
        // Uncapped (one group, or the empty field): everything.
        #expect(SearchGroups.grouped(keys, current: "calm", capped: false).map(\.more) == [0, 0, 0])
    }

    @Test func `more opens five at a time and never leaves one`() {
        let keys = Array(repeating: "calm", count: 14) + ["x", "x"]
        var groups = SearchGroups.grouped(keys, current: "calm", capped: true)
        #expect((groups[0].shown, groups[0].more) == (3, 11))
        groups = SearchGroups.grouped(keys, current: "calm", capped: true, extra: ["calm": 5])
        #expect((groups[0].shown, groups[0].more, groups[0].folds) == (8, 6, true))
        // 13 of 14 would leave "1 more": all 14 show.
        groups = SearchGroups.grouped(keys, current: "calm", capped: true, extra: ["calm": 10])
        #expect((groups[0].shown, groups[0].more, groups[0].folds) == (14, 0, true))
        // A group just one over its share shows it: nothing to fold.
        #expect(SearchGroups.grouped(["x", "x", "x", "y"], current: nil, capped: true).map(\.shown) == [3, 1])
    }

    @Test func `the empty field is a switcher of what you could pick back up`() {
        let keys = ["calm", "calm", "x", "calm", "x", "x", "calm", "calm", "calm", "y"]
        let open = [true, false, false, false, false, false, false, false, false, false]
        let groups = SearchGroups.switcher(keys, open: open, current: "calm")
        #expect(groups.map(\.key) == ["calm", "x", "y"])
        #expect(groups[0].members == [1, 3, 6, 7]) // four of yours, the open one left out
        #expect(groups[1].members == [2, 4]) // two of another
        #expect(groups.allSatisfy { $0.more == 0 })
        #expect(SearchGroups.switcher(Array(repeating: "a", count: 30), open: Array(repeating: false, count: 30), current: "a", yours: 20)
            .first?.members.count == 11)
    }

    @Test func `headers count open, idle and past`() {
        let counts = SearchGroupCounts([.working, .done, .idle, nil, nil, .working])
        #expect((counts.open, counts.idle, counts.past) == (3, 1, 2))
        #expect(counts.words == "3 open (1 done, 2 working), 1 idle, 2 past")
        #expect(SearchGroupCounts([.working, .working]).words == "2 open")
        #expect(SearchGroupCounts([.needsYou]).words == "1 open (1 needs you)")
        #expect(SearchGroupCounts([nil]).words == "1 past")
    }
}

@testable import CalmModel
import Testing

struct ChangeSummaryTests {
    @Test func `a clean project has nothing to report`() {
        #expect(ChangeSummary(changes: [:], lines: [:]) == nil)
        // Lines for files that aren't changes don't make a summary.
        #expect(ChangeSummary(changes: [:], lines: ["a.swift": LineCounts(added: 3, deleted: 1)]) == nil)
    }

    @Test func `counts the changed files and adds up their lines`() throws {
        let summary = try #require(ChangeSummary(
            changes: ["a.swift": .modified, "b.md": .added, "c.txt": .untracked],
            lines: [
                "a.swift": LineCounts(added: 38, deleted: 4),
                "b.md": LineCounts(added: 14, deleted: 0),
                "c.txt": LineCounts(added: 6, deleted: 2),
            ],
        ))
        #expect(summary.count == 3)
        #expect(summary.lines == LineCounts(added: 58, deleted: 6))
        #expect(summary.headline == "3 changed")
    }

    @Test func `a file git couldn't count still counts as changed`() throws {
        let summary = try #require(ChangeSummary(
            changes: ["a.swift": .modified, "logo.png": .modified],
            lines: ["a.swift": LineCounts(added: 2, deleted: 1)],
        ))
        #expect(summary.count == 2)
        #expect(summary.lines == LineCounts(added: 2, deleted: 1))
    }

    @Test func `no lines at all when git counted none`() throws {
        let summary = try #require(ChangeSummary(changes: ["logo.png": .modified], lines: [:]))
        #expect(summary.count == 1)
        #expect(summary.lines == nil)
    }

    @Test func `lines of files that aren't in the changes are left out`() throws {
        let summary = try #require(ChangeSummary(
            changes: ["a.swift": .modified],
            lines: ["a.swift": LineCounts(added: 1, deleted: 1), "stale.swift": LineCounts(added: 99, deleted: 99)],
        ))
        #expect(summary.lines == LineCounts(added: 1, deleted: 1))
    }

    @Test func `said in words for VoiceOver`() throws {
        let one = try #require(ChangeSummary(changes: ["a": .modified], lines: ["a": LineCounts(added: 1, deleted: 0)]))
        #expect(one.spoken == "1 file changed, 1 line added, 0 removed")
        let two = try #require(ChangeSummary(
            changes: ["a": .modified, "b": .added],
            lines: ["a": LineCounts(added: 58, deleted: 6)],
        ))
        #expect(two.spoken == "2 files changed, 58 lines added, 6 removed")
        let uncounted = try #require(ChangeSummary(changes: ["a": .modified, "b": .added], lines: [:]))
        #expect(uncounted.spoken == "2 files changed")
    }

    @Test func `the total of nothing is nothing`() {
        #expect(LineCounts.total([]) == nil)
        #expect(LineCounts.total([LineCounts(added: 1, deleted: 2), LineCounts(added: 3, deleted: 4)]) == LineCounts(added: 4, deleted: 6))
    }
}

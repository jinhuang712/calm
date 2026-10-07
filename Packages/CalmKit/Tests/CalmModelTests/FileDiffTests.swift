@testable import CalmModel
import Foundation
import Testing

struct FileDiffTests {
    /// Real `git diff -U3 HEAD` output: a line added, one removed, and two edited.
    private func fixture() throws -> FileDiff {
        let url = try #require(Bundle.module.url(forResource: "agent-images", withExtension: "diff", subdirectory: "Fixtures/diffs"))
        return try #require(FileDiff.parse(String(contentsOf: url, encoding: .utf8)))
    }

    @Test func `reads the hunk and numbers every line on both sides`() throws {
        let diff = try fixture()
        let hunk = try #require(diff.hunks.first)
        #expect(diff.hunks.count == 1)
        #expect((hunk.oldStart, hunk.oldCount, hunk.newStart, hunk.newCount) == (6, 16, 6, 16))
        #expect(hunk.header == "@@ −6,16 +6,16 @@")
        #expect(hunk.lines.count == 19)
        #expect(hunk.lines[3] == FileDiff.Line(kind: .added, text: #"trap 'rm -rf "$folder"' EXIT"#, old: nil, new: 9))
        #expect(hunk.lines[8] == FileDiff.Line(kind: .removed, text: "# A 1 × 1 PNG.", old: 13, new: nil))
        #expect(hunk.lines.last == FileDiff.Line(
            kind: .context,
            text: #"exec "$(dirname "$0")/agent-standin.sh" claude 60"#,
            old: 21,
            new: 21,
        ))
        #expect(diff.added == 3)
        #expect(diff.removed == 3)
    }

    @Test func `marks added and modified lines, and where lines were only removed`() throws {
        let diff = try fixture()
        #expect(diff.marks == [9: .added, 16: .modified, 19: .modified])
        // "# A 1 × 1 PNG." went from between mkdir (13) and base64, now line 14.
        #expect(diff.deletions == [14])
    }

    @Test func `pairs the split diff's sides, one-sided where a line was only added or removed`() throws {
        let diff = try fixture()
        let pairs = try FileDiff.pairs(of: #require(diff.hunks.first))
        #expect(pairs.count == 17)
        #expect(pairs[3].left == nil)
        #expect(pairs[3].right?.new == 9)
        #expect(pairs[8].left?.old == 13)
        #expect(pairs[8].right == nil)
        let sleep = pairs[11]
        #expect(sleep.left?.text == "  sleep 2.5")
        #expect(sleep.right?.text == "  sleep 3")
        #expect(sleep.emphasis == FileDiff.Emphasis(old: 8 ..< 11, new: 8 ..< 9))
    }

    @Test func `the unified diff singles out the same words, in the page's UTF-16 offsets`() throws {
        let diff = try fixture()
        let hunk = try #require(diff.hunks.first)
        let emphases = FileDiff.emphases(in: hunk)
        #expect(emphases[11] == 8 ..< 11)
        #expect(emphases[12] == 8 ..< 9)
        // Past "❯", the edit is the words added before the closing "\n'".
        let shared = "  printf '❯ [Image #1] which one? and [Image #9] has no file"
        let added = " — hover each"
        #expect(emphases[15] == shared.utf16.count ..< shared.utf16.count)
        #expect(emphases[16] == shared.utf16.count ..< shared.utf16.count + added.utf16.count)
        // Lines only added or removed have nothing to compare with.
        #expect(emphases[3] == nil)
        #expect(emphases[8] == nil)
    }

    @Test func `a rewritten line is the change, with no words singled out`() {
        #expect(FileDiff.emphasis(old: "let width = 340", new: "return nil") == nil)
        #expect(FileDiff.emphasis(old: "same", new: "same") == nil)
        #expect(FileDiff.emphasis(old: "count = 1", new: "count = 12") == FileDiff.Emphasis(old: 9 ..< 9, new: 9 ..< 10))
    }

    @Test func `reads a count left out, and skips git's notes`() throws {
        let text = """
        diff --git a/x b/x
        --- a/x
        +++ b/x
        @@ -1 +1,2 @@ func top()
        -old
        \\ No newline at end of file
        +new
        +more
        \\ No newline at end of file
        """
        let diff = try #require(FileDiff.parse(text))
        let hunk = try #require(diff.hunks.first)
        #expect((hunk.oldStart, hunk.oldCount, hunk.newStart, hunk.newCount) == (1, 1, 1, 2))
        #expect(hunk.section == "func top()")
        #expect(hunk.lines.map(\.kind) == [.removed, .added, .added])
        #expect(diff.marks == [1: .modified, 2: .added])
        #expect(diff.deletions.isEmpty)
    }

    @Test func `lines removed at the end are marked after the last line`() throws {
        let text = """
        @@ -3,3 +3,1 @@
         keep
        -gone
        -also gone
        """
        let diff = try #require(FileDiff.parse(text))
        #expect(diff.deletions == [4])
        #expect(diff.marks.isEmpty)
    }

    @Test func `no hunks is no diff`() {
        #expect(FileDiff.parse("") == nil)
        #expect(FileDiff.parse("diff --git a/i.png b/i.png\nBinary files a/i.png and b/i.png differ\n") == nil)
    }
}

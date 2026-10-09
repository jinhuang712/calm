@testable import CalmModel
import Foundation
import Testing

struct ReleaseVersionTests {
    @Test func `a version reads with or without the tag's v`() {
        #expect(ReleaseVersion("0.1.0")?.description == "0.1.0")
        #expect(ReleaseVersion("v0.1.0") == ReleaseVersion("0.1.0"))
        #expect(ReleaseVersion(" v12.0.31\n")?.description == "12.0.31")
    }

    @Test func `anything that isn't three numbers is not a version`() {
        for text in ["", "v", "1", "1.2", "1.2.3.4", "1.2.x", "1..3", "1.2.3-beta", "v1.2.3-rc1", "1.-2.3", "1.+2.3", "latest", "١.٢.٣"] {
            #expect(ReleaseVersion(text) == nil, "\(text) was read as a version")
        }
    }

    @Test func `versions compare by number, not by text`() throws {
        let versions = try ["0.9.0", "0.10.0", "0.10.1", "1.0.0", "0.2.0"].map { try #require(ReleaseVersion($0)) }
        #expect(versions.sorted().map(\.description) == ["0.2.0", "0.9.0", "0.10.0", "0.10.1", "1.0.0"])
        let (nine, ten) = try (#require(ReleaseVersion("0.9.0")), #require(ReleaseVersion("0.10.0")))
        #expect(ten > nine)
    }
}

struct ReleaseFeedTests {
    private func fixture(_ name: String) throws -> Data {
        let url = try #require(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures/releases"))
        return try Data(contentsOf: url)
    }

    @Test func `the real list from GitHub gives Calm's one release, though it is flagged a pre-release`() throws {
        let release = try #require(try ReleaseFeed.newest(in: fixture("calm-releases")))
        #expect(release.version.description == "0.1.0")
        #expect(release.page == "https://github.com/jinhuang712/calm/releases/tag/v0.1.0")
    }

    /// A list shaped as GitHub's, with the fields the notice reads.
    private func list(_ entries: [(tag: String, draft: Bool)]) -> Data {
        let items = entries.map { #"{"tag_name": "\#($0.tag)", "html_url": "https://example.test/\#($0.tag)", "draft": \#($0.draft)}"# }
        return Data("[\(items.joined(separator: ","))]".utf8)
    }

    @Test func `the highest version wins, wherever GitHub puts it`() throws {
        let data = list([("v0.2.0", false), ("v0.10.0", false), ("v0.9.5", false)])
        #expect(try ReleaseFeed.newest(in: data)?.version.description == "0.10.0")
    }

    @Test func `a draft, a tag that isn't a version and a pre-release suffix are skipped`() throws {
        let data = list([("v0.5.0", true), ("nightly", false), ("v0.4.0-beta", false), ("v0.3.0", false)])
        #expect(try ReleaseFeed.newest(in: data)?.version.description == "0.3.0")
        #expect(try ReleaseFeed.newest(in: list([("v0.5.0", true)])) == nil)
        #expect(try ReleaseFeed.newest(in: Data("[]".utf8)) == nil)
    }

    @Test func `an entry with missing fields doesn't spoil the others`() throws {
        let data = Data(#"[{"id": 1}, {"tag_name": "v0.2.0"}, {"tag_name": null, "draft": null}]"#.utf8)
        let release = try #require(try ReleaseFeed.newest(in: data))
        #expect(release.version.description == "0.2.0")
        #expect(release.page == "")
    }

    @Test func `an answer that isn't a list is an error`() {
        // GitHub's rate limit and its 404 are objects with a message.
        let limited = Data(#"{"message": "Not Found", "status": "404"}"#.utf8)
        #expect(throws: ReleaseFeed.NotAReleaseList.self) { try ReleaseFeed.newest(in: limited) }
        #expect(throws: ReleaseFeed.NotAReleaseList.self) { try ReleaseFeed.newest(in: Data("<html>".utf8)) }
    }
}

struct UpdateOfferTests {
    private func release(_ version: String) throws -> CalmRelease {
        try CalmRelease(version: #require(ReleaseVersion(version)), page: "https://example.test/\(version)")
    }

    private func version(_ text: String) -> ReleaseVersion? {
        ReleaseVersion(text)
    }

    @Test func `a newer release is offered, the same or an older one isn't`() throws {
        let running = try #require(version("0.1.0"))
        #expect(try UpdateOffer.release(newest: release("0.2.0"), running: running, skipped: nil) == release("0.2.0"))
        #expect(try UpdateOffer.release(newest: release("0.1.0"), running: running, skipped: nil) == nil)
        #expect(try UpdateOffer.release(newest: release("0.0.9"), running: running, skipped: nil) == nil)
        #expect(UpdateOffer.release(newest: nil, running: running, skipped: nil) == nil)
    }

    @Test func `a skipped release isn't offered, but a newer one is`() throws {
        let running = try #require(version("0.1.0"))
        let skipped = version("0.2.0")
        #expect(try UpdateOffer.release(newest: release("0.2.0"), running: running, skipped: skipped) == nil)
        #expect(try UpdateOffer.release(newest: release("0.3.0"), running: running, skipped: skipped) == release("0.3.0"))
    }
}

struct UpdateCommandTests {
    @Test func `a Homebrew install is updated by Homebrew, any other by the one-line install`() {
        #expect(CalmUpdates.updateCommand(installedByHomebrew: true) == "brew upgrade --cask calm")
        #expect(CalmUpdates.updateCommand(installedByHomebrew: false) == CalmUpdates.installCommand)
        // get.sh refuses to replace a Calm Homebrew installed, so that command must never be the one offered.
        #expect(CalmUpdates.installCommand.hasSuffix("get.sh | bash"))
    }
}

struct UpdateScheduleTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func ago(_ seconds: TimeInterval) -> Date {
        now.addingTimeInterval(-seconds)
    }

    @Test func `a first launch checks`() {
        #expect(UpdateSchedule.isDue(lastChecked: nil, lastAttempt: nil, now: now))
    }

    @Test func `a check is due after a day, not before`() {
        let almost = ago(UpdateSchedule.interval - 60)
        #expect(!UpdateSchedule.isDue(lastChecked: almost, lastAttempt: almost, now: now))
        let full = ago(UpdateSchedule.interval)
        #expect(UpdateSchedule.isDue(lastChecked: full, lastAttempt: full, now: now))
    }

    @Test func `after a failure it waits an hour, not a day`() {
        let lastChecked = ago(3 * UpdateSchedule.interval)
        #expect(!UpdateSchedule.isDue(lastChecked: lastChecked, lastAttempt: ago(60), now: now))
        #expect(UpdateSchedule.isDue(lastChecked: lastChecked, lastAttempt: ago(UpdateSchedule.retryAfter), now: now))
        // Never succeeded, and just failed.
        #expect(!UpdateSchedule.isDue(lastChecked: nil, lastAttempt: ago(60), now: now))
    }

    @Test func `a clock that was wrong doesn't hold checks back`() {
        let future = now.addingTimeInterval(10 * UpdateSchedule.interval)
        #expect(UpdateSchedule.isDue(lastChecked: future, lastAttempt: nil, now: now))
        #expect(UpdateSchedule.isDue(lastChecked: future, lastAttempt: future, now: now))
    }
}

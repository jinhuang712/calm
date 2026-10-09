@testable import Calm
import CalmModel
import Foundation
import Testing

/// The update check (FEATURES.md → Updates), against a fake GitHub and a defaults suite of its
/// own: no test reaches the network or the user's saved answer.
@MainActor
struct UpdateCheckerTests {
    /// What the fake GitHub is asked, and what it answers next.
    final class Feed: @unchecked Sendable {
        struct Answer {
            let status: Int
            let headers: [String: String]
            let body: String
        }

        private let lock = NSLock()
        private var asked: [URLRequest] = []
        private var answers: [Answer] = []

        var requests: [URLRequest] {
            lock.withLock { asked }
        }

        func answer(_ status: Int = 200, etag: String? = nil, versions: [String] = [], body: String? = nil) {
            let list = "[" + versions.map { #"{"tag_name": "v\#($0)", "html_url": "https://example.test/v\#($0)", "draft": false}"# }
                .joined(separator: ",") + "]"
            lock.withLock {
                answers.append(Answer(status: status, headers: etag.map { ["ETag": $0] } ?? [:], body: body ?? list))
            }
        }

        func next(_ request: URLRequest) throws -> (Data, URLResponse) {
            let answer = lock.withLock {
                asked.append(request)
                return answers.isEmpty ? Answer(status: 200, headers: [:], body: "[]") : answers.removeFirst()
            }
            let url = try #require(request.url)
            let response = try #require(HTTPURLResponse(
                url: url, statusCode: answer.status, httpVersion: "HTTP/1.1", headerFields: answer.headers,
            ))
            return (Data(answer.body.utf8), response)
        }
    }

    private struct Rig {
        let checker: UpdateChecker
        let feed: Feed
        let defaults: UserDefaults
        let clock: Clock
    }

    final class Clock: @unchecked Sendable {
        var now = Date(timeIntervalSince1970: 1_800_000_000)
    }

    private func version(_ text: String) throws -> ReleaseVersion {
        try #require(ReleaseVersion(text))
    }

    private func release(_ text: String) throws -> CalmRelease {
        try CalmRelease(version: version(text), page: "https://example.test/v\(text)")
    }

    private func makeRig(running: String = "0.1.0", settingIsOn: Bool = true, defaults existing: UserDefaults? = nil) throws -> Rig {
        let defaults = try existing ?? #require(UserDefaults(suiteName: "calm-update-tests-\(UUID().uuidString)"))
        let feed = Feed()
        let clock = Clock()
        let checker = UpdateChecker(
            defaults: defaults,
            running: ReleaseVersion(running),
            feed: URL(string: "https://example.test/releases"),
            fetch: { try feed.next($0) },
            now: { clock.now },
            settingIsOn: { settingIsOn },
        )
        return Rig(checker: checker, feed: feed, defaults: defaults, clock: clock)
    }

    @Test func `a newer release is offered, and the request is GitHub's, with Calm's version only`() async throws {
        let rig = try makeRig()
        rig.feed.answer(versions: ["0.1.0", "0.2.0"])
        let outcome = await rig.checker.check(byHand: false)
        #expect(try outcome == .offer(release("0.2.0")))
        #expect(rig.checker.offer?.version.description == "0.2.0")

        let request = try #require(rig.feed.requests.first)
        #expect(request.value(forHTTPHeaderField: "Accept") == "application/vnd.github+json")
        #expect(request.value(forHTTPHeaderField: "User-Agent") == "Calm/0.1.0 (update check)")
        #expect(request.value(forHTTPHeaderField: "If-None-Match") == nil)
        #expect(request.httpMethod == "GET")
    }

    @Test func `the newest release being the one running is up to date`() async throws {
        let rig = try makeRig(running: "0.2.0")
        rig.feed.answer(versions: ["0.1.0", "0.2.0"])
        let outcome = await rig.checker.check(byHand: true)
        #expect(try outcome == .upToDate(version("0.2.0")))
        #expect(rig.checker.offer == nil)
    }

    @Test func `an unchanged list is answered 304 and the saved release still holds`() async throws {
        let rig = try makeRig()
        rig.feed.answer(etag: "\"abc\"", versions: ["0.2.0"])
        _ = await rig.checker.check(byHand: false)
        rig.feed.answer(304)
        let outcome = await rig.checker.check(byHand: false)
        #expect(rig.feed.requests.last?.value(forHTTPHeaderField: "If-None-Match") == "\"abc\"")
        #expect(try outcome == .offer(release("0.2.0")))
    }

    @Test func `the answer is kept for the next launch, and updating takes the notice away`() async throws {
        let first = try makeRig()
        first.feed.answer(versions: ["0.2.0"])
        _ = await first.checker.check(byHand: false)

        // A later launch of the same version shows the notice before any request.
        let again = try makeRig(defaults: first.defaults)
        #expect(again.checker.offer?.version.description == "0.2.0")
        #expect(again.feed.requests.isEmpty)

        // After updating, the same saved answer is no longer newer than what runs.
        let updated = try makeRig(running: "0.2.0", defaults: first.defaults)
        #expect(updated.checker.offer == nil)
    }

    @Test func `skipping hides a release until a newer one, and a check by hand offers it again`() async throws {
        let rig = try makeRig()
        rig.feed.answer(versions: ["0.2.0"])
        _ = await rig.checker.check(byHand: false)
        try rig.checker.skip(#require(rig.checker.offer))
        #expect(rig.checker.offer == nil)

        rig.feed.answer(versions: ["0.2.0", "0.3.0"])
        let newer = await rig.checker.check(byHand: false)
        #expect(newer.isOffer(of: "0.3.0"))

        try rig.checker.skip(#require(rig.checker.offer))
        rig.feed.answer(versions: ["0.3.0"])
        let skipped = await rig.checker.check(byHand: false)
        #expect(try skipped == .upToDate(version("0.1.0")))
        rig.feed.answer(versions: ["0.3.0"])
        let byHand = await rig.checker.check(byHand: true)
        #expect(byHand.isOffer(of: "0.3.0"))
    }

    @Test func `a failure says why, keeps what was known, and counts as an attempt only`() async throws {
        let rig = try makeRig()
        rig.feed.answer(versions: ["0.2.0"])
        _ = await rig.checker.check(byHand: false)

        rig.feed.answer(403, body: #"{"message": "API rate limit exceeded"}"#)
        let limited = await rig.checker.check(byHand: false)
        #expect(limited == .failed("GitHub is limiting requests from this address (403). Try again later."))
        rig.feed.answer(500, body: "")
        let broken = await rig.checker.check(byHand: false)
        #expect(broken == .failed("GitHub answered 500."))
        rig.feed.answer(200, body: "<html>")
        let html = await rig.checker.check(byHand: false)
        #expect(html == .failed("GitHub's answer isn't a list of releases"))
        // What the last good answer said still shows.
        #expect(rig.checker.offer?.version.description == "0.2.0")
    }

    @Test func `a check is due once a day, an hour after a failure, and never with the setting off`() async throws {
        let rig = try makeRig()
        #expect(rig.checker.isDue)
        rig.feed.answer(versions: ["0.1.0"])
        _ = await rig.checker.check(byHand: false)
        #expect(!rig.checker.isDue)

        rig.clock.now.addTimeInterval(UpdateSchedule.interval)
        #expect(rig.checker.isDue)
        rig.feed.answer(500, body: "")
        _ = await rig.checker.check(byHand: false)
        #expect(!rig.checker.isDue)
        rig.clock.now.addTimeInterval(UpdateSchedule.retryAfter)
        #expect(rig.checker.isDue)

        let off = try makeRig(settingIsOn: false)
        #expect(!off.checker.isDue)
    }

    @Test func `coming forward as Calm launches doesn't check, settling does, and later looks follow the schedule`() async throws {
        let rig = try makeRig()
        rig.feed.answer(versions: ["0.1.0"])

        // Calm becomes active while it launches: not a look, so nothing is asked yet.
        #expect(rig.checker.cameForward() == nil)
        #expect(rig.feed.requests.isEmpty)

        // The first seconds are over: the launch's check runs.
        await rig.checker.settle()?.value
        #expect(rig.feed.requests.count == 1)

        // Coming forward soon after changes nothing, a day later it checks again.
        #expect(rig.checker.cameForward() == nil)
        rig.clock.now.addTimeInterval(UpdateSchedule.interval)
        rig.feed.answer(versions: ["0.1.0"])
        await rig.checker.cameForward()?.value
        #expect(rig.feed.requests.count == 2)
    }

    @Test func `the cask's record in Homebrew's Caskroom, in either of its two places, means Homebrew installed it`() {
        #expect(UpdateChecker.installedByHomebrew(exists: { $0 == "/opt/homebrew/Caskroom/calm" }))
        #expect(UpdateChecker.installedByHomebrew(exists: { $0 == "/usr/local/Caskroom/calm" }))
        #expect(!UpdateChecker.installedByHomebrew(exists: { _ in false }))
        // Another cask's folder isn't this one's.
        #expect(!UpdateChecker.installedByHomebrew(exists: { $0 == "/opt/homebrew/Caskroom/calmly" }))
    }

    @Test func `a feed that is a file runs the real path with no network`() async throws {
        let file = FileManager.default.temporaryDirectory.appending(path: "calm-feed-\(UUID().uuidString).json")
        try Data(#"[{"tag_name": "v0.9.0", "html_url": "https://example.test/v0.9.0", "draft": false}]"#.utf8).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        let defaults = try #require(UserDefaults(suiteName: "calm-update-tests-\(UUID().uuidString)"))
        let checker = UpdateChecker(
            defaults: defaults, running: ReleaseVersion("0.1.0"), feed: file, fetch: UpdateChecker.overNetwork, settingIsOn: { true },
        )
        let outcome = await checker.check(byHand: true)
        #expect(outcome.isOffer(of: "0.9.0"))
    }
}

private extension UpdateChecker.Outcome {
    func isOffer(of version: String) -> Bool {
        if case let .offer(release) = self {
            return release.version.description == version
        }
        return false
    }
}

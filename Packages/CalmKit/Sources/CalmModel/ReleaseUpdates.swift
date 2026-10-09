import Foundation

/// A Calm version, `MAJOR.MINOR.PATCH`: how a release's tag (`v0.1.0`) and the app's own bundle write it.
public struct ReleaseVersion: Comparable, Hashable, Sendable, CustomStringConvertible {
    public let major: Int
    public let minor: Int
    public let patch: Int

    /// `0.1.0` or `v0.1.0`. Nil for anything else (a suffix such as `-beta`, fewer or more than
    /// three numbers): such a tag isn't one of Calm's releases, so it is never offered.
    public init?(_ text: String) {
        var rest = Substring(text.trimmingCharacters(in: .whitespacesAndNewlines))
        if rest.hasPrefix("v") {
            rest = rest.dropFirst()
        }
        let parts = rest.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3 else { return nil }
        let numbers = parts.compactMap { part in
            part.isEmpty || !part.allSatisfy { $0.isASCII && $0.isNumber } ? nil : Int(part)
        }
        guard numbers.count == 3 else { return nil }
        (major, minor, patch) = (numbers[0], numbers[1], numbers[2])
    }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        (lhs.major, lhs.minor, lhs.patch) < (rhs.major, rhs.minor, rhs.patch)
    }

    public var description: String {
        "\(major).\(minor).\(patch)"
    }
}

/// A release on GitHub, as far as the update notice needs it.
public struct CalmRelease: Equatable, Sendable {
    public let version: ReleaseVersion
    /// The release's page: its notes and the disk image.
    public let page: String

    public init(version: ReleaseVersion, page: String) {
        self.version = version
        self.page = page
    }
}

/// Where Calm looks for a newer release, and what it tells you to run (FEATURES.md → Updates).
public enum CalmUpdates {
    /// GitHub's list of the releases, not `/releases/latest`: that one leaves out pre-releases and
    /// answers 404 while every release is one, as 0.1.0 is.
    public static let feedAddress = "https://api.github.com/repos/jinhuang712/calm/releases?per_page=20"

    /// The one-line install (get.sh): it takes macOS's download mark off and replaces Calm in
    /// Applications, with a running Calm left working.
    public static let installCommand = "curl -fsSL https://raw.githubusercontent.com/jinhuang712/calm/main/get.sh | bash"

    /// What updates a Calm that Homebrew installed. get.sh refuses to replace that one, since
    /// Homebrew keeps its own record of the app.
    public static let homebrewCommand = "brew upgrade --cask calm"

    /// The command that updates Calm the way it was installed.
    public static func updateCommand(installedByHomebrew: Bool) -> String {
        installedByHomebrew ? homebrewCommand : installCommand
    }
}

/// Reads GitHub's list of a repository's releases (`GET /repos/{owner}/{repo}/releases`).
public enum ReleaseFeed {
    public struct NotAReleaseList: Error, Equatable, CustomStringConvertible {
        public var description: String {
            "GitHub's answer isn't a list of releases"
        }
    }

    /// Only what is read; a field GitHub adds or leaves out never fails the list.
    private struct Entry: Decodable {
        let tag: String?
        let page: String?
        let draft: Bool?

        enum CodingKeys: String, CodingKey {
            case tag = "tag_name"
            case page = "html_url"
            case draft
        }
    }

    /// The release with the highest version, whichever way GitHub ordered the list. A draft is
    /// skipped, and so is a tag that isn't `MAJOR.MINOR.PATCH`. GitHub's pre-release flag isn't
    /// looked at: every 0.x release carries it. Nil when none qualifies.
    public static func newest(in data: Data) throws -> CalmRelease? {
        guard let entries = try? JSONDecoder().decode([Entry].self, from: data) else { throw NotAReleaseList() }
        let releases = entries.compactMap { entry -> CalmRelease? in
            guard entry.draft != true, let tag = entry.tag, let version = ReleaseVersion(tag) else { return nil }
            return CalmRelease(version: version, page: entry.page ?? "")
        }
        return releases.max { $0.version < $1.version }
    }
}

/// What the update notice shows.
public enum UpdateOffer {
    /// The release to tell about: newer than the running version, and not one that was skipped. A
    /// release newer than the skipped one is offered again.
    public static func release(newest: CalmRelease?, running: ReleaseVersion, skipped: ReleaseVersion?) -> CalmRelease? {
        guard let newest, newest.version > running, newest.version != skipped else { return nil }
        return newest
    }
}

/// When Calm asks again: once a day while it is in use, and after a failure not sooner than an
/// hour, so being offline or rate limited never turns into a request on every launch or switch.
public enum UpdateSchedule {
    public static let interval: TimeInterval = 24 * 60 * 60
    public static let retryAfter: TimeInterval = 60 * 60

    public static func isDue(lastChecked: Date?, lastAttempt: Date?, now: Date) -> Bool {
        if let lastAttempt, lastAttempt <= now, now.timeIntervalSince(lastAttempt) < retryAfter {
            return false
        }
        // A last check in the future is a clock that was wrong; it must not hold checks back.
        guard let lastChecked, lastChecked <= now else { return true }
        return now.timeIntervalSince(lastChecked) >= interval
    }
}

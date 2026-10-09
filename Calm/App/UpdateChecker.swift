import AppKit
import CalmModel
import Foundation

/// Asks GitHub whether a newer Calm is out, and keeps the answer for the sidebar's notice
/// (FEATURES.md → Updates, DESIGNS.md → Updates). It only tells: Calm doesn't install itself, so
/// the notice's menu points to the release and to the one-line install.
///
/// There is no timer. A check runs a few seconds after launch and whenever Calm comes forward,
/// each time only when one is due (once a day; an hour after a failure, `UpdateSchedule`), so a
/// Calm left running for weeks costs nothing between looks. The request is one GET of GitHub's
/// list of releases, sent with the ETag of the last answer, so an unchanged list is a short 304.
/// (Measured 2026-10-09: a 304 still counts against the 60 requests an hour GitHub allows an
/// address without a token. One check a day is far under that.)
@MainActor @Observable
final class UpdateChecker {
    static let shared = UpdateChecker()

    /// What a check came to.
    enum Outcome: Equatable {
        case offer(CalmRelease)
        case upToDate(ReleaseVersion)
        case failed(String)
    }

    typealias Fetch = @Sendable (URLRequest) async throws -> (Data, URLResponse)

    /// The release the sidebar's notice shows: newer than the running one and not skipped.
    private(set) var offer: CalmRelease?
    /// A check by hand (Calm → Check for Updates…) is under way.
    private(set) var isChecking = false

    private enum Key {
        static let lastChecked = "update.lastChecked"
        static let lastAttempt = "update.lastAttempt"
        static let etag = "update.etag"
        static let latestVersion = "update.latestVersion"
        static let latestPage = "update.latestPage"
        static let skipped = "update.skipped"
    }

    private struct BadStatus: Error, CustomStringConvertible {
        let code: Int
        var description: String {
            // 403 and 429 are GitHub's limit on requests from one address.
            guard [403, 429].contains(code) else { return "GitHub answered \(code)." }
            return "GitHub is limiting requests from this address (\(code)). Try again later."
        }
    }

    private let defaults: UserDefaults
    /// The version this Calm is.
    let running: ReleaseVersion?
    private let feed: URL?
    private let fetch: Fetch
    private let now: () -> Date
    private let settingIsOn: @MainActor () -> Bool
    private var started = false

    init(
        defaults: UserDefaults = .standard,
        running: ReleaseVersion? = UpdateChecker.bundleVersion,
        feed: URL? = UpdateChecker.feedURL,
        fetch: @escaping Fetch = UpdateChecker.overNetwork,
        now: @escaping () -> Date = { Date() },
        settingIsOn: @escaping @MainActor () -> Bool = { SessionManager.shared.settings.checksForUpdates },
    ) {
        self.defaults = defaults
        self.running = running
        self.feed = feed
        self.fetch = fetch
        self.now = now
        self.settingIsOn = settingIsOn
        offer = currentOffer()
    }

    // MARK: Where it looks

    /// The version in the app's own Info.plist.
    nonisolated static var bundleVersion: ReleaseVersion? {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String).flatMap(ReleaseVersion.init)
    }

    /// `CALM_UPDATE_FEED` points a test at a file or a local server, which runs the real path
    /// without the network; otherwise GitHub's list.
    nonisolated static var feedURL: URL? {
        if let override = ProcessInfo.processInfo.environment["CALM_UPDATE_FEED"], !override.isEmpty {
            return URL(string: override)
        }
        return URL(string: CalmUpdates.feedAddress)
    }

    /// Whether Calm looks on its own at all: a shipped build, and not under a unit test or in a
    /// headless self-test, where no run should reach the network. A test that sets
    /// `CALM_UPDATE_FEED` asks for the real path.
    nonisolated static var looksOnItsOwn: Bool {
        if ProcessInfo.processInfo.environment["CALM_UPDATE_FEED"] != nil {
            return true
        }
        let isTesting = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
        return !BuildVariant.isDev && !Headless.isOn && !isTesting
    }

    /// The system's URL loading, with nothing kept: no cookies and no cache. The ETag is sent by hand.
    private nonisolated static let session = URLSession(configuration: .ephemeral)

    nonisolated static let overNetwork: Fetch = { request in
        try await session.data(for: request)
    }

    // MARK: Checking

    /// At launch: the saved answer shows at once, and a check follows a few seconds later when one
    /// is due, and then whenever Calm comes forward.
    func start() {
        guard !started, Self.looksOnItsOwn else { return }
        started = true
        NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { UpdateChecker.shared.checkIfDue() }
        }
        // After the first frame and the sessions, so the check never competes with them.
        Task {
            try? await Task.sleep(for: .seconds(8))
            checkIfDue()
        }
    }

    /// The setting is on, and a day has passed since the last answer (or an hour since a failure).
    var isDue: Bool {
        settingIsOn() && !isChecking
            && UpdateSchedule.isDue(
                lastChecked: defaults.object(forKey: Key.lastChecked) as? Date,
                lastAttempt: defaults.object(forKey: Key.lastAttempt) as? Date,
                now: now(),
            )
    }

    func checkIfDue() {
        guard isDue else { return }
        Task { await check(byHand: false) }
    }

    /// Looks now. By hand (Calm → Check for Updates…) it ignores the schedule and the setting,
    /// and a version that was skipped is offered again, since you asked.
    @discardableResult
    func check(byHand: Bool) async -> Outcome {
        guard let running, let feed else { return .failed("This build doesn't know its own version.") }
        isChecking = byHand
        defer { isChecking = false }
        let attempted = now()
        defaults.set(attempted, forKey: Key.lastAttempt)
        var request = URLRequest(url: feed, timeoutInterval: 15)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        // GitHub's API refuses a request with no User-Agent. It carries the version and nothing else.
        request.setValue("Calm/\(running) (update check)", forHTTPHeaderField: "User-Agent")
        if let etag = defaults.string(forKey: Key.etag), defaults.string(forKey: Key.latestVersion) != nil {
            request.setValue(etag, forHTTPHeaderField: "If-None-Match")
        }
        do {
            let (data, response) = try await fetch(request)
            // A file (the test feed) has no status.
            let status = (response as? HTTPURLResponse)?.statusCode ?? 200
            if status != 304 {
                guard (200 ..< 300).contains(status) else { throw BadStatus(code: status) }
                let newest = try ReleaseFeed.newest(in: data)
                save(newest, etag: (response as? HTTPURLResponse)?.value(forHTTPHeaderField: "ETag"))
            }
            defaults.set(attempted, forKey: Key.lastChecked)
            if byHand {
                defaults.removeObject(forKey: Key.skipped)
            }
            offer = currentOffer()
            return offer.map(Outcome.offer) ?? .upToDate(running)
        } catch {
            return .failed(error is BadStatus || error is ReleaseFeed.NotAReleaseList ? "\(error)" : error.localizedDescription)
        }
    }

    /// Stops offering this release, until a newer one comes out (or a check by hand).
    func skip(_ release: CalmRelease) {
        defaults.set(release.version.description, forKey: Key.skipped)
        offer = currentOffer()
    }

    // MARK: What is kept

    private func save(_ newest: CalmRelease?, etag: String?) {
        defaults.set(newest?.version.description, forKey: Key.latestVersion)
        defaults.set(newest?.page, forKey: Key.latestPage)
        defaults.set(etag, forKey: Key.etag)
    }

    private func currentOffer() -> CalmRelease? {
        guard let running else { return nil }
        let newest = defaults.string(forKey: Key.latestVersion).flatMap(ReleaseVersion.init).map {
            CalmRelease(version: $0, page: defaults.string(forKey: Key.latestPage) ?? "")
        }
        let skipped = defaults.string(forKey: Key.skipped).flatMap(ReleaseVersion.init)
        return UpdateOffer.release(newest: newest, running: running, skipped: skipped)
    }

    // MARK: What a click does

    /// The release's page, or the list of releases when GitHub gave none.
    static func openReleasePage(_ release: CalmRelease) {
        let page = URL(string: release.page).flatMap { $0.scheme == "https" ? $0 : nil }
        guard let url = page ?? URL(string: "https://github.com/jinhuang712/calm/releases") else { return }
        NSWorkspace.shared.open(url)
    }

    /// Whether Homebrew installed this Calm: it keeps the cask's record in its Caskroom (get.sh looks
    /// in the same two places, for Apple silicon and for Intel).
    static func installedByHomebrew(exists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }) -> Bool {
        ["/opt/homebrew/Caskroom/calm", "/usr/local/Caskroom/calm"].contains(where: exists)
    }

    /// The command that updates Calm the way it was installed, through Calm's own pasteboard,
    /// which a self-test keeps off the user's clipboard.
    static func copyUpdateCommand() {
        let pasteboard = NSPasteboard.calm
        pasteboard.clearContents()
        pasteboard.setString(CalmUpdates.updateCommand(installedByHomebrew: installedByHomebrew()), forType: .string)
    }
}

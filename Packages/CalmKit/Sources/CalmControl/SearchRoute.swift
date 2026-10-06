/// Where `calm search` takes its results from, given how Calm answered (CLI.md → `calm search`).
public enum SearchRoute: Equatable, Sendable {
    case results([ControlResponse.SearchHit])
    /// Calm answered with an error: say it, rather than search behind its back (a Calm older than
    /// the CLI says to update it, which the index can't).
    case refused(String)
    /// Nobody to ask: search the index directly. `notice` says why when Calm is there but didn't
    /// answer; with Calm not running, reading the index is simply how search works.
    case index(notice: String?)

    public static func from(_ answer: Result<ControlResponse, any Error>) -> SearchRoute {
        switch answer {
        case let .success(response):
            return response.ok ? .results(response.results ?? []) : .refused(response.error ?? "Calm couldn't search.")
        case let .failure(error):
            if case .notRunning = error as? ControlClient.ClientError {
                return .index(notice: nil)
            }
            return .index(notice: "Calm didn't answer, so this searched the index directly.")
        }
    }
}

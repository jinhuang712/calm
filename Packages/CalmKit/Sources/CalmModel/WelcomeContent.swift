import Foundation

/// What the welcome page shows in its middle (UIUX.md → Welcome page).
public enum WelcomeContent: Equatable, Sendable {
    /// The three ways to start, one row each; a welcome above them on the first launch.
    case actions
    /// Search, and a list of recent sessions, of projects, or both.
    case lists(sessions: Bool, projects: Bool)

    /// `hasSessions` is whether the search index knows any session at all (nil until it has
    /// answered, when the list is assumed to be coming, so the page doesn't rearrange under the
    /// user's eyes for the common case). A new user with no project is welcomed whatever the index
    /// holds; once they make a project, or when there is nothing at all to list, the page follows
    /// what there is, so a project can never be out of reach.
    public static func choose(firstUse: Bool, hasSessions: Bool?, hasProjects: Bool) -> WelcomeContent {
        if !hasProjects, firstUse || hasSessions == false {
            return .actions
        }
        return .lists(sessions: hasSessions != false, projects: hasProjects)
    }
}

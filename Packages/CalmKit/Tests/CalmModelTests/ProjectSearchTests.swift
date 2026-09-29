@testable import CalmModel
import Foundation
import Testing

/// FEATURES.md → F2, the welcome page: projects are searchable along with sessions.
struct ProjectSearchTests {
    let home = "/Users/me"

    func project(_ path: String, name: String? = nil) -> Project {
        Project(path: path, name: name)
    }

    @Test func `a query is split into words`() {
        #expect(ProjectSearch.terms(in: "  cal   dev\tapps ") == ["cal", "dev", "apps"])
        #expect(ProjectSearch.terms(in: "   ").isEmpty)
    }

    @Test func `a project matches by name or by the folder as shown`() {
        let calm = project("/Users/me/dev/apps/calm")
        #expect(ProjectSearch.matches(calm, terms: ["cal"], home: home))
        #expect(ProjectSearch.matches(calm, terms: ["dev/apps"], home: home))
        #expect(ProjectSearch.matches(calm, terms: ["CALM"], home: home))
        #expect(!ProjectSearch.matches(calm, terms: ["website"], home: home))
    }

    @Test func `every word has to fit, in the name or the folder`() {
        let calm = project("/Users/me/dev/apps/calm")
        #expect(ProjectSearch.matches(calm, terms: ["apps", "calm"], home: home))
        #expect(!ProjectSearch.matches(calm, terms: ["apps", "website"], home: home))
    }

    @Test func `what the page abbreviates cannot match, so nothing matches without being marked`() {
        let calm = project("/Users/me/dev/apps/calm")
        #expect(!ProjectSearch.matches(calm, terms: ["users"], home: home))
        #expect(ProjectSearch.shownPath(of: calm, home: home) == "~/dev/apps/calm")
    }

    @Test func `accents and case are ignored`() {
        let cafe = project("/Users/me/Café", name: "Café")
        #expect(ProjectSearch.matches(cafe, terms: ["cafe"], home: home))
        #expect(ProjectSearch.matches(cafe, terms: ["CAFÉ"], home: home))
    }

    @Test func `the words are marked wherever they fall, once, in order`() {
        let text = "~/dev/localize"
        let marked = ProjectSearch.ranges(of: ["cal"], in: text).map { String(text[$0]) }
        #expect(marked == ["cal"])
        #expect(ProjectSearch.ranges(of: ["cal"], in: "calm calendar").count == 2)
        #expect(ProjectSearch.ranges(of: ["zzz"], in: text).isEmpty)
    }

    @Test func `overlapping words are marked as one stretch`() {
        let text = "calendar"
        let marked = ProjectSearch.ranges(of: ["cal", "lend"], in: text).map { String(text[$0]) }
        #expect(marked == ["calend"])
    }

    @Test func `the workspace lists the projects a query fits, in the sidebar's order, folders and scratch left out`() {
        var workspace = Workspace()
        let calm = workspace.addProject(path: "/Users/me/dev/apps/calm")
        _ = workspace.addProject(path: "/Users/me/dev/website")
        let localize = workspace.addProject(path: "/Users/me/dev/localize")
        _ = workspace.newSession(in: "/Users/me/calendar-folder") // a folder group, not a project
        #expect(workspace.madeProjects(matching: "", home: home).count == 3)
        #expect(workspace.madeProjects(matching: "cal", home: home).map(\.id) == [calm.id, localize.id])
        #expect(workspace.madeProjects(matching: "nothing like it", home: home).isEmpty)
    }
}

struct WelcomeContentTests {
    @Test func `a new user with no project is welcomed, whatever the index holds`() {
        #expect(WelcomeContent.choose(firstUse: true, hasSessions: true, hasProjects: false) == .actions)
        #expect(WelcomeContent.choose(firstUse: true, hasSessions: nil, hasProjects: false) == .actions)
    }

    @Test func `a project made on the first launch is never out of reach`() {
        // The first launch's whole run counts as the first use, so this is the bug to keep out:
        // make a project, close its session, and see only the welcome.
        #expect(WelcomeContent.choose(firstUse: true, hasSessions: false, hasProjects: true) == .lists(sessions: false, projects: true))
        #expect(WelcomeContent.choose(firstUse: true, hasSessions: true, hasProjects: true) == .lists(sessions: true, projects: true))
    }

    @Test func `later, both lists show when there is something for both`() {
        #expect(WelcomeContent.choose(firstUse: false, hasSessions: true, hasProjects: true) == .lists(sessions: true, projects: true))
    }

    @Test func `with no history the projects take the page, and with no projects the sessions do`() {
        #expect(WelcomeContent.choose(firstUse: false, hasSessions: false, hasProjects: true) == .lists(sessions: false, projects: true))
        #expect(WelcomeContent.choose(firstUse: false, hasSessions: true, hasProjects: false) == .lists(sessions: true, projects: false))
    }

    @Test func `with nothing to list the page shows the actions`() {
        #expect(WelcomeContent.choose(firstUse: false, hasSessions: false, hasProjects: false) == .actions)
    }

    @Test func `until the index has answered, sessions are assumed to be coming`() {
        #expect(WelcomeContent.choose(firstUse: false, hasSessions: nil, hasProjects: true) == .lists(sessions: true, projects: true))
        #expect(WelcomeContent.choose(firstUse: false, hasSessions: nil, hasProjects: false) == .lists(sessions: true, projects: false))
    }
}

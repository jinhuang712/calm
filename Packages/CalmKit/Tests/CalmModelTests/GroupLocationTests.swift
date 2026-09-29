@testable import CalmModel
import Testing

struct GroupLocationTests {
    private let home = "/Users/ada"

    @Test func `a folder group says where its folder is`() {
        let nested = Project(path: "/Users/ada/dev/apps/calm", kind: .directory)
        #expect(nested.location(home: home) == "~/dev/apps")
        // Two groups named alike are told apart by the line under the name.
        let other = Project(path: "/Users/ada/projects/calm", kind: .directory)
        #expect(other.location(home: home) == "~/projects")
    }

    @Test func `a folder straight under home is at the tilde, one straight under the root at the slash`() {
        #expect(Project(path: "/Users/ada/cap", kind: .directory).location(home: home) == "~")
        #expect(Project(path: "/opt", kind: .directory).location(home: home) == "/")
        #expect(Project(path: "/opt/tools", kind: .directory).location(home: home) == "/opt")
    }

    @Test func `a folder that only starts like the home folder's name is not inside it`() {
        #expect(Project(path: "/Users/adam/dev/calm", kind: .directory).location(home: home) == "/Users/adam/dev")
    }

    @Test func `the home folder has no location`() {
        #expect(Project(path: "/Users/ada", kind: .directory).location(home: home) == nil)
        #expect(Project(path: "/Users/ada/", kind: .directory).location(home: home) == nil)
    }

    @Test func `a project and the scratch group have none either`() {
        #expect(Project(path: "/Users/ada/dev/calm", kind: .project).location(home: home) == nil)
        #expect(Project(path: "/Users/ada/Library/Calm/Scratch", kind: .scratch).location(home: home) == nil)
    }
}

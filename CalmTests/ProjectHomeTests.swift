@testable import Calm
import Testing

struct ProjectHomeTests {
    @Test func `nothing is chosen until an arrow key, and the first one lands on the first row`() {
        #expect(ProjectHomeModel.step(from: nil, by: 1, count: 3) == 0)
        // ↑ first too: the list starts at its top, not its end.
        #expect(ProjectHomeModel.step(from: nil, by: -1, count: 3) == 0)
    }

    @Test func `the arrows move one row and stop at the ends`() {
        #expect(ProjectHomeModel.step(from: 0, by: 1, count: 3) == 1)
        #expect(ProjectHomeModel.step(from: 2, by: 1, count: 3) == 2)
        #expect(ProjectHomeModel.step(from: 0, by: -1, count: 3) == 0)
    }

    @Test func `with no past sessions there is nothing to choose`() {
        #expect(ProjectHomeModel.step(from: nil, by: 1, count: 0) == nil)
        #expect(ProjectHomeModel.step(from: 2, by: 1, count: 0) == nil)
    }
}

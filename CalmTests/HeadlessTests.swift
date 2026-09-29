@testable import Calm
import Testing

struct HeadlessTests {
    @Test func `a headless run lives ten minutes past its snapshot delay`() {
        #expect(Headless.lifetime(snapshotDelay: nil) == 600)
        #expect(Headless.lifetime(snapshotDelay: 2.5) == 602.5)
        #expect(Headless.lifetime(snapshotDelay: 120) == 720)
    }

    @Test func `a negative delay doesn't shorten it`() {
        #expect(Headless.lifetime(snapshotDelay: -5) == 600)
    }
}

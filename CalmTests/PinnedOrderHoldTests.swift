@testable import Calm
import Foundation
import Testing

/// When Pinned's order stays still under the pointer (specs/FEATURES.md → F2).
@MainActor
struct PinnedOrderHoldTests {
    @Test func `the pointer holds the order it found, and leaving lets go`() {
        let hold = PinnedOrderHold(rest: .seconds(60))
        let first = [UUID(), UUID()]

        hold.pointerMoved(current: first)
        hold.pointerMoved(current: first.reversed())
        #expect(hold.order == first)

        hold.pointerLeft()
        #expect(hold.order == nil)
    }

    @Test func `a pointer at rest lets go`() async throws {
        let hold = PinnedOrderHold(rest: .milliseconds(10))
        hold.pointerMoved(current: [UUID()])

        try await Task.sleep(for: .milliseconds(300))
        #expect(hold.order == nil)
    }
}

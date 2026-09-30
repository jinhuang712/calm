@testable import CalmModel
import Testing

struct SplitHandleTests {
    private func shown(
        hasSplits: Bool = true, isFocused: Bool = false, isPointedAt: Bool = false, isBusy: Bool = false, isAsking: Bool = false,
    ) -> Bool {
        SplitHandle.isShown(hasSplits: hasSplits, isFocused: isFocused, isPointedAt: isPointedAt, isBusy: isBusy, isAsking: isAsking)
    }

    @Test func `a lone pane has no icon, whatever the pointer does`() {
        #expect(!shown(hasSplits: false, isFocused: true, isPointedAt: true, isBusy: true))
    }

    @Test func `at rest only the pane you're in shows it`() {
        #expect(shown(isFocused: true))
        #expect(!shown(isFocused: false))
    }

    @Test func `any pane shows it while the pointer is on it`() {
        #expect(shown(isPointedAt: true))
    }

    @Test func `a pane keeps it while its menu is open or it is dragged`() {
        #expect(shown(isBusy: true))
    }

    @Test func `a close question leaves the pane to itself`() {
        #expect(!shown(isFocused: true, isPointedAt: true, isBusy: true, isAsking: true))
    }
}

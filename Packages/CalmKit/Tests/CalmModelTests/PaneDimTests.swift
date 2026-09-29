@testable import CalmModel
import Testing

struct PaneDimTests {
    @Test func `a lone pane is never dimmed`() {
        #expect(PaneDim.veil(isFocused: false, hasSplits: false, isAsked: false, asking: false) == 0)
        #expect(PaneDim.veil(isFocused: true, hasSplits: false, isAsked: true, asking: true) == 0)
    }

    @Test func `in a split the focused pane stays bright and the others recede`() {
        #expect(PaneDim.veil(isFocused: true, hasSplits: true, isAsked: false, asking: false) == 0)
        let veil = PaneDim.veil(isFocused: false, hasSplits: true, isAsked: false, asking: false)
        #expect(abs(veil - (1 - PaneDim.unfocusedOpacity)) < 1e-9)
    }

    @Test func `while a pane is asked about the others almost go and it steps back a little`() {
        let others = PaneDim.veil(isFocused: false, hasSplits: true, isAsked: false, asking: true)
        let asked = PaneDim.veil(isFocused: false, hasSplits: true, isAsked: true, asking: true)
        #expect(others > asked)
        #expect(asked > 0)
        // The focused pane doesn't stay bright when another is the one asked about.
        #expect(PaneDim.veil(isFocused: true, hasSplits: true, isAsked: false, asking: true) == others)
    }
}

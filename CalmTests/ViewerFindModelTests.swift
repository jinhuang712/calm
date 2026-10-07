@testable import Calm
import Testing

@MainActor
struct ViewerFindModelTests {
    @Test func `opening searches the last words again, closing stops, the count is the page’s`() {
        let find = ViewerFindModel()
        var searched: [String] = []
        var closed = 0
        find.onSearch = { searched.append($0) }
        find.onClose = { closed += 1 }
        find.toggle()
        #expect(find.isOpen && find.focusRequest == 1)
        find.query = "error"
        #expect(searched == ["error"])
        find.show(total: 3, current: 0)
        #expect(find.countText == "1 of 3")
        #expect(find.upDisabled && !find.downDisabled)
        find.show(total: 3, current: 2)
        #expect(!find.upDisabled && find.downDisabled) // no wrapping, as in the terminal
        find.toggle()
        #expect(!find.isOpen && closed == 1)
        find.toggle()
        #expect(searched == ["error", "error"]) // the words come back and search again
    }

    @Test func `in a file ↵ goes down, and the words ⌘E picks replace the field’s`() {
        let find = ViewerFindModel()
        var steps: [Bool] = []
        var searched: [String] = []
        find.onStep = { steps.append($0) }
        find.onSearch = { searched.append($0) }
        #expect(!find.returnStepsUp)
        find.toggle(words: "parser")
        #expect(find.isOpen && searched == ["parser"])
        find.step(up: false)
        find.step(up: true)
        #expect(steps == [false, true])
    }

    @Test func `a web page's find has no count: only no matches, for the words searched`() {
        let find = ViewerFindModel()
        find.reset(for: .web)
        find.toggle()
        find.query = "error"
        find.show(found: true)
        #expect(find.countText == "" && !find.downDisabled)
        find.query = "segfault"
        #expect(find.found == nil) // the answer was for the old words
        find.show(found: false)
        #expect(find.countText == "No matches" && find.upDisabled && find.downDisabled)
    }

    @Test func `a picture has nothing to find: a quiet note, and no field`() {
        let find = ViewerFindModel()
        find.reset(for: .picture)
        find.toggle()
        #expect(!find.isOpen && find.showsPictureNote)
        find.hidePictureNote()
        #expect(!find.showsPictureNote)
    }
}

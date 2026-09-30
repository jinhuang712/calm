@testable import CalmModel
import Foundation
import Testing

struct SessionDragTests {
    @Test func `a drag reads back as it was written`() {
        let id = UUID()
        for origin in [SessionDrag.Origin.card, .pane] {
            let drag = SessionDrag(origin: origin, sessionID: id)
            #expect(SessionDrag(text: drag.text) == drag)
        }
    }

    @Test func `text that isn't a session drag is nothing`() {
        #expect(SessionDrag(text: "") == nil)
        #expect(SessionDrag(text: "hello") == nil)
        #expect(SessionDrag(text: "card:not-a-uuid") == nil)
        #expect(SessionDrag(text: "file:\(UUID().uuidString)") == nil)
    }

    @Test func `its type is Calm's own, so a terminal never takes it for a path`() {
        #expect(SessionDrag.typeIdentifier.hasPrefix("com.jinhuang.calm."))
    }
}

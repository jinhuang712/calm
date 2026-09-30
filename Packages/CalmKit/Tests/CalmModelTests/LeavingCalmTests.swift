@testable import CalmModel
import Foundation
import Testing

struct LeavingCalmTests {
    private let done = LeavingCalm.OnScreen(sessionID: UUID(), state: .done)

    @Test func `another app with a Dock icon is leaving`() {
        var leaving = LeavingCalm(calmIsActive: true)
        #expect(leaving.appCameForward(regular: true, onScreen: done) == done)
    }

    @Test func `a menu-bar tool and back is not leaving`() {
        var leaving = LeavingCalm(calmIsActive: true)
        #expect(leaving.appCameForward(regular: false, onScreen: done) == nil)
        leaving.calmCameForward()
        #expect(leaving.appCameForward(regular: false, onScreen: done) == nil)
    }

    @Test func `a menu-bar tool on the way to another app is leaving`() {
        var leaving = LeavingCalm(calmIsActive: true)
        #expect(leaving.appCameForward(regular: false, onScreen: done) == nil)
        #expect(leaving.appCameForward(regular: false, onScreen: done) == nil)
        #expect(leaving.appCameForward(regular: true, onScreen: done) == done)
    }

    @Test func `a session that finished while a tool was in front stays unseen`() {
        var leaving = LeavingCalm(calmIsActive: true)
        let working = LeavingCalm.OnScreen(sessionID: done.sessionID, state: .working)
        #expect(leaving.appCameForward(regular: false, onScreen: working) == nil)
        #expect(leaving.appCameForward(regular: true, onScreen: done) == nil)
    }

    @Test func `moving between other apps leaves nothing more`() {
        var leaving = LeavingCalm(calmIsActive: true)
        #expect(leaving.appCameForward(regular: true, onScreen: done) == done)
        // The session on screen finished while the user was away, in another app.
        #expect(leaving.appCameForward(regular: true, onScreen: done) == nil)
        #expect(leaving.appCameForward(regular: false, onScreen: done) == nil)
    }

    @Test func `nothing is left before Calm has been in front`() {
        var leaving = LeavingCalm(calmIsActive: false)
        #expect(leaving.appCameForward(regular: true, onScreen: done) == nil)
        leaving.calmCameForward()
        #expect(leaving.appCameForward(regular: true, onScreen: done) == done)
    }
}

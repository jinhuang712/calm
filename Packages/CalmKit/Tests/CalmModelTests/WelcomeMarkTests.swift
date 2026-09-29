@testable import CalmModel
import Foundation
import Testing

/// UIUX.md → Welcome page: the mark arrives once, then waits with a breathing cursor.
struct WelcomeMarkMotionTests {
    private func places(at time: TimeInterval) -> [AppIconFrame.Place] {
        WelcomeMarkMotion.frame(at: time).places
    }

    @Test func `at the start nothing is drawn yet`() {
        let frame = WelcomeMarkMotion.frame(at: 0)
        #expect(frame.places.allSatisfy { $0.ring == 0 && $0.cursor == 0 })
        #expect(frame.centerLevel == 0)
        #expect(frame.cursorVisibility == 0)
    }

    @Test func `the ring draws itself in typing order, one cell after another`() {
        // Places 2 to 11 are the ring's cells; each starts a little after the one before.
        for time in stride(from: 0.05, through: 1.1, by: 0.05) {
            let ring = places(at: time)[2 ... 11].map(\.ring)
            #expect(zip(ring, ring.dropFirst()).allSatisfy { $0 >= $1 }, "at \(time)")
        }
        // Early on only the first cells show.
        let early = places(at: 0.2)
        #expect(early[2].ring > 0)
        #expect(early[8].ring == 0)
    }

    @Test func `the cursor's resting place and the opening stay empty of ring while it arrives`() {
        for time in stride(from: 0, through: WelcomeMarkMotion.arrivalLength, by: 0.05) {
            let ring = places(at: time).map(\.ring)
            #expect(ring[0] == 0 && ring[1] == 0, "at \(time)")
        }
    }

    @Test func `the center comes after the ring has begun and before the cursor lands`() {
        #expect(WelcomeMarkMotion.frame(at: 0.5).centerLevel == 0)
        #expect(WelcomeMarkMotion.frame(at: 0.8).centerLevel > 0)
        #expect(WelcomeMarkMotion.frame(at: 0.8).centerLevel < 1)
        #expect(WelcomeMarkMotion.frame(at: 1.3).centerLevel == 1)
    }

    @Test func `the cursor appears on the ring's last cell, then takes the last step slowly`() {
        let waiting = places(at: 1.05)
        #expect(waiting[11].cursor > 0)
        #expect(waiting[0].cursor == 0)
        // Halfway through the step it is shared between the two places.
        let stepping = places(at: 1.6)
        #expect(stepping[11].cursor > 0 && stepping[0].cursor > 0)
        #expect(stepping[0].cursor > stepping[11].cursor)
        // And it ends on its resting place.
        let landed = places(at: WelcomeMarkMotion.arrivalLength - 0.001)
        #expect(landed[0].cursor > 0.99)
    }

    @Test func `when the arrival ends the mark is the finished icon`() {
        let frame = WelcomeMarkMotion.frame(at: WelcomeMarkMotion.arrivalLength)
        #expect(frame.arrival.isInfinite)
        #expect(frame.head == 0)
        #expect(frame.cursorLevel == 1)
        #expect(frame.places == AppIconFrame.still.places)
    }

    @Test func `then the cursor breathes between full and 42 percent, and only the cursor`() {
        let start = WelcomeMarkMotion.arrivalLength
        let levels = stride(from: 0.0, through: WelcomeMarkMotion.breathLength * 2, by: 0.05).map {
            WelcomeMarkMotion.frame(at: start + $0).cursorLevel
        }
        #expect(levels.min().map { abs($0 - 0.42) < 0.001 } == true)
        #expect(levels.max().map { abs($0 - 1) < 0.001 } == true)
        // It goes down and comes back once per breath.
        let half = WelcomeMarkMotion.frame(at: start + WelcomeMarkMotion.breathLength / 2)
        #expect(abs(half.cursorLevel - 0.42) < 0.001)
        #expect(abs(WelcomeMarkMotion.frame(at: start + WelcomeMarkMotion.breathLength).cursorLevel - 1) < 0.001)
        #expect(half.places[0].cursor == half.cursorLevel)
        #expect(half.places[2].ring == 1)
        #expect(half.centerLevel == 1)
    }

    @Test func `after eight breaths the mark rests as the still icon, with no jump`() {
        let rests = WelcomeMarkMotion.restsAfter
        #expect(WelcomeMarkMotion.frame(at: rests) == .still)
        #expect(WelcomeMarkMotion.frame(at: rests + 3600) == .still)
        // Just before, it is at the top of a breath, so the change is invisible.
        #expect(WelcomeMarkMotion.frame(at: rests - 0.001).cursorLevel > 0.999)
        #expect(abs(rests - (WelcomeMarkMotion.arrivalLength + 8 * 3.6)) < 0.0001)
    }

    @Test func `a breathing mark is not at rest, so the Dock never mistakes it for the still icon`() {
        #expect(!WelcomeMarkMotion.frame(at: 0.5).isAtRest)
        #expect(!WelcomeMarkMotion.frame(at: WelcomeMarkMotion.arrivalLength + 1.8).isAtRest)
        #expect(AppIconFrame.still.isAtRest)
    }

    @Test func `time before the start is the start`() {
        #expect(WelcomeMarkMotion.frame(at: -3) == WelcomeMarkMotion.frame(at: 0))
    }

    @Test func `a click runs one lap of the chase and settles back to the still mark`() {
        #expect(WelcomeMarkMotion.lapFrame(at: 0.6).busy > 0)
        #expect(WelcomeMarkMotion.lapFrame(at: 0.6).head > 0)
        #expect(WelcomeMarkMotion.lapFrame(at: WelcomeMarkMotion.lapLength + 0.1).isAtRest)
    }

    @Test func `the Dock icon's own frames are unchanged by the arrival`() {
        let running = AppIconFrame(busy: 1, head: 5, done: 0, failed: 0)
        #expect(running.arrival.isInfinite && running.cursorLevel == 1)
        #expect(running.centerLevel == 1)
        #expect(running.places[5] == .init(ring: 0, cursor: 1))
        #expect(running.rounded == running)
    }
}

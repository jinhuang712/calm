@testable import CalmModel
import Testing

struct AppIconStateTests {
    @Test(arguments: [
        ([SessionState](), AppIconState.idle),
        ([.idle, .needsYou], .idle),
        ([.idle, .done], .done),
        ([.done, .working], .running),
        ([.working, .failed, .done], .failed),
        ([.failed], .failed),
    ])
    func `a failure outranks work, which outranks finished work`(states: [SessionState], expected: AppIconState) {
        #expect(AppIconState.summarizing(states) == expected)
    }
}

struct AppIconFrameTests {
    @Test func `at rest the ring is open and the cursor sits just past its end`() {
        let places = AppIconFrame.still.places
        #expect(places.count == 12)
        #expect(places[0] == .init(ring: 0, cursor: 1))
        // The opening.
        #expect(places[1] == .init(ring: 0, cursor: 0))
        for place in places[2...] {
            #expect(place == .init(ring: 1, cursor: 0))
        }
    }

    @Test func `done closes the ring`() {
        let places = AppIconMotion.stillFrame(for: .done).places
        #expect(places[1].ring == 1)
        #expect(places[0].cursor == 1)
    }

    @Test func `while working a trail follows the cursor and the opening moves ahead of it`() {
        let places = AppIconFrame(busy: 1, head: 5, done: 0, failed: 0).places
        #expect(places[5] == .init(ring: 0, cursor: 1))
        #expect(places[6] == .init(ring: 0, cursor: 0))
        #expect(places[4].cursor == 0.55)
        #expect(places[3].cursor == 0.3)
        #expect(places[2].cursor == 0.12)
        #expect(places[1].cursor == 0)
        #expect(places[4].ring == 1)
    }

    @Test func `a lap later the cursor is back at rest`() {
        #expect(AppIconFrame(busy: 0, head: 24, done: 0, failed: 0).places == AppIconFrame.still.places)
    }
}

struct AppIconMotionTests {
    @Test func `the chase steps a place at a time`() {
        var motion = AppIconMotion()
        motion.show(.running, at: 10)
        #expect(motion.frame(at: 11).head == 8)
        // Holding on a place for most of its beat.
        #expect(motion.frame(at: 11.05).head == 8)
        #expect(motion.frame(at: 11).busy == 1)
        #expect(!motion.isStill(at: 11))
    }

    @Test func `in whole steps the chase jumps between places, 8 frames a second instead of 16`() {
        var motion = AppIconMotion()
        motion.show(.running, at: 0)
        // Mid-step: eased, the cursor is between places; in whole steps it hasn't left yet.
        #expect(motion.frame(at: 1.1).head > 8 && motion.frame(at: 1.1).head < 9)
        #expect(motion.frame(at: 1.1, wholeSteps: true).head == 8)
        // It arrives at the same moment either way.
        #expect(motion.frame(at: 1.125, wholeSteps: true).head == 9)
        #expect(motion.frame(at: 1.125).head == 9)
        /// Frames that differ at 30 ticks a second, over 3 s of the steady chase.
        func drawn(wholeSteps: Bool) -> Int {
            let heads = (30 ..< 120).map { motion.frame(at: Double($0) / 30, wholeSteps: wholeSteps).rounded.head }
            return zip(heads, heads.dropFirst()).count(where: { $0 != $1 }) + 1
        }
        #expect(drawn(wholeSteps: false) == 48)
        #expect(drawn(wholeSteps: true) == 24)
    }

    @Test func `in whole steps the settle still eases the last step`() {
        var motion = AppIconMotion()
        motion.show(.running, at: 0)
        motion.show(.done, at: 1)
        #expect(motion.frame(at: 1.375, wholeSteps: true).head == 11)
        let halfway = motion.frame(at: 1.6, wholeSteps: true).head
        #expect(halfway > 11 && halfway < 12)
        #expect(motion.frame(at: 1.825, wholeSteps: true).head == 12)
    }

    @Test func `when work is done the cursor settles at rest, then the ring closes`() {
        var motion = AppIconMotion()
        motion.show(.running, at: 0)
        motion.show(.done, at: 1) // eight places in
        // Keeps stepping to the place before its resting one, then takes the last step slowly.
        #expect(motion.frame(at: 1.375).head == 11)
        #expect(motion.frame(at: 1.6).head > 11)
        #expect(motion.frame(at: 1.825).head == 12)
        #expect(motion.frame(at: 1.825).done == 0)
        let settled = motion.frame(at: 2.4)
        #expect(settled.done == 1)
        #expect(settled.busy == 0)
        #expect(settled.places == AppIconMotion.stillFrame(for: .done).places)
        #expect(motion.isStill(at: 2.4))
    }

    @Test func `leaving done turns the icon back without moving the cursor`() {
        var motion = AppIconMotion()
        motion.show(.done, at: 0)
        #expect(motion.frame(at: 0.5).done == 1)
        motion.show(.idle, at: 1)
        #expect(motion.frame(at: 1.25).done > 0)
        #expect(motion.frame(at: 1.5) == .still)
        #expect(motion.isStill(at: 1.5))
    }

    @Test func `failing dims the icon after the settle`() {
        var motion = AppIconMotion()
        motion.show(.running, at: 0)
        motion.show(.failed, at: 1.5) // exactly a lap: already at rest
        #expect(motion.frame(at: 1.5).head == 12)
        #expect(motion.frame(at: 3).failed == 1)
        #expect(motion.frame(at: 3).done == 0)
    }

    @Test func `after a run the icon is at rest again, laps later`() {
        var motion = AppIconMotion()
        motion.show(.running, at: 0)
        motion.show(.idle, at: 2)
        let rested = motion.frame(at: 4).rounded
        #expect(rested.head == 24)
        #expect(rested.isAtRest)
        #expect(!motion.frame(at: 2.5).rounded.isAtRest)
        #expect(AppIconFrame.still.isAtRest)
    }

    @Test func `work resuming mid-settle carries on from where the cursor is`() {
        var motion = AppIconMotion()
        motion.show(.running, at: 0)
        motion.show(.idle, at: 1)
        let head = motion.frame(at: 1.2).head
        motion.show(.running, at: 1.2)
        #expect(abs(motion.frame(at: 1.2).head - head) < 0.001)
        #expect(motion.frame(at: 2.2).head >= head + 7)
    }

    @Test func `with reduced motion running still shows its trail`() {
        let running = AppIconMotion.stillFrame(for: .running)
        #expect(running.busy == 1)
        #expect(running.places[11].cursor == 0.55)
        #expect(AppIconMotion.stillFrame(for: .idle) == .still)
    }
}

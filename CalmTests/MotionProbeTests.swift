#if DEBUG
    @testable import Calm
    import Foundation
    import Testing

    /// The self-test motion probe's analysis (`MotionProbe`), on made-up row profiles.
    struct MotionProbeTests {
        /// A profile with an unrelated value on every row, like text of varying length: a
        /// repeating one would let a large shift pass for a small one.
        private func profile(count: Int = 400, seed: UInt64 = 7) -> [Float] {
            var state = seed
            return (0 ..< count).map { _ in
                state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
                return Float(state >> 56)
            }
        }

        @Test func `a frame that moved up is measured in pixels`() {
            let before = profile()
            let after = Array(before.dropFirst(13)) + Array(repeating: 0, count: 13)
            #expect(MotionProbe.shift(from: before, to: after, maxShift: 40) == 13)
        }

        @Test func `a frame that moved down is a negative shift`() {
            let before = profile()
            let after = Array(repeating: 0, count: 5) + Array(before.dropLast(5))
            #expect(MotionProbe.shift(from: before, to: after, maxShift: 40) == -5)
        }

        @Test func `an unchanged frame has no shift`() {
            let frame = profile()
            #expect(MotionProbe.shift(from: frame, to: frame, maxShift: 40) == 0)
        }

        @Test func `a change no shift explains is in place`() {
            #expect(MotionProbe.shift(from: profile(seed: 7), to: profile(seed: 31), maxShift: 40) == nil)
        }

        @Test func `the report counts moves that aren't whole rows`() {
            let report = MotionProbe.Report(frames: 4, shifts: [34, 12, 68, 5], cellHeight: 34)
            #expect(report.offRow == 2)
            #expect(report.summary.contains("moves off whole rows: 2/4"))
        }

        @Test func `the report says how many frames were presented, alike or not`() {
            let report = MotionProbe.Report(frames: 2, samples: 40, presents: 5)
            #expect(report.summary.contains("(40 samples, 5 presented)"))
        }

        @Test func `a cell rectangle reads as columns and rows`() throws {
            let cells = try #require(MotionProbe.Cells("0,1,12,30"))
            #expect(cells.columns == 0 ... 12)
            #expect(cells.rows == 1 ... 30)
            #expect(MotionProbe.Cells("3,1") == nil)
            #expect(MotionProbe.Cells("5,1,2,30") == nil)
        }

        @Test func `a watched color reads as hex and matches near it`() throws {
            let magenta = try #require(MotionProbe.Color("ff00ff"))
            #expect(magenta.matches(blue: 255, green: 0, red: 255))
            // sRGB magenta as a Display P3 frame stores it.
            #expect(magenta.matches(blue: 244, green: 51, red: 234))
            #expect(!magenta.matches(blue: 128, green: 128, red: 128))
            #expect(MotionProbe.Color("ff00") == nil)
            #expect(MotionProbe.Color("zzzzzz") == nil)
        }
    }
#endif

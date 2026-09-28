#if DEBUG
    import Accelerate
    import AppKit
    import IOSurface

    /// Measures how the focused terminal's picture moves (self-tests, `CALM_SELFTEST_MOTION`): reads
    /// the frames libghostty presents for a while and logs how far the content shifted vertically
    /// from each frame to the next. Smooth scrolling shows as shifts that aren't whole rows; without
    /// it, every move is a multiple of the cell height.
    enum MotionProbe {
        struct Report: Equatable {
            /// Frames that differed from the one before.
            var frames = 0
            /// Vertical shift of each frame that moved, in pixels; positive is content moving up.
            var shifts: [Int] = []
            /// Frames that changed in place: no shift explained them.
            var inPlace = 0
            var cellHeight = 0
            /// Median time between frames that moved, in milliseconds.
            var frameInterval = 0.0
            /// Frames read, changed or not: well above the frame rate, or frames were missed.
            var samples = 0

            /// Moves that weren't a whole number of rows.
            var offRow: Int {
                cellHeight > 0 ? shifts.count(where: { $0 % cellHeight != 0 }) : 0
            }

            /// Fills in the frames, shifts and timing from consecutive distinct frames.
            mutating func analyze(_ frames: [(time: ContinuousClock.Instant, profile: [Float])]) {
                let maxShift = max(cellHeight, 1) * 16
                var lastMove: ContinuousClock.Instant?
                var intervals: [Double] = []
                for (previous, current) in zip(frames, frames.dropFirst()) {
                    self.frames += 1
                    switch MotionProbe.shift(from: previous.profile, to: current.profile, maxShift: maxShift) {
                    case let .some(dy) where dy != 0:
                        shifts.append(dy)
                        if let lastMove {
                            intervals.append(Double((current.time - lastMove) / .microseconds(1)) / 1000)
                        }
                        lastMove = current.time
                    case .some: break
                    case .none: inPlace += 1
                    }
                }
                frameInterval = intervals.sorted().dropFirst(intervals.count / 2).first ?? 0
            }

            var summary: String {
                "motion: \(frames) frames, \(shifts.count) moved, \(inPlace) changed in place; cell \(cellHeight)px; "
                    + "moving frames every \(frameInterval.formatted(.number.precision(.fractionLength(1)))) ms "
                    + "(\(samples) samples); "
                    + "moves off whole rows: \(offRow)/\(shifts.count); shifts px: "
                    + shifts.map(String.init).joined(separator: ",")
            }
        }

        /// A rectangle of cells to watch, inclusive: `CALM_SELFTEST_MOTION_CELLS=col,row,col,row`.
        /// Small moving text (a list in the first columns) is lost among static parts in a
        /// whole-frame profile.
        struct Cells {
            var columns: ClosedRange<Int>
            var rows: ClosedRange<Int>

            init?(_ text: String) {
                let parts = text.split(separator: ",").compactMap { Int($0) }
                guard parts.count == 4, parts[0] <= parts[2], parts[1] <= parts[3] else { return nil }
                columns = parts[0] ... parts[2]
                rows = parts[1] ... parts[3]
            }
        }

        /// Samples `pane`'s presented frames every few milliseconds for `seconds`, the whole frame
        /// or only `cells`. Sampling only keeps each new frame's profile; the shifts are worked out
        /// afterwards, so the analysis never delays a sample.
        @MainActor
        static func run(on pane: TerminalSurfaceView, seconds: Double, cells: Cells? = nil) async -> Report {
            var report = Report(cellHeight: pane.cellHeightPixelsForTesting)
            // Grid padding is left out: a few pixels either way don't matter to a profile.
            let (width, height) = (pane.cellWidthPixelsForTesting, report.cellHeight)
            let columns = cells.map { $0.columns.lowerBound * width ..< ($0.columns.upperBound + 1) * width }
            let rows = cells.map { $0.rows.lowerBound * height ..< ($0.rows.upperBound + 1) * height }
            let end = ContinuousClock.now + .seconds(seconds)
            var frames: [(time: ContinuousClock.Instant, profile: [Float])] = []
            while ContinuousClock.now < end {
                if let surface = pane.presentedFrameForTesting,
                   let profile = rowProfile(of: surface, columns: columns, rows: rows) {
                    report.samples += 1
                    if profile != frames.last?.profile {
                        frames.append((ContinuousClock.now, profile))
                    }
                }
                // Well under a 120 Hz frame, so no presented frame is missed.
                try? await Task.sleep(for: .milliseconds(2))
            }
            report.analyze(frames)
            if let dump = ProcessInfo.processInfo.environment["CALM_SELFTEST_MOTION_DUMP"], let start = frames.first?.time {
                // One line per distinct frame: milliseconds since the first, then its profile.
                let lines = frames.map { frame in
                    ([Double((frame.time - start) / .microseconds(1)) / 1000] + frame.profile.map(Double.init))
                        .map { String(format: "%.2f", $0) }.joined(separator: ",")
                }
                try? lines.joined(separator: "\n").write(toFile: dump, atomically: true, encoding: .utf8)
            }
            return report
        }

        /// Mean brightness of each pixel row in `rows`, across `columns` (all of them by default: a
        /// program's moving text can sit at either edge). Every pixel counts: glyph strokes are a
        /// few pixels wide, and sampling columns misses them. `nil` unless the frame is 32-bit BGRA.
        static func rowProfile(of surface: IOSurface, columns: Range<Int>? = nil, rows: Range<Int>? = nil) -> [Float]? {
            guard surface.pixelFormat == kCVPixelFormatType_32BGRA, surface.width > 0, surface.height > 0 else { return nil }
            let columns = (columns ?? 0 ..< surface.width).clamped(to: 0 ..< surface.width)
            let rows = (rows ?? 0 ..< surface.height).clamped(to: 0 ..< surface.height)
            guard !columns.isEmpty, !rows.isEmpty else { return nil }
            guard surface.lock(options: .readOnly, seed: nil) == kIOReturnSuccess else { return nil }
            defer { surface.unlock(options: .readOnly, seed: nil) }
            let base = surface.baseAddress.assumingMemoryBound(to: UInt8.self)
            let (stride, pixels) = (surface.bytesPerRow, columns.count)
            var bytes = [Float](repeating: 0, count: pixels * 4)
            return rows.map { y in
                // vDSP keeps this fast in Debug builds, where a per-pixel Swift loop can't keep up
                // with 120 Hz. The alpha bytes are 255 in an opaque frame and are taken out after.
                vDSP_vfltu8(base.advanced(by: y * stride + columns.lowerBound * 4), 1, &bytes, 1, vDSP_Length(bytes.count))
                var sum: Float = 0
                vDSP_sve(bytes, 1, &sum, vDSP_Length(bytes.count))
                return (sum - 255 * Float(pixels)) / Float(pixels * 3)
            }
        }

        /// The vertical shift in pixels (positive: the content moved up) that best maps `previous`
        /// onto `current`, up to `maxShift`: 0 when they match as they are, `nil` when no shift
        /// explains the change much better than none (the content changed in place). Each shift is
        /// judged on the rows the two frames still share.
        static func shift(from previous: [Float], to current: [Float], maxShift: Int) -> Int? {
            let count = min(previous.count, current.count)
            let maxShift = min(maxShift, count / 2)
            guard count > 1 else { return nil }
            var difference = [Float](repeating: 0, count: count)
            func error(_ dy: Int) -> Float {
                // Row y of `current` against row y + dy of `previous`, where both exist.
                let rows = max(0, -dy) ..< min(count, count - dy)
                previous.withUnsafeBufferPointer { previous in
                    current.withUnsafeBufferPointer { current in
                        vDSP_vsub(
                            previous.baseAddress! + rows.lowerBound + dy,
                            1,
                            current.baseAddress! + rows.lowerBound,
                            1,
                            &difference,
                            1,
                            vDSP_Length(rows.count),
                        )
                    }
                }
                var total: Float = 0
                vDSP_svemg(difference, 1, &total, vDSP_Length(rows.count))
                return total / Float(rows.count)
            }
            let still = error(0)
            if still < 0.01 {
                return 0
            }
            var best = (dy: 0, error: still)
            for dy in -maxShift ... maxShift where dy != 0 {
                let candidate = error(dy)
                if candidate < best.error {
                    best = (dy, candidate)
                }
            }
            // A scroll leaves the rows it brings in unexplained, so a real shift explains most of
            // the change, not all of it.
            return best.dy != 0 && best.error < still * 0.5 ? best.dy : nil
        }
    }
#endif

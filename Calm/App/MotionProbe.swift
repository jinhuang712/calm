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
            /// With a watched color: the most pixel rows showing it in one frame, and how many
            /// frames showed it on more than one row's height (something drawn twice).
            var colorRows: Int?
            var colorFramesOver = 0
            /// When those frames came, in milliseconds since the first frame.
            var colorOverAt: [Int] = []

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
                    + "moves off whole rows: \(offRow)/\(shifts.count); "
                    + (colorRows.map {
                        "color rows: max \($0) px, frames over one row: \(colorFramesOver) "
                            + "(at ms \(colorOverAt.map(String.init).joined(separator: ","))); "
                    } ?? "")
                    + "shifts px: " + shifts.map(String.init).joined(separator: ",")
            }
        }

        /// A color to count in each frame, `CALM_SELFTEST_MOTION_COLOR=ff00ff`. The frame is Display
        /// P3 and the config's colors aren't, so it matches within `tolerance` on each channel.
        struct Color {
            var red, green, blue: Int
            static let tolerance = 64

            init?(_ hex: String) {
                guard hex.count == 6, let value = Int(hex, radix: 16) else { return nil }
                red = value >> 16 & 0xFF
                green = value >> 8 & 0xFF
                blue = value & 0xFF
            }

            func matches(blue b: UInt8, green g: UInt8, red r: UInt8) -> Bool {
                abs(Int(r) - red) <= Self.tolerance && abs(Int(g) - green) <= Self.tolerance
                    && abs(Int(b) - blue) <= Self.tolerance
            }
        }

        /// How many pixel rows in `rows` show `color` across `columns`: a few matching pixels make a
        /// row count, so text drawn over the color doesn't hide it. With `keep`, also the frame's
        /// pixels as read, since libghostty may draw the next frame into the same surface before a
        /// second read.
        static func colorRows(
            of surface: IOSurface,
            color: Color,
            columns: Range<Int>? = nil,
            rows: Range<Int>? = nil,
            keep: Bool = false,
        ) -> (count: Int, pixels: Data?) {
            guard surface.pixelFormat == kCVPixelFormatType_32BGRA else { return (0, nil) }
            let columns = (columns ?? 0 ..< surface.width).clamped(to: 0 ..< surface.width)
            let rows = (rows ?? 0 ..< surface.height).clamped(to: 0 ..< surface.height)
            guard surface.lock(options: .readOnly, seed: nil) == kIOReturnSuccess else { return (0, nil) }
            defer { surface.unlock(options: .readOnly, seed: nil) }
            let base = surface.baseAddress.assumingMemoryBound(to: UInt8.self)
            let pixels = keep ? Data(bytes: base, count: surface.bytesPerRow * surface.height) : nil
            var count = 0
            for y in rows {
                let row = base.advanced(by: y * surface.bytesPerRow)
                var hits = 0
                // Every fourth pixel: the color fills a box, not a stroke.
                for x in Swift.stride(from: columns.lowerBound, to: columns.upperBound, by: 4) {
                    let pixel = row.advanced(by: x * 4)
                    if color.matches(blue: pixel[0], green: pixel[1], red: pixel[2]) {
                        hits += 1
                        if hits == 4 {
                            break
                        }
                    }
                }
                if hits == 4 {
                    count += 1
                }
            }
            return (count, pixels)
        }

        /// A PNG of BGRA `pixels` read from `surface`.
        static func png(_ pixels: Data, like surface: IOSurface) -> Data? {
            guard let provider = CGDataProvider(data: pixels as CFData),
                  let image = CGImage(
                      width: surface.width, height: surface.height, bitsPerComponent: 8, bitsPerPixel: 32,
                      bytesPerRow: surface.bytesPerRow, space: CGColorSpace(name: CGColorSpace.displayP3)!,
                      bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue
                          | CGBitmapInfo.byteOrder32Little.rawValue),
                      provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent,
                  )
            else { return nil }
            return NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
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

        /// How many frames `CALM_SELFTEST_MOTION_FRAMES` keeps as pictures. Writing them slows
        /// the sampling down, so frame timing is read from a run without it.
        static let maxFramePictures = 240

        /// Samples `pane`'s presented frames every few milliseconds for `seconds`, the whole frame
        /// or only `cells`. Sampling only keeps each new frame's profile; the shifts are worked out
        /// afterwards, so the analysis never delays a sample.
        @MainActor
        static func run(on pane: TerminalSurfaceView, seconds: Double, cells: Cells? = nil, color: Color? = nil) async -> Report {
            var report = Report(cellHeight: pane.cellHeightPixelsForTesting)
            // Grid padding is left out: a few pixels either way don't matter to a profile.
            let (width, height) = (pane.cellWidthPixelsForTesting, report.cellHeight)
            let columns = cells.map { $0.columns.lowerBound * width ..< ($0.columns.upperBound + 1) * width }
            let rows = cells.map { $0.rows.lowerBound * height ..< ($0.rows.upperBound + 1) * height }
            let end = ContinuousClock.now + .seconds(seconds)
            let framesDirectory = ProcessInfo.processInfo.environment["CALM_SELFTEST_MOTION_FRAMES"]
                .flatMap { $0.isEmpty ? nil : $0 }
            var frames: [(time: ContinuousClock.Instant, profile: [Float])] = []
            while ContinuousClock.now < end {
                if let surface = pane.presentedFrameForTesting,
                   let profile = rowProfile(of: surface, columns: columns, rows: rows) {
                    report.samples += 1
                    if profile != frames.last?.profile {
                        frames.append((ContinuousClock.now, profile))
                        // With a frames directory, each of the first few frames is kept as a
                        // picture, to look at how something moves rather than count it.
                        if let framesDirectory, frames.count <= Self.maxFramePictures,
                           surface.lock(options: .readOnly, seed: nil) == kIOReturnSuccess {
                            // Copied under the lock: libghostty may draw the next frame into the
                            // same surface before a second read.
                            let pixels = Data(bytes: surface.baseAddress, count: surface.bytesPerRow * surface.height)
                            surface.unlock(options: .readOnly, seed: nil)
                            if let png = png(pixels, like: surface) {
                                let name = String(format: "frame-%03d.png", frames.count)
                                try? png.write(to: URL(filePath: "\(framesDirectory)/\(name)"))
                            }
                        }
                        if let color {
                            // With a dump, the first few frames showing the color too much are
                            // kept as pictures.
                            let dump = ProcessInfo.processInfo.environment["CALM_SELFTEST_MOTION_DUMP"]
                            let (seen, pixels) = colorRows(
                                of: surface, color: color, columns: columns, rows: rows,
                                keep: dump != nil && report.colorFramesOver < 4,
                            )
                            report.colorRows = max(report.colorRows ?? 0, seen)
                            // A couple of pixels of slack for anti-aliased edges.
                            if seen > height + 2 {
                                report.colorFramesOver += 1
                                if let start = frames.first?.time {
                                    report.colorOverAt.append(Int((ContinuousClock.now - start) / .milliseconds(1)))
                                }
                                if let dump, let pixels, let png = png(pixels, like: surface) {
                                    try? png.write(to: URL(filePath: "\(dump).over\(report.colorFramesOver).png"))
                                }
                            }
                        }
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

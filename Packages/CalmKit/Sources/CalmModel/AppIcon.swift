import Foundation

/// What Calm's Dock icon shows (UIUX.md → App icon): the still mark; the chase while an agent
/// works; the ring closed, its cursor cell sage, when work is done; the ring dimmed to grey, its
/// cursor cell red, when something failed.
public enum AppIconState: Sendable, Equatable {
    case idle
    case running
    case done
    case failed

    /// One state for the whole app. A failure outranks work in progress, which outranks finished
    /// work. *Needs you* has its own notification and leaves the icon as it is.
    public static func summarizing(_ states: some Sequence<SessionState>) -> AppIconState {
        var running = false
        var done = false
        for state in states {
            switch state {
            case .failed: return .failed
            case .working: running = true
            case .done: done = true
            case .idle, .needsYou: break
            }
        }
        return running ? .running : done ? .done : .idle
    }
}

/// One drawing of the icon: everything that moves, as numbers the renderer turns into cells.
public struct AppIconFrame: Sendable, Equatable {
    /// 0 at rest, 1 while working: the trail behind the cursor cell, and the ring stepping back.
    public var busy: Double
    /// Where the cursor cell is, in places around the ring. Every multiple of `placeCount` is its
    /// resting place, just past the ring's end.
    public var head: Double
    /// How far the icon has turned into *done* (0 to 1).
    public var done: Double
    /// How far the icon has turned into *failed* (0 to 1).
    public var failed: Double
    /// Seconds since the mark began to draw itself (the welcome page, `WelcomeMarkMotion`): the
    /// ring's cells appear in typing order, then the center, then the cursor. Infinity is the
    /// finished mark, which is what every other frame is.
    public var arrival: Double
    /// How much of the cursor cell shows (0 to 1) while the mark waits; the welcome page lets it
    /// breathe. 1 everywhere else.
    public var cursorLevel: Double

    public init(
        busy: Double, head: Double, done: Double, failed: Double,
        arrival: Double = .infinity, cursorLevel: Double = 1,
    ) {
        self.busy = busy
        self.head = head
        self.done = done
        self.failed = failed
        self.arrival = arrival
        self.cursorLevel = cursorLevel
    }

    public static let still = AppIconFrame(busy: 0, head: 0, done: 0, failed: 0)

    // MARK: Arrival

    /// The mark draws itself in this many seconds (`WelcomeMarkMotion.arrivalLength`).
    static let arrivalLength: TimeInterval = 2.15
    /// Each ring cell fades in over `ringFade`, one `ringStagger` after the one before.
    static let ringStagger: TimeInterval = 0.055
    static let ringFade: TimeInterval = 0.55
    static let centerStart: TimeInterval = 0.62
    static let centerFade: TimeInterval = 0.6
    /// The cursor appears on the ring's last cell, waits a moment, then takes the last step to its
    /// resting place slowly.
    static let cursorStart: TimeInterval = 0.95
    static let cursorFade: TimeInterval = 0.3
    static let stepStart: TimeInterval = 1.15
    static let stepLength: TimeInterval = 1

    private static func reveal(_ arrival: Double, start: TimeInterval, length: TimeInterval) -> Double {
        AppIconMotion.easeOut((arrival - start) / length)
    }

    /// How much of the center cell has appeared (1 unless the mark is still arriving).
    public var centerLevel: Double {
        Self.reveal(arrival, start: Self.centerStart, length: Self.centerFade)
    }

    /// How much of the cursor cell, and its glow, shows: its arrival times its breathing.
    public var cursorVisibility: Double {
        cursorLevel * Self.reveal(arrival, start: Self.cursorStart, length: Self.cursorFade)
    }

    /// The ring's places, counterclockwise (the way it types) from the cursor cell's resting
    /// place; at rest, place 1 is the ring's opening.
    public static let placeCount = 12

    /// How bright the trail is behind the cursor cell, from its own place back.
    static let trail: [Double] = [1, 0.55, 0.3, 0.12, 0]

    /// One place around the ring: how much of the ring cell shows there, and how much of the
    /// cursor (or its trail).
    public struct Place: Sendable, Equatable {
        public var ring: Double
        public var cursor: Double
    }

    /// The twelve places, in `placeCount` order.
    public var places: [Place] {
        let count = Double(Self.placeCount)
        return (0 ..< Self.placeCount).map { index in
            // How far behind the cursor this place is, 0 up to (not including) 12.
            let behind = (head - Double(index)).truncatingRemainder(dividingBy: count)
            let d = behind < 0 ? behind + count : behind
            var cursor: Double
            if d > count - 1 {
                // The next place, lighting up as the cursor arrives.
                cursor = d - (count - 1)
            } else {
                cursor = busy * Self.trailStrength(d)
                if d < 1 {
                    cursor = max(1 - d, cursor)
                }
            }
            // Behind the cursor the ring fills in; at its far end it gives way, which leaves the
            // opening just ahead of the cursor.
            var ring = 1.0
            if d < 1 {
                ring = d
            } else if d > count - 2 {
                ring = max(0, (count - 1) - d)
            }
            // Done closes the ring.
            if index == 1 {
                ring = max(ring, done)
            }
            if arrival.isFinite {
                // Arriving: the ring's ten cells (places 2 to 11) draw themselves in typing order;
                // the cursor's resting place and the opening stay empty.
                ring = index >= 2 ? ring * Self.reveal(arrival, start: Double(index - 2) * Self.ringStagger, length: Self.ringFade) : 0
            }
            return Place(ring: min(1, ring), cursor: min(1, cursor * cursorVisibility))
        }
    }

    /// Looks exactly like the still mark: nothing lit or turned, the cursor at its resting place
    /// (after a run that's a whole number of laps, not zero).
    public var isAtRest: Bool {
        busy == 0 && done == 0 && failed == 0 && arrival.isInfinite && cursorLevel == 1
            && head.truncatingRemainder(dividingBy: Double(Self.placeCount)) == 0
    }

    /// The frame to three decimals, so frames that look the same compare equal.
    public var rounded: AppIconFrame {
        func r(_ value: Double) -> Double {
            (value * 1000).rounded() / 1000
        }
        return AppIconFrame(
            busy: r(busy), head: r(head), done: r(done), failed: r(failed), arrival: r(arrival), cursorLevel: r(cursorLevel),
        )
    }

    static func trailStrength(_ d: Double) -> Double {
        let index = Int(d)
        guard index < trail.count - 1 else { return 0 }
        return trail[index] + (trail[index + 1] - trail[index]) * (d - Double(index))
    }
}

/// Moves the icon from state to state over time (UIUX.md → App icon): the chase starts at once;
/// when work stops, the cursor carries on to its resting place and takes the last step slowly
/// (the settle), then the icon turns into the new state. Pure: frames are a function of time.
public struct AppIconMotion: Sendable, Equatable {
    /// A lap of the ring in 1.5 s.
    public static let placesPerSecond = 8.0
    static let trailOn: TimeInterval = 0.3
    static let lastStep: TimeInterval = 0.45
    static let trailOff: TimeInterval = 0.8
    /// Into and out of *done* and *failed*.
    static let markChange: TimeInterval = 0.5

    public private(set) var state: AppIconState = .idle
    /// When the current run's position was zero; nil before the first run.
    private var runStart: TimeInterval?
    private var settle: Settle?
    private var busy = Ramp(value: 0)
    private var done = Ramp(value: 0)
    private var failed = Ramp(value: 0)

    public init() {}

    public mutating func show(_ newState: AppIconState, at time: TimeInterval) {
        guard newState != state else { return }
        let now = frame(at: time)
        if newState == .running {
            // Carry on from wherever the cursor is.
            runStart = time - now.head / Self.placesPerSecond
            settle = nil
            busy = Ramp(from: now.busy, to: 1, start: time, duration: Self.trailOn)
        }
        var changeAt = time
        if state == .running, newState != .running, let runStart {
            let position = Self.placesPerSecond * (time - runStart)
            let lap = Double(AppIconFrame.placeCount)
            let rest = (position / lap).rounded(.up) * lap
            // Keep stepping to the place before the resting one, then take the last step slowly.
            let lastStepAt = max(time, runStart + (rest - 1) / Self.placesPerSecond)
            let from = position >= rest - 1 ? now.head : rest - 1
            settle = Settle(at: lastStepAt, from: from, to: rest)
            busy = Ramp(from: now.busy, to: 0, start: lastStepAt, duration: Self.trailOff)
            changeAt = lastStepAt + Self.lastStep
        }
        done = Ramp(from: now.done, to: newState == .done ? 1 : 0, start: changeAt, duration: Self.markChange)
        failed = Ramp(from: now.failed, to: newState == .failed ? 1 : 0, start: changeAt, duration: Self.markChange)
        state = newState
    }

    /// `wholeSteps`: the chase jumps from place to place instead of easing between them, which
    /// halves the frames it draws (8 a second rather than 16); the Dock uses it, where the ease is
    /// too small to see and every frame goes to the Dock as a new picture. The settle keeps its ease.
    public func frame(at time: TimeInterval, wholeSteps: Bool = false) -> AppIconFrame {
        var head = 0.0
        if let runStart {
            if let settle, time >= settle.at {
                head = settle.from + (settle.to - settle.from) * Self.easeOut((time - settle.at) / Self.lastStep)
            } else {
                let position = Self.placesPerSecond * (time - runStart)
                head = wholeSteps ? position.rounded(.down) : Self.step(position)
            }
        }
        return AppIconFrame(busy: busy.value(at: time), head: head, done: done.value(at: time), failed: failed.value(at: time))
    }

    /// Nothing changes until the next state, so the icon can stop redrawing.
    public func isStill(at time: TimeInterval) -> Bool {
        guard state != .running else { return false }
        let settled = settle.map { time >= $0.at + max(Self.lastStep, Self.trailOff) } ?? true
        return settled && time >= busy.end && time >= done.end && time >= failed.end
    }

    /// The state without motion (Reduce Motion): running keeps its trail and dimmed ring, still.
    public static func stillFrame(for state: AppIconState) -> AppIconFrame {
        switch state {
        case .idle: .still
        case .running: AppIconFrame(busy: 1, head: 0, done: 0, failed: 0)
        case .done: AppIconFrame(busy: 0, head: 0, done: 1, failed: 0)
        case .failed: AppIconFrame(busy: 0, head: 0, done: 0, failed: 1)
        }
    }

    /// The cursor holds on a place, then steps to the next in the last 30% of its beat, like a
    /// terminal spinner: no half-lit cell lingers ahead of it.
    static func step(_ position: Double) -> Double {
        let whole = position.rounded(.down)
        return whole + easeInOut((position - whole - 0.7) / 0.3)
    }

    static func easeOut(_ value: Double) -> Double {
        let x = min(1, max(0, value))
        return 1 - pow(1 - x, 3)
    }

    static func easeInOut(_ value: Double) -> Double {
        let x = min(1, max(0, value))
        return x < 0.5 ? 4 * x * x * x : 1 - pow(-2 * x + 2, 3) / 2
    }

    /// The last step of a run: from where, to which resting place, starting when.
    private struct Settle: Sendable, Equatable {
        var at: TimeInterval
        var from: Double
        var to: Double
    }

    /// A value easing from one number to another over a stretch of time.
    private struct Ramp: Sendable, Equatable {
        var from: Double
        var to: Double
        var start: TimeInterval
        var duration: TimeInterval

        init(value: Double) {
            self.init(from: value, to: value, start: 0, duration: 0)
        }

        init(from: Double, to: Double, start: TimeInterval, duration: TimeInterval) {
            self.from = from
            self.to = to
            self.start = start
            self.duration = duration
        }

        var end: TimeInterval {
            start + duration
        }

        func value(at time: TimeInterval) -> Double {
            guard duration > 0, time < end else { return to }
            guard time > start else { return from }
            return from + (to - from) * AppIconMotion.easeInOut((time - start) / duration)
        }
    }
}

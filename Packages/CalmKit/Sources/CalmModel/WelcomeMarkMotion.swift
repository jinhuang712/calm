import Foundation

/// How Calm's mark moves on the welcome page (UIUX.md → Welcome page). It arrives once: the ring
/// draws itself in typing order, the center follows, and the cursor appears on the ring's last
/// cell and takes the last step to its resting place slowly, settling once, as it does when an
/// agent stops working. Then it waits, the cursor breathing slowly, the way a cursor waits for the
/// next character. Nothing here means "working": the chase is the Dock's word for that, so a click
/// is the only thing that runs it here, for one lap. Pure: frames are a function of time.
public enum WelcomeMarkMotion {
    /// The arrival takes this long; the breathing starts as it ends.
    public static let arrivalLength = AppIconFrame.arrivalLength

    /// One breath of the cursor, and how far it dips (from 1 down to `1 - dip`).
    static let breathLength: TimeInterval = 3.6
    static let dip = 0.58
    /// It breathes this many times, then rests as the still mark: a page left alone shouldn't go
    /// on redrawing for hours.
    public static let breaths = 8
    /// When, counted from the end of the arrival, the mark has come to rest.
    public static let restsAfter = arrivalLength + Double(breaths) * breathLength

    /// A lap of the ring, then the trail fades: the click's whole run.
    public static let lapLength = Double(AppIconFrame.placeCount) / AppIconMotion.placesPerSecond + AppIconMotion.trailOff
    /// After a lap the cursor breathes again from full, and rests after the same number of breaths.
    public static let restsAfterLap = lapLength + Double(breaths) * breathLength

    /// The mark `elapsed` seconds after it first showed. Reduce Motion shows `AppIconFrame.still`.
    public static func frame(at elapsed: TimeInterval) -> AppIconFrame {
        let time = max(0, elapsed)
        if time >= restsAfter {
            return .still
        }
        if time < arrivalLength {
            // The cursor waits on place 11, the ring's last cell, until it takes the last step.
            let step = AppIconMotion.easeOut((time - AppIconFrame.stepStart) / AppIconFrame.stepLength)
            return AppIconFrame(busy: 0, head: 11 + step, done: 0, failed: 0, arrival: time)
        }
        let phase = (time - arrivalLength) / breathLength
        let level = 1 - dip * (1 - cos(2 * .pi * phase)) / 2
        return AppIconFrame(busy: 0, head: 0, done: 0, failed: 0, cursorLevel: level)
    }

    /// One lap of the chase, `elapsed` seconds after a click, ending in the settle.
    public static func lapFrame(at elapsed: TimeInterval) -> AppIconFrame {
        var motion = AppIconMotion()
        motion.show(.running, at: 0)
        motion.show(.idle, at: Double(AppIconFrame.placeCount) / AppIconMotion.placesPerSecond)
        return motion.frame(at: max(0, elapsed))
    }
}

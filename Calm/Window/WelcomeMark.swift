import AppKit
import CalmModel
import Observation
import SwiftUI

/// Calm's mark on the welcome page (UIUX.md → Welcome page). It is drawn by the Dock icon's own
/// view, so it is always the real icon, in the theme's light or dark version, and it moves as
/// `WelcomeMarkMotion` says: it arrives once, waits with a breathing cursor for a while, then
/// rests. A click runs one lap of the chase, a small easter egg like the project marks'. Reduce
/// Motion draws the finished mark and nothing else.
struct WelcomeMark: View {
    let clock: WelcomeMarkClock
    let isDark: Bool
    /// The tile's side at the standard interface size.
    var side: CGFloat = 60

    /// The icon's tile fills 824 of the 1024 points its view draws on.
    private var canvas: CGFloat {
        side.scaled * 1024 / 824
    }

    var body: some View {
        let reduced = Motion.isReduced
        // Reduce Motion asks for one frame; otherwise frames come until the mark has come to rest.
        TimelineView(WelcomeMarkSchedule(end: reduced ? .now : clock.restsAt)) { timeline in
            MarkDrawing(frame: reduced ? .still : clock.frame(at: timeline.date), dark: isDark)
                .frame(width: canvas, height: canvas)
        }
        // The layout box is the tile; the drawing's margin overflows it.
        .frame(width: side.scaled, height: side.scaled)
        .contentShape(Rectangle())
        .onTapGesture {
            if !reduced {
                clock.runLap()
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Calm")
        .accessibilityAddTraits(.isImage)
    }
}

/// When the mark first showed and when it was last clicked. The page owns it, so the mark carries
/// on where it was if the page rearranges itself while it plays.
@MainActor
@Observable
final class WelcomeMarkClock {
    let shownAt = Date.now
    private(set) var lapAt: Date?

    /// When the mark has come to rest: a while after the arrival, or after the last click's lap.
    var restsAt: Date {
        if let lapAt {
            return lapAt.addingTimeInterval(WelcomeMarkMotion.restsAfterLap)
        }
        return shownAt.addingTimeInterval(WelcomeMarkMotion.restsAfter)
    }

    /// One lap of the chase, once the arrival is over and the previous lap has finished.
    func runLap(now: Date = .now) {
        guard now.timeIntervalSince(shownAt) >= WelcomeMarkMotion.arrivalLength else { return }
        if let lapAt, now.timeIntervalSince(lapAt) < WelcomeMarkMotion.lapLength {
            return
        }
        lapAt = now
    }

    func frame(at date: Date) -> AppIconFrame {
        #if DEBUG
            // Self-tests freeze the mark at a chosen second, so snapshots show the same frame.
            if let frozen = Self.frozenTime {
                return WelcomeMarkMotion.frame(at: frozen)
            }
        #endif
        guard let lapAt else { return WelcomeMarkMotion.frame(at: date.timeIntervalSince(shownAt)) }
        let elapsed = date.timeIntervalSince(lapAt)
        if elapsed < WelcomeMarkMotion.lapLength {
            return WelcomeMarkMotion.lapFrame(at: elapsed)
        }
        // After the lap the cursor goes on breathing, starting again from full.
        return WelcomeMarkMotion.frame(at: WelcomeMarkMotion.arrivalLength + elapsed - WelcomeMarkMotion.lapLength)
    }

    #if DEBUG
        /// `CALM_WELCOME_MARK_AT=<seconds>`: the frame the mark is frozen at.
        static let frozenTime: TimeInterval? = ProcessInfo.processInfo.environment["CALM_WELCOME_MARK_AT"].flatMap(TimeInterval.init)
    #endif
}

/// Thirty frames a second (the rate Calm's marks use) until `end`, then nothing: a page left alone
/// stops redrawing. The first frame always comes.
private struct WelcomeMarkSchedule: TimelineSchedule {
    let end: Date

    func entries(from start: Date, mode _: TimelineScheduleMode) -> some Sequence<Date> {
        let end = end
        return sequence(state: (date: start, isFirst: true)) { state -> Date? in
            if state.isFirst {
                state.isFirst = false
                return state.date
            }
            state.date = state.date.addingTimeInterval(1.0 / 30)
            return state.date <= end ? state.date : nil
        }
    }
}

/// One frame of the icon, drawn by the Dock icon's view.
private struct MarkDrawing: NSViewRepresentable {
    let frame: AppIconFrame
    let dark: Bool

    func makeNSView(context _: Context) -> DockIconView {
        let view = DockIconView()
        view.iconFrame = frame.rounded
        view.dark = dark
        return view
    }

    func updateNSView(_ view: DockIconView, context _: Context) {
        let rounded = frame.rounded
        // Most ticks change nothing (the mark waits between breaths): redraw only what moved.
        guard view.iconFrame != rounded || view.dark != dark else { return }
        view.iconFrame = rounded
        view.dark = dark
        view.needsDisplay = true
    }
}

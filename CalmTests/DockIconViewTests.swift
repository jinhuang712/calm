import AppKit
@testable import Calm
import CalmModel
import Testing

@MainActor
struct DockIconViewTests {
    private static let frames = [
        AppIconFrame.still,
        AppIconFrame(busy: 1, head: 3, done: 0, failed: 0),
        AppIconFrame(busy: 1, head: 8.6, done: 0, failed: 0),
        AppIconFrame(busy: 0.4, head: 11.5, done: 0, failed: 0),
        AppIconMotion.stillFrame(for: .done),
        AppIconMotion.stillFrame(for: .failed),
    ]

    /// Draws the view the way `NSDockTile.display` does, into a bitmap of the screen's scale.
    private func pixels(_ view: DockIconView) throws -> [UInt8] {
        let rep = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: rep)
        let data = try #require(rep.bitmapData)
        return Array(UnsafeBufferPointer(start: data, count: rep.bytesPerRow * rep.pixelsHigh))
    }

    @Test func `the cached tile draws the same icon as drawing it all each frame`() throws {
        for dark in [true, false] {
            for frame in Self.frames {
                let view = DockIconView(frame: NSRect(x: 0, y: 0, width: 128, height: 128))
                view.dark = dark
                view.iconFrame = frame
                view.cachesStillParts = false
                let whole = try pixels(view)
                view.cachesStillParts = true
                _ = try pixels(view) // makes the cache
                let cached = try pixels(view)
                #expect(whole.count == cached.count)
                let worst = zip(whole, cached).map { abs(Int($0) - Int($1)) }.max() ?? 0
                #expect(worst <= 1, "dark \(dark), \(frame): a channel differs by \(worst)")
            }
        }
    }

    @Test func `each of the chase's twelve pictures is drawn once and looks as drawn whole`() throws {
        for dark in [true, false] {
            let view = DockIconView(frame: NSRect(x: 0, y: 0, width: 128, height: 128))
            view.dark = dark
            for head in 12 ..< 36 {
                let frame = AppIconFrame(busy: 1, head: Double(head), done: 0, failed: 0)
                view.iconFrame = frame
                view.cachesStillParts = false
                let whole = try pixels(view)
                view.cachesStillParts = true
                let cached = try pixels(view)
                let worst = zip(whole, cached).map { abs(Int($0) - Int($1)) }.max() ?? 0
                #expect(worst <= 1, "dark \(dark), head \(head): a channel differs by \(worst)")
            }
            // Two laps, one picture per place.
            #expect(view.chasePicturesForTesting == 12)
            // The settle eases between places: drawn as it comes, nothing kept.
            view.iconFrame = AppIconFrame(busy: 0.4, head: 11.5, done: 0, failed: 0)
            _ = try pixels(view)
            #expect(view.chasePicturesForTesting == 12)
            view.releaseChasePictures()
            #expect(view.chasePicturesForTesting == 0)
        }
    }
}

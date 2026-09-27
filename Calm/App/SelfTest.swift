#if DEBUG
    import AppKit

    /// Debug-only hooks for automated self-testing without Screen Recording permission.
    ///
    /// - `CALM_SNAPSHOT=/path/shot.png` saves the key window to a PNG once the UI settles.
    /// - `CALM_SNAPSHOT_DELAY=2.5` seconds to wait before the snapshot (default 1.5).
    /// - `CALM_SNAPSHOT_QUIT=1` quits after writing the snapshot.
    @MainActor
    enum SelfTest {
        static func scheduleIfRequested() {
            let env = ProcessInfo.processInfo.environment
            guard let path = env["CALM_SNAPSHOT"], !path.isEmpty else { return }
            let delay = env["CALM_SNAPSHOT_DELAY"].flatMap(Double.init) ?? 1.5
            let quit = env["CALM_SNAPSHOT_QUIT"] == "1"

            Task { @MainActor in
                try? await Task.sleep(for: .seconds(delay))
                let written = snapshotKeyWindow(to: URL(fileURLWithPath: path))
                FileHandle.standardError.write(Data("calm-selftest: snapshot \(written ? "written" : "failed") \(path)\n".utf8))
                if quit {
                    NSApp.terminate(nil)
                }
            }
        }

        /// Renders the whole window frame (title bar included) through AppKit's cache.
        static func snapshotKeyWindow(to url: URL) -> Bool {
            guard let window = NSApp.keyWindow ?? NSApp.windows.first(where: \.isVisible),
                  let frameView = window.contentView?.superview
            else { return false }
            let bounds = frameView.bounds
            guard let rep = frameView.bitmapImageRepForCachingDisplay(in: bounds) else { return false }
            frameView.cacheDisplay(in: bounds, to: rep)
            guard let png = rep.representation(using: .png, properties: [:]) else { return false }
            return (try? png.write(to: url)) != nil
        }
    }
#endif

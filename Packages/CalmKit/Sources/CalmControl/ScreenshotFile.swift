import Foundation

/// Where `calm screenshot` writes, and a check of what came back (CLI.md).
public enum ScreenshotFile {
    /// `calm-<yyyyMMdd-HHmmss>.png` in `directory` when the caller names no file, so two shots
    /// never overwrite each other. A relative name starts from `directory`; `~` is the home folder.
    public static func path(
        argument: String?,
        directory: String,
        now: Date = .now,
        home: String = NSHomeDirectory(),
    ) -> String {
        guard let argument, !argument.isEmpty else {
            return (directory as NSString).appendingPathComponent("calm-\(stamp(now)).png")
        }
        if argument == "~" || argument.hasPrefix("~/") {
            return (home as NSString).appendingPathComponent(String(argument.dropFirst(argument == "~" ? 1 : 2)))
        }
        return argument.hasPrefix("/") ? argument : (directory as NSString).appendingPathComponent(argument)
    }

    /// The reply is trusted only as far as its first bytes: a Calm that answers with something else
    /// must not leave a broken `.png` behind.
    public static func png(fromBase64 text: String?) -> Data? {
        guard let text, let data = Data(base64Encoded: text), data.starts(with: [0x89, 0x50, 0x4E, 0x47]) else { return nil }
        return data
    }

    private static func stamp(_ date: Date) -> String {
        let parts = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        return String(
            format: "%04d%02d%02d-%02d%02d%02d",
            parts.year ?? 0, parts.month ?? 0, parts.day ?? 0, parts.hour ?? 0, parts.minute ?? 0, parts.second ?? 0,
        )
    }
}

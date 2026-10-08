import Foundation

/// Path helpers shared by the model. Pure string operations: no file system access.
public enum WorkspacePath {
    public static func standardize(_ path: String) -> String {
        var result = (path as NSString).expandingTildeInPath
        result = (result as NSString).standardizingPath
        while result.count > 1, result.hasSuffix("/") {
            result.removeLast()
        }
        return result
    }

    /// A folder with the home folder written as "~": "~/dev/calm", "/opt/tools".
    public static func abbreviated(_ path: String, home: String = NSHomeDirectory()) -> String {
        let path = standardize(path)
        let home = standardize(home)
        guard home != "/", isInside(path, folder: home) else { return path }
        return "~" + path.dropFirst(home.count)
    }

    public static func isInside(_ directory: String, folder: String) -> Bool {
        directory == folder || directory.hasPrefix(folder == "/" ? "/" : folder + "/")
    }

    public static func displayName(for path: String) -> String {
        let standardized = standardize(path)
        if standardized == standardize("~") {
            return "~"
        }
        let name = (standardized as NSString).lastPathComponent
        return name.isEmpty ? standardized : name
    }
}

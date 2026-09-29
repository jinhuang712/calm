import Foundation

public extension Project {
    /// Where a folder group's folder lives, for the line under its name so two groups with the
    /// same name can be told apart: the folder's parent with the home folder as "~" ("~/dev").
    /// Nil for the home folder itself (it has no useful parent), and for a project or the
    /// scratch group, whose folder isn't what names them.
    func location(home: String = NSHomeDirectory()) -> String? {
        guard kind == .directory, path != WorkspacePath.standardize(home) else { return nil }
        return WorkspacePath.abbreviated((path as NSString).deletingLastPathComponent, home: home)
    }
}

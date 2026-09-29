import Foundation

/// Finding the projects a user made by what they type into the welcome page's search
/// (FEATURES.md → F2): every word must be in the project's name or its folder, as the page shows
/// them, ignoring case and accents. What matches is what's marked, so a word that only fits the
/// part of a path the page abbreviates ("/Users/me" for "~") doesn't match.
public enum ProjectSearch {
    private static let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]

    /// The words of a query.
    public static func terms(in query: String) -> [String] {
        query.split(whereSeparator: \.isWhitespace).map(String.init)
    }

    /// The folder as the page shows it: "~/dev/apps/calm".
    public static func shownPath(of project: Project, home: String = NSHomeDirectory()) -> String {
        WorkspacePath.abbreviated(project.path, home: home)
    }

    public static func matches(_ project: Project, terms: [String], home: String = NSHomeDirectory()) -> Bool {
        let path = shownPath(of: project, home: home)
        return terms.allSatisfy { term in
            project.name.range(of: term, options: options) != nil || path.range(of: term, options: options) != nil
        }
    }

    /// Where the words fall in `text`, in order and without overlap, for marking them.
    public static func ranges(of terms: [String], in text: String) -> [Range<String.Index>] {
        var found: [Range<String.Index>] = []
        for term in terms {
            var from = text.startIndex
            while from < text.endIndex, let range = text.range(of: term, options: options, range: from ..< text.endIndex) {
                found.append(range)
                from = range.upperBound
            }
        }
        var merged: [Range<String.Index>] = []
        for range in found.sorted(by: { $0.lowerBound < $1.lowerBound }) {
            if let last = merged.last, range.lowerBound <= last.upperBound {
                merged[merged.count - 1] = last.lowerBound ..< max(last.upperBound, range.upperBound)
            } else {
                merged.append(range)
            }
        }
        return merged
    }
}

public extension Workspace {
    /// The projects the user made that fit `query`, in the sidebar's order; all of them for an
    /// empty query.
    func madeProjects(matching query: String, home: String = NSHomeDirectory()) -> [Project] {
        let terms = ProjectSearch.terms(in: query)
        guard !terms.isEmpty else { return madeProjects }
        return madeProjects.filter { ProjectSearch.matches($0, terms: terms, home: home) }
    }
}

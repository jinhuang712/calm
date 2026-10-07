import CalmAgents
import CalmModel
import Foundation
import ImageIO

/// Finds the image behind an agent's tag for a pasted image (`[Image #4]`, FEATURES.md → F8)
/// through the agent's adapter (`PastedImageResolving`): the core only asks.
@MainActor
enum PastedImageLookup {
    /// Each agent's tag, compiled once; an agent without one has no entry.
    private static var patterns: [AgentKind: NSRegularExpression] = [:]

    static func pattern(for kind: AgentKind) -> NSRegularExpression? {
        if let pattern = patterns[kind] {
            return pattern
        }
        guard let resolver = Agents.pastedImageResolver(for: kind),
              let pattern = try? NSRegularExpression(pattern: resolver.pastedImagePattern)
        else { return nil }
        patterns[kind] = pattern
        return pattern
    }

    /// The image behind tag `number` in `session`, while an agent that has such tags runs there.
    static func image(
        _ number: Int,
        in session: Session,
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        environment: [String: String] = ProcessInfo.processInfo.environment,
    ) -> URL? {
        guard let agent = session.agent, let resolver = Agents.pastedImageResolver(for: agent.kind) else { return nil }
        return resolver.pastedImage(PastedImageQuery(
            number: number, pane: session.id, processID: agent.processID, agentSessionID: agent.agentSessionID,
            home: home, environment: environment,
        ))
    }

    /// `1999 × 1254`, read from the file's header without decoding it.
    static func pixelSize(of url: URL) -> String? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int
        else { return nil }
        return "\(width) × \(height)"
    }
}

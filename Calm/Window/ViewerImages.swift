import Foundation
import UniformTypeIdentifiers
import WebKit

/// Pictures in a viewed Markdown file (`![…](docs/pipeline.png)`). Calm's page loads from the app
/// bundle with read access to its own folder only, so a path relative to the file found nothing.
/// The page asks for each local picture as `calm-image://file/<absolute path>` instead, and this
/// answers for pictures only: the page's script can never read a neighbour such as `.env`.
@MainActor
final class ViewerImages: NSObject, WKURLSchemeHandler {
    nonisolated static let scheme = "calm-image"

    /// Tasks WebKit stopped while their file was read; answering one raises an exception.
    private var stopped: Set<ObjectIdentifier> = []

    /// The picture file `url` names, or nil when it names anything else.
    nonisolated static func picture(at url: URL) -> (path: String, mimeType: String)? {
        guard url.scheme == scheme else { return nil }
        let path = url.path(percentEncoded: false)
        guard path.hasPrefix("/"),
              let type = UTType(filenameExtension: (path as NSString).pathExtension),
              type.conforms(to: .image),
              let mimeType = type.preferredMIMEType
        else { return nil }
        return ((path as NSString).standardizingPath, mimeType)
    }

    func webView(_: WKWebView, start task: any WKURLSchemeTask) {
        guard let url = task.request.url, let picture = Self.picture(at: url) else {
            task.didFailWithError(URLError(.unsupportedURL))
            return
        }
        let id = ObjectIdentifier(task)
        // `WKURLSchemeTask` isn't Sendable; it's only touched again here, on the main actor.
        nonisolated(unsafe) let task = task
        Task { [weak self] in
            let data = await Task.detached(priority: .userInitiated) {
                try? Data(contentsOf: URL(filePath: picture.path), options: .mappedIfSafe)
            }.value
            guard let self, stopped.remove(id) == nil else { return }
            guard let data else {
                task.didFailWithError(URLError(.fileDoesNotExist))
                return
            }
            task.didReceive(URLResponse(
                url: url, mimeType: picture.mimeType, expectedContentLength: data.count, textEncodingName: nil,
            ))
            task.didReceive(data)
            task.didFinish()
        }
    }

    func webView(_: WKWebView, stop task: any WKURLSchemeTask) {
        stopped.insert(ObjectIdentifier(task))
    }
}

import AppKit
import GhosttyKit
import UniformTypeIdentifiers

/// libghostty's clipboard callbacks.
///
/// Rules from the engine: a read that returns `STARTED` must be answered by exactly
/// one complete or deny call with its `state`; every pointer handed to us is only
/// valid for the duration of the callback.
@MainActor
enum TerminalClipboard {
    static let selectionPasteboard = NSPasteboard(name: NSPasteboard.Name("com.jinhuang.calm.selection"))

    static func pasteboard(_ location: ghostty_clipboard_e) -> NSPasteboard? {
        switch location {
        case GHOSTTY_CLIPBOARD_STANDARD: .general
        case GHOSTTY_CLIPBOARD_SELECTION: selectionPasteboard
        default: nil // macOS has no primary selection.
        }
    }

    // MARK: Read (paste, OSC 52 read)

    static func read(
        surfaceUserdata: UnsafeMutableRawPointer?,
        location: ghostty_clipboard_e,
        state: UnsafeMutableRawPointer?,
        mimes: UnsafePointer<UnsafePointer<CChar>?>?,
        mimeCount: Int,
        list: Bool,
    ) -> ghostty_clipboard_read_result_e {
        guard let view = TerminalSurfaceView.from(surfaceUserdata), let surface = view.surface,
              let pasteboard = pasteboard(location)
        else { return GHOSTTY_CLIPBOARD_READ_UNSUPPORTED }

        var requested: [String] = []
        for index in 0 ..< mimeCount {
            if let mime = mimes?[index] {
                let value = String(cString: mime)
                if !requested.contains(value) {
                    requested.append(value)
                }
            }
        }

        let contents = requested.compactMap { mime in data(forMime: mime, from: pasteboard).map { (mime, $0) } }
        let available = list ? availableMimes(in: pasteboard) : []
        if contents.isEmpty, !list {
            return GHOSTTY_CLIPBOARD_READ_UNAVAILABLE
        }

        complete(surface: surface, state: state, contents: contents, available: available, confirmed: false, remember: false)
        return GHOSTTY_CLIPBOARD_READ_STARTED
    }

    // MARK: Confirmation (unsafe paste, OSC 52)

    static func confirmRead(
        surfaceUserdata: UnsafeMutableRawPointer?,
        confirm: UnsafePointer<ghostty_clipboard_confirm_s>?,
        state: UnsafeMutableRawPointer?,
        request: ghostty_clipboard_request_e,
    ) {
        guard let view = TerminalSurfaceView.from(surfaceUserdata), let surface = view.surface, let confirm else { return }

        // Copy everything now; the confirm struct is borrowed.
        var contents: [(String, Data)] = []
        for index in 0 ..< confirm.pointee.contents_len {
            let item = confirm.pointee.contents[index]
            guard let mime = item.mime else { continue }
            let data = item.data.map { Data(bytes: $0, count: item.len) } ?? Data()
            contents.append((String(cString: mime), data))
        }
        var available: [String] = []
        for index in 0 ..< confirm.pointee.available_len {
            if let mime = confirm.pointee.available[index] {
                available.append(String(cString: mime))
            }
        }

        let preview = contents.first { $0.0 == "text/plain" }.flatMap { String(data: $0.1, encoding: .utf8) } ?? ""
        let alert = NSAlert()
        switch request {
        case GHOSTTY_CLIPBOARD_REQUEST_PASTE:
            alert.messageText = "Paste this text?"
            alert.informativeText = "It looks like it could run commands.\n\n" + String(preview.prefix(600))
        case GHOSTTY_CLIPBOARD_REQUEST_OSC_52_READ, GHOSTTY_CLIPBOARD_REQUEST_KITTY_READ:
            alert.messageText = "Allow this program to read your clipboard?"
        case GHOSTTY_CLIPBOARD_REQUEST_OSC_52_WRITE, GHOSTTY_CLIPBOARD_REQUEST_KITTY_WRITE:
            alert.messageText = "Allow this program to change your clipboard?"
            alert.informativeText = String(preview.prefix(600))
        default:
            ghostty_surface_deny_clipboard_request(surface, state)
            return
        }
        alert.addButton(withTitle: "Allow")
        alert.addButton(withTitle: "Cancel")

        // Answer after this callback returns, so the modal alert doesn't run inside libghostty.
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                guard let surface = view.surface else { return }
                if alert.runModal() == .alertFirstButtonReturn {
                    complete(surface: surface, state: state, contents: contents, available: available, confirmed: true, remember: false)
                } else {
                    ghostty_surface_deny_clipboard_request(surface, state)
                }
            }
        }
    }

    // MARK: Write (copy, OSC 52 write)

    static func write(
        surfaceUserdata _: UnsafeMutableRawPointer?,
        location: ghostty_clipboard_e,
        contents: UnsafePointer<ghostty_clipboard_content_s>?,
        count: Int,
        confirm: Bool,
    ) {
        guard let pasteboard = pasteboard(location), let contents else { return }
        var items: [(NSPasteboard.PasteboardType, Data)] = []
        for index in 0 ..< count {
            let item = contents[index]
            guard let mime = item.mime, let pointer = item.data else { continue }
            let data = Data(bytes: pointer, count: item.len)
            items.append((pasteboardType(forMime: String(cString: mime)), data))
        }
        guard !items.isEmpty else { return }

        let apply = {
            pasteboard.declareTypes(items.map(\.0), owner: nil)
            for (type, data) in items {
                pasteboard.setData(data, forType: type)
            }
        }
        guard confirm else {
            apply()
            return
        }
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = "Allow this program to change your clipboard?"
            let text = items.first { $0.0 == .string }.flatMap { String(data: $0.1, encoding: .utf8) } ?? ""
            alert.informativeText = String(text.prefix(600))
            alert.addButton(withTitle: "Allow")
            alert.addButton(withTitle: "Cancel")
            if alert.runModal() == .alertFirstButtonReturn {
                apply()
            }
        }
    }

    // MARK: Helpers

    private static func complete(
        surface: ghostty_surface_t, state: UnsafeMutableRawPointer?,
        contents: [(String, Data)], available: [String], confirmed: Bool, remember: Bool,
    ) {
        // Build C buffers that stay alive for the duration of the call.
        let mimeStrings = contents.map { strdup($0.0) }
        let dataBuffers = contents.map { item -> UnsafeMutablePointer<CChar> in
            let buffer = UnsafeMutablePointer<CChar>.allocate(capacity: max(item.1.count, 1))
            item.1.withUnsafeBytes { raw in
                if let base = raw.baseAddress {
                    buffer.initialize(from: base.assumingMemoryBound(to: CChar.self), count: item.1.count)
                }
            }
            return buffer
        }
        let availableStrings = available.map { strdup($0) }
        defer {
            mimeStrings.forEach { free($0) }
            dataBuffers.forEach { $0.deallocate() }
            availableStrings.forEach { free($0) }
        }

        var cContents = contents.indices.map { index in
            ghostty_clipboard_content_s(
                mime: mimeStrings[index].map { UnsafePointer($0) },
                data: UnsafePointer(dataBuffers[index]),
                len: contents[index].1.count,
            )
        }
        var cAvailable: [UnsafePointer<CChar>?] = availableStrings.map { $0.map { UnsafePointer($0) } }
        cContents.withUnsafeMutableBufferPointer { contentsBuffer in
            cAvailable.withUnsafeMutableBufferPointer { availableBuffer in
                var payload = ghostty_clipboard_complete_s(
                    contents: contentsBuffer.baseAddress, contents_len: contentsBuffer.count,
                    available: availableBuffer.baseAddress, available_len: availableBuffer.count,
                    confirmed: confirmed, remember: remember,
                )
                ghostty_surface_complete_clipboard_request(surface, &payload, state)
            }
        }
    }

    /// Text is served as the pasteboard's string; dropped file URLs become shell-escaped paths.
    private static func data(forMime mime: String, from pasteboard: NSPasteboard) -> Data? {
        switch mime {
        case "text/plain":
            return plainText(from: pasteboard).map { Data($0.utf8) }
        case "text/uri-list":
            let urls = pasteboard.readObjects(forClasses: [NSURL.self]) as? [URL] ?? []
            return urls.isEmpty ? nil : Data(urls.map(\.absoluteString).joined(separator: "\r\n").utf8)
        default:
            guard let type = UTType(mimeType: mime) else { return nil }
            return pasteboard.data(forType: NSPasteboard.PasteboardType(type.identifier))
        }
    }

    static func plainText(from pasteboard: NSPasteboard) -> String? {
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL],
           !urls.isEmpty {
            return urls.map { shellEscaped($0.path) }.joined(separator: " ")
        }
        return pasteboard.string(forType: .string)
    }

    static func shellEscaped(_ path: String) -> String {
        let special = Set(" \\()[]{}<>'\"`$&*?!;|#~=%^")
        return String(path.flatMap { special.contains($0) ? ["\\", $0] : [$0] })
    }

    private static func availableMimes(in pasteboard: NSPasteboard) -> [String] {
        (pasteboard.types ?? []).compactMap { type in
            if type == .string {
                return "text/plain"
            }
            return UTType(type.rawValue)?.preferredMIMEType
        }
    }

    private static func pasteboardType(forMime mime: String) -> NSPasteboard.PasteboardType {
        if mime == "text/plain" {
            return .string
        }
        if let type = UTType(mimeType: mime) {
            return NSPasteboard.PasteboardType(type.identifier)
        }
        return NSPasteboard.PasteboardType(mime)
    }
}

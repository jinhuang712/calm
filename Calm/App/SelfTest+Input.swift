#if DEBUG
    import AppKit
    import GhosttyKit

    extension TerminalSurfaceView {
        /// ANSI virtual key codes for the characters the self-test types.
        private static let keyCodes: [Character: UInt16] = [
            "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7, "c": 8, "v": 9, "b": 11, "q": 12,
            "w": 13, "e": 14, "r": 15, "y": 16, "t": 17, "1": 18, "2": 19, "3": 20, "4": 21, "6": 22, "5": 23,
            "=": 24, "9": 25, "7": 26, "-": 27, "8": 28, "0": 29, "o": 31, "u": 32, "i": 34, "p": 35, "\r": 36,
            "l": 37, "j": 38, "k": 40, ";": 41, ",": 43, "/": 44, "n": 45, "m": 46, ".": 47, " ": 49,
        ]

        /// Characters typed with Shift on a US layout, and the key they share.
        private static let shifted: [Character: Character] = [
            "!": "1", "@": "2", "#": "3", "$": "4", "%": "5", "^": "6", "&": "7", "*": "8", "(": "9", ")": "0",
            "_": "-", "+": "=", ":": ";", "<": ",", ">": ".", "?": "/",
        ]

        /// Sends each character as a real key-down/key-up pair through the keyboard path
        /// (performKeyEquivalent is skipped: these keys use at most Shift).
        func pressKeysForTesting(_ text: String) -> Int {
            guard let window else { return 0 }
            var sent = 0
            for character in text {
                let base = Self.shifted[character] ?? Character(character.lowercased())
                guard let code = Self.keyCodes[base] else { continue }
                let flags: NSEvent.ModifierFlags = base == character ? [] : .shift
                for type in [NSEvent.EventType.keyDown, .keyUp] {
                    guard let event = NSEvent.keyEvent(
                        with: type, location: .zero, modifierFlags: flags, timestamp: ProcessInfo.processInfo.systemUptime,
                        windowNumber: window.windowNumber, context: nil, characters: String(character),
                        charactersIgnoringModifiers: String(base), isARepeat: false, keyCode: code,
                    ) else { continue }
                    if type == .keyDown {
                        keyDown(with: event)
                    } else {
                        keyUp(with: event)
                    }
                }
                sent += 1
            }
            return sent
        }

        /// Columns × rows as libghostty sees them.
        var gridSizeForTesting: String {
            guard let surface else { return "none" }
            let size = ghostty_surface_size(surface)
            return "\(size.columns)x\(size.rows)"
        }

        /// Drags across the first rows of the pane, copies the selection, and returns the pasteboard text.
        func dragAndCopyFirstRowForTesting() -> String? {
            guard let window else { return nil }
            let top = frame.height - 8
            let start = convert(NSPoint(x: 4, y: top), to: nil)
            let end = convert(NSPoint(x: frame.width * 0.6, y: top - cellSize.height * 1.5), to: nil)
            let events: [(NSEvent.EventType, NSPoint)] = [(.leftMouseDown, start), (.leftMouseDragged, end), (.leftMouseUp, end)]
            for (type, point) in events {
                guard let event = NSEvent.mouseEvent(
                    with: type, location: point, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                    windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1,
                ) else { continue }
                switch type {
                case .leftMouseDown: mouseDown(with: event)
                case .leftMouseDragged: mouseDragged(with: event)
                default: mouseUp(with: event)
                }
            }
            // Don't clobber the user's clipboard: put back whatever was there.
            let pasteboard = NSPasteboard.general
            let saved = pasteboard.pasteboardItems?.map { item in
                item.types.reduce(into: [NSPasteboard.PasteboardType: Data]()) { $0[$1] = item.data(forType: $1) }
            } ?? []
            pasteboard.clearContents()
            perform("copy_to_clipboard")
            let copied = pasteboard.string(forType: .string)
            pasteboard.clearContents()
            pasteboard.writeObjects(saved.map { types in
                let item = NSPasteboardItem()
                for (type, data) in types {
                    item.setData(data, forType: type)
                }
                return item
            })
            return copied
        }
    }
#endif

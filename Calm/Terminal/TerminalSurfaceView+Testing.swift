#if DEBUG
    import AppKit
    import CalmModel
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

        /// One row's height in the frame's pixels.
        var cellHeightPixelsForTesting: Int {
            guard let surface else { return 0 }
            return Int(ghostty_surface_size(surface).cell_height_px)
        }

        /// One column's width in the frame's pixels.
        var cellWidthPixelsForTesting: Int {
            guard let surface else { return 0 }
            return Int(ghostty_surface_size(surface).cell_width_px)
        }

        /// The frame on screen: libghostty sets the layer's contents to each frame it presents.
        var presentedFrameForTesting: IOSurface? {
            layer?.contents as? IOSurface
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

    extension TerminalSurfaceView {
        /// Types text as if from the keyboard, then presses Return.
        func typeForTesting(_ text: String) {
            run(text)
        }
    }

    extension TerminalSurfaceView {
        /// ⌥-double-clicks the first cell showing `text`, through the real mouse path, and returns
        /// what was copied. The user's clipboard is put back afterwards.
        /// Rests the pointer, with ⌘ held, on the first cell of `text` on screen, as the mouse would.
        func hoverLinkForTesting(_ text: String) -> Bool {
            guard let surface else { return false }
            let grid = TextGrid(lines: viewportRows())
            for (row, cells) in grid.cells.enumerated() {
                let line = cells.compactMap(\.self).map(String.init).joined()
                guard let range = line.range(of: text) else { continue }
                let column = line[..<range.lowerBound].reduce(0) { $0 + CellWidth.of($1) } + 1
                guard let cell = rect(row: row, columns: column ..< column + 1) else { return false }
                links.pointer = NSPoint(x: cell.midX, y: cell.midY)
                ghostty_surface_mouse_pos(surface, cell.midX, bounds.height - cell.midY, TerminalInput.mods(.command))
                return true
            }
            return false
        }

        /// The window point at the middle of the first cell showing `text`.
        private func windowPointForTesting(of text: String) -> NSPoint? {
            let grid = TextGrid(lines: viewportRows())
            for (row, cells) in grid.cells.enumerated() {
                let line = cells.compactMap(\.self).map(String.init).joined()
                guard let range = line.range(of: text) else { continue }
                let column = line[..<range.lowerBound].reduce(0) { $0 + CellWidth.of($1) } + 1
                guard let cell = rect(row: row, columns: column ..< column + 1) else { return nil }
                return convert(NSPoint(x: cell.midX, y: cell.midY), to: nil)
            }
            return nil
        }

        /// ⌘-moves onto the first cell showing `text` and ⌘-clicks it, through the pane's own mouse
        /// handlers as AppKit calls them (unlike `hoverLinkForTesting`, which talks to libghostty
        /// directly), so libghostty decides what the click opens, mouse captured or not.
        func commandClickForTesting(_ text: String) -> Bool {
            guard let window, let point = windowPointForTesting(of: text) else { return false }
            for type in [NSEvent.EventType.mouseMoved, .leftMouseDown, .leftMouseUp] {
                guard let event = NSEvent.mouseEvent(
                    with: type, location: point, modifierFlags: .command, timestamp: ProcessInfo.processInfo.systemUptime,
                    windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1,
                ) else { continue }
                switch type {
                case .mouseMoved: mouseMoved(with: event)
                case .leftMouseDown: mouseDown(with: event)
                default: mouseUp(with: event)
                }
            }
            return true
        }

        /// Rests the pointer on the first cell showing `text` with no modifier, then presses ⌘
        /// (a flagsChanged event, as the keyboard sends), so only the key press can start the hover.
        func commandPressOverForTesting(_ text: String) -> Bool {
            guard let window, let point = windowPointForTesting(of: text),
                  let moved = NSEvent.mouseEvent(
                      with: .mouseMoved, location: point, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                      windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 0, pressure: 0,
                  ),
                  let flags = NSEvent.keyEvent(
                      with: .flagsChanged, location: .zero, modifierFlags: .command, timestamp: ProcessInfo.processInfo.systemUptime,
                      windowNumber: window.windowNumber, context: nil, characters: "", charactersIgnoringModifiers: "",
                      isARepeat: false, keyCode: 0x37,
                  )
            else { return false }
            mouseMoved(with: moved)
            flagsChanged(with: flags)
            return true
        }

        /// What the grid's origin is worked out from: the baseline read_text reports, the IME point
        /// (the cursor cell's bottom), the cell size and the origin found.
        var gridGeometryForTesting: String {
            guard let surface else { return "no surface" }
            var text = ghostty_text_s()
            let corner = ghostty_point_s(tag: GHOSTTY_POINT_VIEWPORT, coord: GHOSTTY_POINT_COORD_EXACT, x: 0, y: 0)
            guard ghostty_surface_read_text(surface, ghostty_selection_s(top_left: corner, bottom_right: corner, rectangle: false), &text)
            else { return "no text" }
            defer { ghostty_surface_free_text(surface, &text) }
            var x = 0.0, y = 0.0, width = 0.0, height = 0.0
            ghostty_surface_ime_point(surface, &x, &y, &width, &height)
            let origin = gridOrigin().map { "\($0)" } ?? "none"
            return "baseline \(text.tl_px_y), ime bottom \(y), cell \(cellSize), view \(bounds.size), origin \(origin)"
        }

        /// The links marked at rest, top to bottom.
        var linkMarksForTesting: [String] {
            links.marks.keys.compactMap { match in match.runs.first.map { (match, $0) } }
                .sorted { ($0.1.row, $0.1.columns.lowerBound) < ($1.1.row, $1.1.columns.lowerBound) }
                .map { $0.0.runs.count > 1 ? "\($0.0.text) (\($0.0.runs.count) rows)" : $0.0.text }
        }

        func copyCellForTesting(_ text: String) -> String? {
            guard let window else { return nil }
            let grid = TextGrid(lines: viewportRows())
            var target: (row: Int, column: Int)?
            for (row, cells) in grid.cells.enumerated() {
                let line = cells.compactMap(\.self).map(String.init).joined()
                if let range = line.range(of: text) {
                    target = (row, line[..<range.lowerBound].reduce(0) { $0 + CellWidth.of($1) } + 1)
                    break
                }
            }
            guard let target, let cell = rect(row: target.row, columns: target.column ..< target.column + 1) else { return nil }
            let point = NSPoint(x: cell.midX, y: cell.midY)

            let saved = NSPasteboard.general.string(forType: .string)
            NSPasteboard.general.clearContents()
            for clicks in [1, 2] {
                for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
                    guard let event = NSEvent.mouseEvent(
                        with: type, location: convert(point, to: nil), modifierFlags: .option,
                        timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                        context: nil, eventNumber: 0, clickCount: clicks, pressure: 1,
                    ) else { continue }
                    if type == .leftMouseDown {
                        mouseDown(with: event)
                    } else {
                        mouseUp(with: event)
                    }
                }
            }
            let copied = NSPasteboard.general.string(forType: .string)
            NSPasteboard.general.clearContents()
            if let saved {
                NSPasteboard.general.setString(saved, forType: .string)
            }
            return copied
        }
    }
#endif

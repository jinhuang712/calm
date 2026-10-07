import AppKit
import GhosttyKit

/// Keyboard and IME input for terminal panes.
extension TerminalSurfaceView: @preconcurrency NSTextInputClient {
    // `@preconcurrency`: NSTextInputClient predates Swift concurrency; AppKit only calls it on main.

    // MARK: Key events

    override func keyDown(with event: NSEvent) {
        host?.surfaceDidReceiveInput(self)
        // Typing into the session closes find; ⌘ keys (⌘F, ⌘G, ⌘E) are find's own and pass by.
        if !event.modifierFlags.contains(.command) {
            host?.surfaceDidType(self)
        }
        updateCellOutline([]) // typing puts it away, as it does a link's tag
        guard let surface else {
            interpretKeyEvents([event])
            return
        }

        // Which modifiers take part in text translation (option-as-alt comes from the config).
        let translation = TerminalInput.flags(ghostty_surface_key_translation_mods(surface, TerminalInput.mods(event.modifierFlags)))
        var translationMods = event.modifierFlags // keeps hidden bits dead keys rely on
        for flag in [NSEvent.ModifierFlags.shift, .control, .option, .command] {
            if translation.contains(flag) {
                translationMods.insert(flag)
            } else {
                translationMods.remove(flag)
            }
        }
        // Reuse the original event when nothing changed; some input methods (Korean) depend on it.
        let translationEvent: NSEvent = if translationMods == event.modifierFlags {
            event
        } else {
            NSEvent.keyEvent(
                with: event.type, location: event.locationInWindow, modifierFlags: translationMods,
                timestamp: event.timestamp, windowNumber: event.windowNumber, context: nil,
                characters: event.characters(byApplyingModifiers: translationMods) ?? "",
                charactersIgnoringModifiers: event.charactersIgnoringModifiers ?? "",
                isARepeat: event.isARepeat, keyCode: event.keyCode,
            ) ?? event
        }

        let action = event.isARepeat ? GHOSTTY_ACTION_REPEAT : GHOSTTY_ACTION_PRESS
        keyTextAccumulator = []
        defer { keyTextAccumulator = nil }

        let hadMarkedText = markedText.length > 0
        let layoutBefore = hadMarkedText ? nil : TerminalInput.keyboardLayoutID
        lastPerformKeyEventTimestamp = nil

        interpretKeyEvents([translationEvent])

        // The key switched input sources: an input method consumed it.
        if !hadMarkedText, layoutBefore != TerminalInput.keyboardLayoutID {
            return
        }

        syncPreedit(clearIfNeeded: hadMarkedText)
        let composing = markedText.length > 0 || hadMarkedText
        let accumulated = keyTextAccumulator ?? []

        if hadMarkedText, !accumulated.isEmpty {
            // The input method committed text while handling this key: send it as typed input.
            for text in accumulated where !suppressesComposingControl(text, composing: composing) {
                sendCommittedText(text, action: action)
            }
            return
        }

        if !accumulated.isEmpty {
            for text in accumulated where !suppressesComposingControl(text, composing: composing) {
                sendKey(action, event: event, translationEvent: translationEvent, text: text, composing: composing)
            }
        } else {
            if let characters = event.characters, suppressesComposingControl(characters, composing: composing) {
                return
            }
            sendKey(
                action,
                event: event,
                translationEvent: translationEvent,
                text: translationEvent.terminalCharacters,
                composing: composing,
            )
        }
    }

    override func keyUp(with event: NSEvent) {
        sendKey(GHOSTTY_ACTION_RELEASE, event: event, translationEvent: nil, text: nil, composing: false)
    }

    override func flagsChanged(with event: NSEvent) {
        updateCellOutline(event.modifierFlags)
        let mod: UInt32 = switch event.keyCode {
        case 0x39: GHOSTTY_MODS_CAPS.rawValue
        case 0x38, 0x3C: GHOSTTY_MODS_SHIFT.rawValue
        case 0x3B, 0x3E: GHOSTTY_MODS_CTRL.rawValue
        case 0x3A, 0x3D: GHOSTTY_MODS_ALT.rawValue
        case 0x37, 0x36: GHOSTTY_MODS_SUPER.rawValue
        default: 0
        }
        guard mod != 0, !hasMarkedText() else { return }
        defer { refreshJoinedLinkHover() } // ⌘ going down or up over a link the pane finds itself
        links.isCommandDown = event.modifierFlags.contains(.command)

        var action = GHOSTTY_ACTION_RELEASE
        if TerminalInput.mods(event.modifierFlags).rawValue & mod != 0 {
            // For right-side keys, only a press if that side's device bit is set;
            // otherwise one side was released while the other is still held.
            let raw = event.modifierFlags.rawValue
            let sidePressed = switch event.keyCode {
            case 0x3C: raw & UInt(NX_DEVICERSHIFTKEYMASK) != 0
            case 0x3E: raw & UInt(NX_DEVICERCTLKEYMASK) != 0
            case 0x3D: raw & UInt(NX_DEVICERALTKEYMASK) != 0
            case 0x36: raw & UInt(NX_DEVICERCMDKEYMASK) != 0
            default: true
            }
            if sidePressed {
                action = GHOSTTY_ACTION_PRESS
            }
        }
        sendKey(action, event: event, translationEvent: nil, text: nil, composing: false)
    }

    /// Cmd- and ctrl-keys arrive here before `keyDown`. Terminal bindings win; everything
    /// else first goes through the menus, and comes back to the terminal if nothing took it.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        // Only the pane that has the keyboard answers: AppKit offers a key equivalent to every view
        // in turn, and the first to take it wins.
        guard event.type == .keyDown, isFocused, window?.firstResponder === self, let surface else { return false }
        host?.surfaceDidReceiveInput(self)

        var key = event.terminalKeyEvent(GHOSTTY_ACTION_PRESS)
        let isBinding = (event.characters ?? "").withCString { pointer in
            key.text = pointer
            var flags = ghostty_binding_flags_e(0)
            return ghostty_surface_key_is_binding(surface, key, &flags)
        }
        if isBinding {
            keyDown(with: event)
            return true
        }

        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if event.charactersIgnoringModifiers == "\r", flags.contains(.control) {
            keyDown(with: event)
            return true
        }
        if event.charactersIgnoringModifiers == "/", flags == .control {
            // Ctrl-/ makes macOS beep; send it as Ctrl-_ like other terminals.
            if let underscore = NSEvent.keyEvent(
                with: .keyDown, location: event.locationInWindow, modifierFlags: event.modifierFlags,
                timestamp: event.timestamp, windowNumber: event.windowNumber, context: nil,
                characters: "_", charactersIgnoringModifiers: "_", isARepeat: event.isARepeat, keyCode: event.keyCode,
            ) {
                keyDown(with: underscore)
                return true
            }
        }

        if event.timestamp == 0 {
            return false
        } // synthetic, e.g. Cmd-. turning into Escape
        guard flags.contains(.command) || flags.contains(.control) else {
            lastPerformKeyEventTimestamp = nil
            return false
        }
        if lastPerformKeyEventTimestamp == event.timestamp {
            // Second pass: no menu wanted it, so the terminal gets it.
            lastPerformKeyEventTimestamp = nil
            keyDown(with: event)
            return true
        }
        lastPerformKeyEventTimestamp = event.timestamp
        return false
    }

    /// Unhandled commands must not beep. An unclaimed cmd-key is sent back through the
    /// event pipeline so it reaches `performKeyEquivalent` for its second pass.
    override func doCommand(by _: Selector) {
        if let current = NSApp.currentEvent, lastPerformKeyEventTimestamp == current.timestamp {
            NSApp.sendEvent(current)
        }
    }

    private func sendKey(
        _ action: ghostty_input_action_e, event: NSEvent, translationEvent: NSEvent?, text: String?, composing: Bool,
    ) {
        guard let surface else { return }
        var key = event.terminalKeyEvent(action, translationMods: translationEvent?.modifierFlags)
        key.composing = composing
        if let text, text.isSendableKeyText, action != GHOSTTY_ACTION_RELEASE {
            text.withCString { pointer in
                key.text = pointer
                _ = ghostty_surface_key(surface, key)
            }
        } else {
            _ = ghostty_surface_key(surface, key)
        }
    }

    /// Committed input-method text is sent as a typed key, never as a paste.
    private func sendCommittedText(_ text: String, action: ghostty_input_action_e) {
        guard let surface else { return }
        var key = ghostty_input_key_s()
        key.action = action
        key.keycode = 0
        key.mods = GHOSTTY_MODS_NONE
        key.consumed_mods = GHOSTTY_MODS_NONE
        key.unshifted_codepoint = 0
        key.composing = false
        text.withCString { pointer in
            key.text = pointer
            _ = ghostty_surface_key(surface, key)
        }
    }

    private func suppressesComposingControl(_ text: String, composing: Bool) -> Bool {
        guard composing, text.unicodeScalars.count == 1, let scalar = text.unicodeScalars.first else { return false }
        return scalar.value < 0x20
    }

    func syncPreedit(clearIfNeeded: Bool = true) {
        guard let surface else { return }
        if markedText.length > 0 {
            let string = markedText.string
            string.withCString { ghostty_surface_preedit(surface, $0, UInt(string.utf8.count)) }
        } else if clearIfNeeded {
            ghostty_surface_preedit(surface, nil, 0)
        }
    }

    // MARK: NSTextInputClient

    func hasMarkedText() -> Bool {
        markedText.length > 0
    }

    func markedRange() -> NSRange {
        markedText.length > 0 ? NSRange(location: 0, length: markedText.length) : NSRange(location: NSNotFound, length: 0)
    }

    func selectedRange() -> NSRange {
        // Never `{NSNotFound, 0}`: that says "no insertion point", and System Dictation and voice
        // tools then decline to start. We keep no text storage to index, so an empty range at 0
        // is the caret (Ghostty answers the same).
        let caret = NSRange(location: 0, length: 0)
        guard let surface else { return caret }
        var text = ghostty_text_s()
        guard ghostty_surface_read_selection(surface, &text) else { return caret }
        defer { ghostty_surface_free_text(surface, &text) }
        return NSRange(location: Int(text.offset_start), length: Int(text.offset_len))
    }

    func setMarkedText(_ string: Any, selectedRange _: NSRange, replacementRange _: NSRange) {
        switch string {
        case let attributed as NSAttributedString: markedText = NSMutableAttributedString(attributedString: attributed)
        case let plain as String: markedText = NSMutableAttributedString(string: plain)
        default: return
        }
        // Outside keyDown (e.g. a layout change mid dead-key), update the preedit now.
        if keyTextAccumulator == nil {
            syncPreedit()
        }
    }

    func unmarkText() {
        guard markedText.length > 0 else { return }
        markedText.mutableString.setString("")
        syncPreedit()
    }

    func validAttributesForMarkedText() -> [NSAttributedString.Key] {
        []
    }

    func attributedSubstring(forProposedRange _: NSRange, actualRange _: NSRangePointer?) -> NSAttributedString? {
        nil
    }

    func characterIndex(for _: NSPoint) -> Int {
        0
    }

    func firstRect(forCharacterRange range: NSRange, actualRange _: NSRangePointer?) -> NSRect {
        guard let surface else { return .zero }
        var x = 0.0
        var y = 0.0
        var width = Double(cellSize.width)
        var height = Double(cellSize.height)
        ghostty_surface_ime_point(surface, &x, &y, &width, &height)
        if range.length == 0, width > 0 {
            // Dictation wants a caret, not a box.
            width = 0
            x += Double(cellSize.width) * Double(range.location + range.length)
        }
        // libghostty reports points with a top-left origin.
        let viewRect = NSRect(x: x, y: frame.height - y, width: width, height: max(height, Double(cellSize.height)))
        let windowRect = convert(viewRect, to: nil)
        return window?.convertToScreen(windowRect) ?? windowRect
    }

    func insertText(_ string: Any, replacementRange _: NSRange) {
        // No check for a current key event: dictation and voice input methods commit from their own
        // callbacks, after the key that started them, and their text was being dropped here.
        var text = switch string {
        case let attributed as NSAttributedString: attributed.string
        case let plain as String: plain
        default: ""
        }

        // Join a UTF-16 surrogate pair that arrives in two calls.
        if let lead = pendingLeadSurrogate {
            pendingLeadSurrogate = nil
            let units = Array(text.utf16)
            if let trail = units.first, UTF16.isTrailSurrogate(trail) {
                text = String(decoding: [lead] + units, as: UTF16.self)
            }
        }
        let units = Array(text.utf16)
        if units.count == 1, UTF16.isLeadSurrogate(units[0]) {
            pendingLeadSurrogate = units[0]
            return
        }
        if units.count == 1, UTF16.isTrailSurrogate(units[0]) {
            return
        }

        unmarkText()
        if keyTextAccumulator != nil {
            keyTextAccumulator?.append(text)
        } else if !text.isEmpty {
            // Dictation, the emoji picker, or an input method committing by mouse. (An empty commit
            // only clears the marked text above; sent on, it would be a key press with no text.)
            sendCommittedText(text, action: GHOSTTY_ACTION_PRESS)
        }
    }
}

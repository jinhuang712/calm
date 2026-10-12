import AppKit
import SwiftUI

/// Where a text field's caret is. SwiftUI reports it through `TextSelection` only from macOS 15, so
/// on macOS 14 it is read off the field's editor (an `NSTextView`) when asked. From macOS 15 on it is
/// SwiftUI's own selection, as it always was.
struct FieldCaret {
    private var stored: Any?

    @available(macOS 15, *)
    fileprivate var selection: TextSelection? {
        get { stored as? TextSelection }
        set { stored = newValue }
    }

    /// The caret's place as a count of characters from the start of `text`, or nil while a range is
    /// selected or the place isn't known.
    @MainActor
    func offset(in text: String) -> Int? {
        if #available(macOS 15, *) {
            guard case let .selection(range)? = selection?.indices, range.isEmpty else { return nil }
            return text.distance(from: text.startIndex, to: range.lowerBound)
        }
        guard let editor = NSApp.keyWindow?.firstResponder as? NSTextView, editor.selectedRange().length == 0 else { return nil }
        let location = editor.selectedRange().location
        guard let index = Range(NSRange(location: location, length: 0), in: text)?.lowerBound else { return nil }
        return text.distance(from: text.startIndex, to: index)
    }
}

/// A plain text field that keeps its caret in `caret`.
struct CaretTextField: View {
    @Binding var text: String
    @Binding var caret: FieldCaret
    let prompt: Text

    var body: some View {
        if #available(macOS 15, *) {
            TextField("", text: $text, selection: Binding(get: { caret.selection }, set: { caret.selection = $0 }), prompt: prompt)
        } else {
            TextField("", text: $text, prompt: prompt)
        }
    }
}

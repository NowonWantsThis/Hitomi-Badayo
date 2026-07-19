import AppKit
import SwiftUI

enum OriginalInputType: String, CaseIterable, Equatable {
    case hitomi
    case ehen
    case pixiv
    case hiyobi

    static let metadataKey = "original_input_type"

    static var autocompleteKeywords: [String] {
        allCases.map(\.rawValue).sorted()
    }

    static func prefixedInput(from raw: String) -> (type: OriginalInputType, payload: String)? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowercased = trimmed.lowercased()
        for type in allCases {
            let prefix = type.rawValue + "_"
            guard lowercased.hasPrefix(prefix) else { continue }
            let payload = String(trimmed.dropFirst(prefix.count))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return payload.isEmpty ? nil : (type, payload)
        }
        return nil
    }
}

enum OriginalInputAutocomplete {
    private static let splitters = [" -", " ", ",", "\""]

    struct Replacement: Equatable {
        var text: String
        var cursorUTF16Offset: Int
    }

    static func fragment(in text: String, cursorUTF16Offset: Int? = nil) -> String {
        let nsText = text as NSString
        let offset = min(max(cursorUTF16Offset ?? nsText.length, 0), nsText.length)
        var fragment = nsText.substring(to: offset)
        for splitter in splitters {
            fragment = fragment.components(separatedBy: splitter).last ?? fragment
        }
        fragment = fragment.trimmingCharacters(in: .whitespacesAndNewlines)
        if fragment.hasPrefix("-") {
            fragment = String(fragment.dropFirst()).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return fragment
    }

    static func suggestions(
        forFragment fragment: String,
        keywords: [String] = OriginalInputType.autocompleteKeywords,
        limit: Int = 1_000
    ) -> [String] {
        let query = fragment.lowercased()
        guard !query.isEmpty, limit > 0 else { return [] }
        let matches = keywords
            .map { $0.components(separatedBy: "(").first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? $0 }
            .filter { $0.lowercased().contains(query) }
            .sorted()
        guard matches.count > limit else { return matches }
        return Array(matches[0..<limit])
    }

    static func replacingFragment(
        in text: String,
        cursorUTF16Offset: Int,
        with completion: String,
        allowSpace: Bool = true
    ) -> Replacement {
        let nsText = text as NSString
        let offset = min(max(cursorUTF16Offset, 0), nsText.length)
        let fragment = fragment(in: text, cursorUTF16Offset: offset)
        let fragmentLength = (fragment as NSString).length
        let replacement = !allowSpace && completion.contains(" ") && !completion.hasPrefix("\"")
            ? "\"\(completion)\""
            : completion
        let range = NSRange(
            location: max(0, offset - fragmentLength),
            length: min(fragmentLength, offset)
        )
        let result = nsText.replacingCharacters(in: range, with: replacement)
        return Replacement(
            text: result,
            cursorUTF16Offset: range.location + (replacement as NSString).length
        )
    }
}

struct OriginalURLTextField: NSViewRepresentable {
    @Binding var text: String
    var cursorUTF16Offset: Int
    var placeholder: String
    var fontSize: CGFloat
    var onFocusChange: (Bool) -> Void = { _ in }
    var onCursorChange: (Int) -> Void = { _ in }
    var onMoveCompletion: (Int) -> Bool = { _ in false }
    var onAcceptCompletion: () -> Bool = { false }
    var onDismissCompletion: () -> Bool = { false }
    var onSubmit: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            text: $text,
            onFocusChange: onFocusChange,
            onCursorChange: onCursorChange,
            onMoveCompletion: onMoveCompletion,
            onAcceptCompletion: onAcceptCompletion,
            onDismissCompletion: onDismissCompletion,
            onSubmit: onSubmit
        )
    }

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField(string: text)
        field.delegate = context.coordinator
        field.target = context.coordinator
        field.action = #selector(Coordinator.submit(_:))
        field.placeholderString = AppLocalization.text(placeholder)
        field.font = .systemFont(ofSize: fontSize)
        field.isBezeled = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.lineBreakMode = .byTruncatingTail
        field.maximumNumberOfLines = 1
        field.usesSingleLineMode = true
        field.cell?.isScrollable = true
        field.setAccessibilityLabel("URL")
        return field
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        context.coordinator.text = $text
        context.coordinator.onFocusChange = onFocusChange
        context.coordinator.onCursorChange = onCursorChange
        context.coordinator.onMoveCompletion = onMoveCompletion
        context.coordinator.onAcceptCompletion = onAcceptCompletion
        context.coordinator.onDismissCompletion = onDismissCompletion
        context.coordinator.onSubmit = onSubmit
        field.placeholderString = AppLocalization.text(placeholder)
        field.font = .systemFont(ofSize: fontSize)
        let textChanged = field.stringValue != text
        let desiredOffset = min(max(cursorUTF16Offset, 0), (text as NSString).length)
        let editor = field.currentEditor() as? NSTextView
        let cursorChanged = editor.map { $0.selectedRange().location != desiredOffset } ?? false
        guard textChanged || cursorChanged else { return }
        context.coordinator.isUpdatingFromSwiftUI = true
        if textChanged {
            field.stringValue = text
            editor?.string = text
        }
        if cursorChanged {
            editor?.setSelectedRange(NSRange(location: desiredOffset, length: 0))
        }
        context.coordinator.isUpdatingFromSwiftUI = false
    }

    static func dismantleNSView(_ field: NSTextField, coordinator: Coordinator) {
        coordinator.stopObservingSelection()
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var text: Binding<String>
        var onFocusChange: (Bool) -> Void
        var onCursorChange: (Int) -> Void
        var onMoveCompletion: (Int) -> Bool
        var onAcceptCompletion: () -> Bool
        var onDismissCompletion: () -> Bool
        var onSubmit: () -> Void
        var isUpdatingFromSwiftUI = false
        private weak var observedEditor: NSTextView?

        init(
            text: Binding<String>,
            onFocusChange: @escaping (Bool) -> Void,
            onCursorChange: @escaping (Int) -> Void,
            onMoveCompletion: @escaping (Int) -> Bool,
            onAcceptCompletion: @escaping () -> Bool,
            onDismissCompletion: @escaping () -> Bool,
            onSubmit: @escaping () -> Void
        ) {
            self.text = text
            self.onFocusChange = onFocusChange
            self.onCursorChange = onCursorChange
            self.onMoveCompletion = onMoveCompletion
            self.onAcceptCompletion = onAcceptCompletion
            self.onDismissCompletion = onDismissCompletion
            self.onSubmit = onSubmit
        }

        func controlTextDidBeginEditing(_ notification: Notification) {
            onFocusChange(true)
            if let field = notification.object as? NSTextField,
               let editor = field.currentEditor() as? NSTextView {
                startObservingSelection(in: editor)
                reportCursor(in: editor)
            }
        }

        func controlTextDidChange(_ notification: Notification) {
            guard !isUpdatingFromSwiftUI,
                  let field = notification.object as? NSTextField else { return }
            text.wrappedValue = field.stringValue
            if let editor = field.currentEditor() as? NSTextView {
                reportCursor(in: editor)
            }
        }

        func controlTextDidEndEditing(_ notification: Notification) {
            stopObservingSelection()
            onFocusChange(false)
        }

        func control(
            _ control: NSControl,
            textView: NSTextView,
            doCommandBy commandSelector: Selector
        ) -> Bool {
            switch commandSelector {
            case #selector(NSResponder.moveDown(_:)):
                return onMoveCompletion(1)
            case #selector(NSResponder.moveUp(_:)):
                return onMoveCompletion(-1)
            case #selector(NSResponder.insertTab(_:)),
                 #selector(NSResponder.insertBacktab(_:)),
                 #selector(NSResponder.insertNewline(_:)):
                return onAcceptCompletion()
            case #selector(NSResponder.cancelOperation(_:)):
                return onDismissCompletion()
            default:
                return false
            }
        }

        @objc func submit(_ sender: NSTextField) {
            text.wrappedValue = sender.stringValue
            onSubmit()
        }

        private func startObservingSelection(in editor: NSTextView) {
            guard observedEditor !== editor else { return }
            stopObservingSelection()
            observedEditor = editor
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(selectionDidChange(_:)),
                name: NSTextView.didChangeSelectionNotification,
                object: editor
            )
        }

        func stopObservingSelection() {
            if let observedEditor {
                NotificationCenter.default.removeObserver(
                    self,
                    name: NSTextView.didChangeSelectionNotification,
                    object: observedEditor
                )
            }
            observedEditor = nil
        }

        @objc private func selectionDidChange(_ notification: Notification) {
            guard !isUpdatingFromSwiftUI,
                  let editor = notification.object as? NSTextView else { return }
            reportCursor(in: editor)
        }

        private func reportCursor(in editor: NSTextView) {
            onCursorChange(editor.selectedRange().location)
        }
    }
}

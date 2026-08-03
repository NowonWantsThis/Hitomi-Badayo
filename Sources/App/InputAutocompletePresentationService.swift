import Foundation

enum InputAutocompletePresentationService {
    static func visibleSuggestions(
        inputText: String,
        cursorUTF16Offset: Int,
        isInputFocused: Bool,
        isDismissed: Bool
    ) -> [String] {
        guard isInputFocused, !isDismissed else { return [] }
        return availableSuggestions(
            inputText: inputText,
            cursorUTF16Offset: cursorUTF16Offset
        )
    }

    static func availableSuggestions(
        inputText: String,
        cursorUTF16Offset: Int
    ) -> [String] {
        let fragment = OriginalInputAutocomplete.fragment(
            in: inputText,
            cursorUTF16Offset: cursorUTF16Offset
        )
        return OriginalInputAutocomplete.suggestions(forFragment: fragment)
    }
}

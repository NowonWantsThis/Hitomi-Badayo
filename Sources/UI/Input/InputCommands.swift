import SwiftUI

struct InputCommands {
    private let manager: DownloadManager?

    init(manager: DownloadManager? = nil) {
        self.manager = manager
    }

    @MainActor
    func setText(_ text: String) {
        manager?.setInputText(text)
    }

    @MainActor
    func setFocused(_ focused: Bool) {
        manager?.setURLInputFocused(focused)
    }

    @MainActor
    func setCursorUTF16Offset(_ offset: Int) {
        manager?.setInputCursorUTF16Offset(offset)
    }

    @discardableResult
    @MainActor
    func moveAutocompleteSelection(by delta: Int) -> Bool {
        manager?.moveInputAutocompleteSelection(by: delta) ?? false
    }

    @MainActor
    func setAutocompleteSelection(_ index: Int) {
        manager?.setInputAutocompleteSelection(index)
    }

    @discardableResult
    @MainActor
    func acceptAutocompleteSuggestion(_ suggestion: String? = nil) -> Bool {
        manager?.acceptInputAutocompleteSuggestion(suggestion) ?? false
    }

    @discardableResult
    @MainActor
    func dismissAutocomplete() -> Bool {
        manager?.dismissInputAutocomplete() ?? false
    }

    @MainActor
    func paste() {
        manager?.pasteURLs()
    }

    @discardableResult
    @MainActor
    func pasteAndDownload(_ text: String? = nil) -> Bool {
        manager?.pasteAndDownloadURLs(text: text) ?? false
    }

    @MainActor
    func addURLs(fallbackText: String? = nil) {
        manager?.addURLs(fallbackText: fallbackText)
    }

    @MainActor
    func addMP3AudioURLs() {
        manager?.addMP3AudioURLs()
    }

    @MainActor
    func bookmarkURLs() {
        manager?.bookmarkInputURLs()
    }

    @MainActor
    func addLocalFilesAndFolders() {
        manager?.addLocalFilesAndFolders()
    }

    @MainActor
    func importURLList() {
        manager?.importURLList()
    }
}

private struct InputCommandsKey: EnvironmentKey {
    static let defaultValue = InputCommands()
}

extension EnvironmentValues {
    var inputCommands: InputCommands {
        get { self[InputCommandsKey.self] }
        set { self[InputCommandsKey.self] = newValue }
    }
}

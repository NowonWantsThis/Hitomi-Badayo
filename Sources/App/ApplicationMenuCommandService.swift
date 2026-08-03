import AppKit
import Foundation

@MainActor
final class ApplicationMenuCommandService {
    typealias Handler =
        (AppInterfaceLanguage) -> Void

    private let handler: Handler?

    init(handler: Handler? = nil) {
        self.handler = handler
    }

    func applyInterfaceLanguage(
        _ language: AppInterfaceLanguage
    ) {
        if let handler {
            handler(language)
            return
        }
        AppMainMenuPruner.simplify(
            NSApplication.shared.mainMenu,
            language: language
        )
    }
}

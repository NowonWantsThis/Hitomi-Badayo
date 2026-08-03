import AppKit
import Foundation

struct ConfirmationDialogRequest {
    var style: NSAlert.Style
    var message: String
    var informativeText: String
    var confirmButtonTitle: String
    var cancelButtonTitle: String
}

@MainActor
final class ConfirmationDialogService {
    typealias Handler =
        (ConfirmationDialogRequest) -> Bool

    private let handler: Handler?

    init(handler: Handler? = nil) {
        self.handler = handler
    }

    func confirm(
        _ request: ConfirmationDialogRequest
    ) -> Bool {
        if let handler {
            return handler(request)
        }

        let alert = NSAlert()
        alert.alertStyle = request.style
        alert.messageText = request.message
        alert.informativeText =
            request.informativeText
        alert.addButton(
            withTitle:
                request.confirmButtonTitle
        )
        alert.addButton(
            withTitle:
                request.cancelButtonTitle
        )
        return alert.runModal() ==
            .alertFirstButtonReturn
    }
}

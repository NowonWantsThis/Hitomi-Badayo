import AppKit
import Foundation

@MainActor
final class QueueCompletionCommandService {
    let workspaceItemCommandService:
        WorkspaceItemCommandService
    private let shouldSkipCommand: () -> Bool
    private let terminateApplication:
        @MainActor () -> Void

    init(
        workspaceItemCommandService:
            WorkspaceItemCommandService,
        shouldSkipCommand:
            @escaping () -> Bool = {
                ProcessInfo.processInfo.environment[
                    "HITOMI_NATIVE_SKIP_QUEUE_COMPLETION_ACTION"
                ] == "1"
        },
        terminateApplication:
            @escaping @MainActor () -> Void = {
                NSApplication.shared.terminate(nil)
            }
    ) {
        self.workspaceItemCommandService =
            workspaceItemCommandService
        self.shouldSkipCommand = shouldSkipCommand
        self.terminateApplication = terminateApplication
    }

    func perform(
        _ action: QueueCompletionAction,
        summary: String,
        destinationPath: String,
        language: AppInterfaceLanguage
    ) -> String {
        switch action {
        case .none:
            return Self.statusText(for: .none)
        case .openDestination:
            let status = AppLocalization.format(
                "After completion: Open Folder (%@)",
                language: language,
                summary
            )
            guard !shouldSkipCommand() else {
                return status
            }
            _ = workspaceItemCommandService.open(
                URL(
                    fileURLWithPath: destinationPath,
                    isDirectory: true
                )
            )
            return status
        case .quitApp:
            let status = AppLocalization.format(
                "After completion: Quit App (%@)",
                language: language,
                summary
            )
            guard !shouldSkipCommand() else {
                return status
            }
            terminateApplication()
            return status
        }
    }

    nonisolated static func statusText(
        for action: QueueCompletionAction
    ) -> String {
        AppLocalization.format(
            "After completion: %@",
            AppLocalization.text(
                action == .none
                ? "Do Nothing"
                : action.label
            )
        )
    }
}

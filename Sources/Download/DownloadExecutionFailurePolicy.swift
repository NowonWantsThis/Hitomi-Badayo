import Foundation

enum DownloadExecutionFailureDisposition: Equatable {
    case cancelled
    case taskReaction(name: String, message: String)
    case retryRequested(message: String)
    case failed(message: String, allowsIncompleteRetry: Bool)
}

enum DownloadExecutionFailureContext: Equatable {
    case startHook
    case sourceExecution
}

enum DownloadExecutionFailureAction: Equatable {
    case cancel
    case fail(
        message: String,
        reaction: String?,
        allowsIncompleteRetry: Bool,
        attemptRecordingRetry: Bool
    )
}

final class DownloadExecutionFailurePolicy {
    func disposition(
        for error: Error
    ) -> DownloadExecutionFailureDisposition {
        if error is CancellationError {
            return .cancelled
        }
        if let bridgeError = error as? PythonScriptBridgeError {
            switch bridgeError {
            case .taskReaction(let name, let message):
                return .taskReaction(name: name, message: message)
            case .retryRequested(_, let message):
                return .retryRequested(message: message)
            default:
                break
            }
        }
        return .failed(
            message: AppLocalization.errorText(error),
            allowsIncompleteRetry:
                DownloadRetryPolicy.failureAllowsIncompleteRetry(error)
        )
    }

    func action(
        for disposition:
            DownloadExecutionFailureDisposition,
        context: DownloadExecutionFailureContext
    ) -> DownloadExecutionFailureAction {
        switch disposition {
        case .cancelled:
            return .cancel
        case .taskReaction(let name, let message):
            return .fail(
                message: message,
                reaction: name,
                allowsIncompleteRetry: true,
                attemptRecordingRetry: false
            )
        case .retryRequested(let message):
            return .fail(
                message: message,
                reaction: nil,
                allowsIncompleteRetry: false,
                attemptRecordingRetry: false
            )
        case .failed(
            let message,
            let allowsIncompleteRetry
        ):
            return .fail(
                message:
                    context == .startHook
                    ? "Start hook failed: \(message)"
                    : message,
                reaction: nil,
                allowsIncompleteRetry:
                    allowsIncompleteRetry,
                attemptRecordingRetry:
                    context == .sourceExecution
            )
        }
    }
}

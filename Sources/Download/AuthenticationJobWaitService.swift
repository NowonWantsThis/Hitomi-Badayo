import Foundation

@MainActor
final class AuthenticationJobWaitService {
    let queueStore: QueueStore
    let waitCoordinator:
        AuthenticationWaitCoordinator

    init(
        queueStore: QueueStore,
        waitCoordinator:
            AuthenticationWaitCoordinator
    ) {
        self.queueStore = queueStore
        self.waitCoordinator = waitCoordinator
    }

    func wait(
        jobID: UUID,
        provider: String,
        waitingMessage: String,
        requiredSummary: String,
        resumedMessage: String,
        persist: @MainActor () -> Void,
        setSummary:
            @MainActor (String) -> Void,
        onRegistered:
            @MainActor @escaping () -> Void
    ) async {
        guard queueStore.updateJob(
            id: jobID,
            {
                $0.status = .resolving
                $0.message = waitingMessage
                $0.metadata[
                    "authentication_waiting"
                ] = provider
            }
        ) else {
            return
        }
        persist()
        setSummary(requiredSummary)

        await waitCoordinator.wait(
            jobID: jobID,
            provider: provider,
            onRegistered: onRegistered
        )

        guard queueStore.updateJob(
            id: jobID,
            {
                $0.metadata.removeValue(
                    forKey:
                        "authentication_waiting"
                )
                if $0.status != .cancelled {
                    $0.message = resumedMessage
                }
            }
        ) else {
            return
        }
        persist()
    }
}

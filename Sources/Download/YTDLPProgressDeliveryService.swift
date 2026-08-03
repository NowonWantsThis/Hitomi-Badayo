import Foundation

final class YTDLPProgressDeliveryService:
    @unchecked Sendable
{
    typealias Apply =
        @MainActor @Sendable (
            YTDLPRuntimeUpdate,
            UUID
        ) -> Void

    func handler(
        jobID: UUID,
        apply:
            @escaping Apply
    ) -> @Sendable (YTDLPRuntimeUpdate) -> Void {
        { update in
            Task { @MainActor in
                apply(update, jobID)
            }
        }
    }
}

import Foundation

@MainActor
final class PythonNativeDelegationCoordinator {
    private var activeJobIDs: Set<UUID> = []

    func allowsPythonPlugin(for jobID: UUID) -> Bool {
        !activeJobIDs.contains(jobID)
    }

    func withNativeResolver<Result>(
        jobID: UUID,
        operation: () async throws -> Result
    ) async rethrows -> Result {
        activeJobIDs.insert(jobID)
        defer { activeJobIDs.remove(jobID) }
        return try await operation()
    }
}

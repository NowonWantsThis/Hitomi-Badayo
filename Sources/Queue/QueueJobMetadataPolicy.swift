import Foundation

enum QueueJobMetadataPolicy {
    static let groupIDMetadataKey = "queue_group_id"
    static let pendingRemovalMetadataKey = "pending_queue_removal"

    static func metadataGroupID(for job: DownloadJob) -> UUID? {
        job.metadata[groupIDMetadataKey]
            .flatMap { UUID(uuidString: $0.trimmed) }
    }

    static func groupID(
        for job: DownloadJob,
        groups: [QueueGroup]
    ) -> UUID? {
        if let id = metadataGroupID(for: job),
           groups.contains(where: { $0.id == id }) {
            return id
        }
        let legacyName = (
            job.metadata["group"] ??
                job.metadata["group_name"] ??
                ""
        ).trimmed
        guard !legacyName.isEmpty else { return nil }
        return groups.first {
            $0.name.caseInsensitiveCompare(legacyName) == .orderedSame
        }?.id
    }

    static func isPendingRemoval(_ job: DownloadJob) -> Bool {
        job.metadata[pendingRemovalMetadataKey]?
            .trimmed.lowercased() == "true"
    }
}

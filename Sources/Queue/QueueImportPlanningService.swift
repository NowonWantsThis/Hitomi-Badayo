import Foundation

struct QueueImportPlan {
    var jobs: [DownloadJob]
    var groups: [QueueGroup]
}

enum QueueImportPlanningService {
    static func plan(
        document: QueueImportDocument,
        existingJobIDs: Set<UUID>,
        existingGroupIDs: Set<UUID>,
        groupIDMetadataKey: String
    ) -> QueueImportPlan {
        var importedGroups = document.groups
        var usedGroupIDs = existingGroupIDs
        var groupIDMap: [UUID: UUID] = [:]
        for index in importedGroups.indices {
            let originalID = importedGroups[index].id
            var resolvedID = originalID
            while usedGroupIDs.contains(resolvedID) {
                resolvedID = UUID()
            }
            usedGroupIDs.insert(resolvedID)
            groupIDMap[originalID] = resolvedID
            importedGroups[index].id = resolvedID
        }

        var usedJobIDs = existingJobIDs
        var jobIDMap: [UUID: UUID] = [:]
        var normalized: [DownloadJob] = []
        for var job in document.jobs {
            let originalID = job.id
            if let oldGroupID = groupID(
                in: job,
                metadataKey: groupIDMetadataKey
            ), let newGroupID = groupIDMap[oldGroupID] {
                job.metadata[groupIDMetadataKey] = newGroupID.uuidString
            }
            guard let restored = normalizedImportedJob(
                job,
                existingIDs: &usedJobIDs
            ) else {
                continue
            }
            jobIDMap[originalID] = restored.id
            normalized.append(restored)
        }
        for index in importedGroups.indices {
            if let anchor = importedGroups[index].anchorJobID {
                importedGroups[index].anchorJobID = jobIDMap[anchor]
            }
        }
        importedGroups = QueueGroupNormalizationService.normalizedGroups(
            importedGroups,
            jobs: &normalized,
            groupIDMetadataKey: groupIDMetadataKey
        )
        return QueueImportPlan(jobs: normalized, groups: importedGroups)
    }

    private static func normalizedImportedJob(
        _ job: DownloadJob,
        existingIDs: inout Set<UUID>
    ) -> DownloadJob? {
        var restored = QueueRecoveryPolicy.restorePersistedJob(job)
        let source = SourceInputNormalizer.normalizedToken(
            restored.source.trimmed
        )
        guard !source.isEmpty else { return nil }

        restored.source = source
        if restored.title.trimmed.isEmpty {
            restored.title = source
        }
        restored.comment = restored.comment.trimmed
        restored.rangeExpression = ResolvedDownloadRangeService
            .isValidAssetRangeExpression(restored.rangeExpression)
            ? restored.rangeExpression.trimmed
            : ""
        if existingIDs.contains(restored.id) {
            restored.id = UUID()
        }
        existingIDs.insert(restored.id)
        return restored
    }

    private static func groupID(
        in job: DownloadJob,
        metadataKey: String
    ) -> UUID? {
        job.metadata[metadataKey]
            .flatMap { UUID(uuidString: $0.trimmed) }
    }
}

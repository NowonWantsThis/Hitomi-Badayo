import Foundation

struct QueuePresentationSnapshot {
    let filteredJobs: [DownloadJob]
    let listEntries: [QueueListEntry]
    let groupOptions: [QueueGroup]
    let jobsByGroupID: [UUID: [DownloadJob]]
    let removableFinishedJobCount: Int
    let removableCompletedJobCount: Int
    let retryableIncompleteJobCount: Int
    let canSelectRandomVisibleJob: Bool
    let removalConfirmationMessage: String

    func jobs(in group: QueueGroup) -> [DownloadJob] {
        jobsByGroupID[group.id] ?? []
    }
}

@MainActor
enum QueuePresentationReadModelService {
    static func snapshot(
        jobs: [DownloadJob],
        groups: [QueueGroup],
        scheduler: QueueScheduler,
        query: String,
        sortMode: QueueSortMode,
        descending: Bool,
        selectedJobIDs: Set<UUID>,
        pendingRemovalIDs: [UUID],
        language: AppInterfaceLanguage
    ) -> QueuePresentationSnapshot {
        let orderedJobs = scheduler.orderedJobs(from: jobs).filter {
            !QueueJobMetadataPolicy.isPendingRemoval($0)
        }
        let filteredJobs = QueueListPresentationService.filteredJobs(
            orderedJobs: orderedJobs,
            query: query,
            sortMode: sortMode,
            descending: descending,
            duplicateKey: {
                DownloadRequestIdentityService.duplicateKey(
                    source: $0.source,
                    metadata: $0.metadata
                )
            }
        )
        let listEntries = QueueListPresentationService.listEntries(
            orderedJobs: orderedJobs,
            groups: groups,
            query: query,
            sortMode: sortMode,
            descending: descending,
            duplicateKey: {
                DownloadRequestIdentityService.duplicateKey(
                    source: $0.source,
                    metadata: $0.metadata
                )
            },
            groupID: QueueJobMetadataPolicy.metadataGroupID
        )
        let groupOptions = sortedGroupOptions(groups)
        let jobsByGroupID = Dictionary(grouping: orderedJobs) { job in
            QueueJobMetadataPolicy.groupID(for: job, groups: groups)
        }.reduce(into: [UUID: [DownloadJob]]()) { result, entry in
            guard let groupID = entry.key else { return }
            result[groupID] = entry.value
        }
        let removableFinishedJobCount = jobs.filter {
            isRemovableFinishedJob($0)
        }.count
        let removableCompletedJobCount = jobs.filter {
            isRemovableCompletedJob($0, groups: groups)
        }.count
        let retryableIncompleteJobCount = jobs.filter {
            isRetryableIncompleteJob($0, groups: groups)
        }.count

        return QueuePresentationSnapshot(
            filteredJobs: filteredJobs,
            listEntries: listEntries,
            groupOptions: groupOptions,
            jobsByGroupID: jobsByGroupID,
            removableFinishedJobCount: removableFinishedJobCount,
            removableCompletedJobCount: removableCompletedJobCount,
            retryableIncompleteJobCount: retryableIncompleteJobCount,
            canSelectRandomVisibleJob: canSelectRandomVisibleJob(
                filteredJobs: filteredJobs,
                selectedJobIDs: selectedJobIDs
            ),
            removalConfirmationMessage: removalConfirmationMessage(
                jobs: jobs,
                pendingRemovalIDs: pendingRemovalIDs,
                language: language
            )
        )
    }

    static func sortedGroupOptions(_ groups: [QueueGroup]) -> [QueueGroup] {
        groups.sorted {
            let comparison = $0.name.localizedStandardCompare($1.name)
            if comparison == .orderedSame {
                return $0.id.uuidString < $1.id.uuidString
            }
            return comparison == .orderedAscending
        }
    }

    static func isRetryableIncompleteJob(
        _ job: DownloadJob,
        groups: [QueueGroup]
    ) -> Bool {
        QueueRecoveryPolicy.isRetryableIncompleteJob(
            job,
            isFolded: isFolded(job, groups: groups)
        )
    }

    static func isRemovableCompletedJob(
        _ job: DownloadJob,
        groups: [QueueGroup]
    ) -> Bool {
        job.status == .finished &&
            (job.total <= 0 || job.completed >= job.total) &&
            !job.isLocked &&
            !isFolded(job, groups: groups)
    }

    static func isRemovableFinishedJob(_ job: DownloadJob) -> Bool {
        !job.isLocked && (
            job.status == .finished ||
                job.status == .failed ||
                job.status == .cancelled
        )
    }

    static func canSelectRandomVisibleJob(
        filteredJobs: [DownloadJob],
        selectedJobIDs: Set<UUID>
    ) -> Bool {
        guard !filteredJobs.isEmpty else { return false }
        guard let currentID = filteredJobs.first(where: {
            selectedJobIDs.contains($0.id)
        })?.id else {
            return true
        }
        return filteredJobs.contains { $0.id != currentID }
    }

    static func removalConfirmationMessage(
        jobs: [DownloadJob],
        pendingRemovalIDs: [UUID],
        language: AppInterfaceLanguage
    ) -> String {
        let pending = Set(pendingRemovalIDs)
        let selected = jobs.filter { pending.contains($0.id) }
        let activeNote: String
        if selected.contains(where: {
            $0.status == .resolving || $0.status == .downloading
        }) {
            activeNote = AppLocalization.text(
                "\nActive downloads will be cancelled immediately. Files already downloaded will be kept.",
                language: language
            )
        } else {
            activeNote = ""
        }
        guard selected.count != 1 else {
            return AppLocalization.format(
                "Remove \"%@\" from the list only. Downloaded files will not be deleted.%@",
                language: language,
                selected[0].title,
                activeNote
            )
        }

        let titles = selected.prefix(10).map { job in
            "• \(job.title.trimmed.isEmpty ? job.source : job.title)"
        }.joined(separator: "\n")
        let remainder = selected.count > 10 ? "\n• ..." : ""
        return AppLocalization.format(
            "Remove %@ tasks from the list only. Downloaded files will not be deleted.\n%@%@%@",
            language: language,
            String(selected.count),
            titles,
            remainder,
            activeNote
        )
    }

    private static func isFolded(
        _ job: DownloadJob,
        groups: [QueueGroup]
    ) -> Bool {
        guard let groupID = QueueJobMetadataPolicy.groupID(
            for: job,
            groups: groups
        ),
        let group = groups.first(where: { $0.id == groupID }) else {
            return false
        }
        return !group.isExpanded
    }
}

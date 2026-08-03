import AppKit
import Combine
import Foundation

enum QueueGroupPromptAction: Equatable {
    case create(jobIDs: Set<UUID>)
    case move(jobIDs: Set<UUID>)
    case rename(groupID: UUID)
}

struct PendingDuplicateAddition: Equatable {
    var source: String
    var title: String
    var metadata: [String: String]
}

@MainActor
final class QueueEditorStore: ObservableObject {
    @Published var infoJob: DownloadJob?
    @Published var pageSelectorJob: DownloadJob?
    @Published var pageSelectorItems: [PageSelectorItem] = []
    @Published var pageSelectorSelectedIndexes: Set<Int> = []
    @Published var pageSelectorRangeText = ""
    @Published var pageSelectorMessage = ""
    @Published var editingCommentJob: DownloadJob?
    @Published var editingCommentJobIDs: [UUID] = []
    @Published var jobCommentText = ""
    @Published var jobPendingRemoval: DownloadJob?
    @Published var jobPendingRemovalIDs: [UUID] = []
    @Published var jobGroupNameDraft = ""
    @Published var jobGroupPending: DownloadJob?
    @Published var queueGroupPendingRemoval: QueueGroup?
    @Published var queueGroupPendingRetry: QueueGroup?
    @Published private(set) var queueGroupPromptAction: QueueGroupPromptAction?
    @Published var outputDeletionJob: DownloadJob?
    @Published var outputDeletionJobIDs: [UUID] = []
    @Published var outputDeletionCandidates: [OutputDeletionCandidate] = []
    @Published var removeJobAfterOutputDeletion = false
    @Published private(set) var pendingIncompleteRetryJobIDs: [UUID] = []
    @Published private(set) var pendingCompletedRemovalJobIDs: [UUID] = []
    @Published private(set) var duplicateAdditionMessage = ""
    @Published var editingJob: DownloadJob?
    @Published var jobEditTitle = ""
    @Published var jobEditSource = ""
    @Published var jobEditInput = ""
    @Published var jobEditOutputPath = ""
    @Published var jobEditArtist = ""
    @Published var jobEditZipFile = ""
    @Published var jobEditStatus: JobStatus = .queued
    @Published var jobEditType = ""
    @Published var jobEditSite = ""
    @Published var jobEditDate = ""
    @Published var jobEditRange = ""
    @Published var jobEditNamesText = ""
    @Published var jobEditComment = ""
    @Published var jobEditThumbnailImage: NSImage?
    @Published var jobEditThumbnailIsCustom = false
    @Published var jobEditThumbnailMessage = "No thumbnail"

    var jobEditThumbnailPNGData: Data?
    var jobEditThumbnailChanged = false
    var jobEditOriginalThumbnailPath = ""
    private(set) var pendingDuplicateAdditions: [PendingDuplicateAddition] = []
    private(set) var pendingDuplicateAdditionStartsQueue = false

    func resetPageSelector() {
        pageSelectorJob = nil
        pageSelectorItems = []
        pageSelectorSelectedIndexes = []
        pageSelectorRangeText = ""
        pageSelectorMessage = ""
    }

    func beginEditingComments(for jobs: [DownloadJob]) {
        guard let first = jobs.first else { return }
        editingCommentJob = first
        editingCommentJobIDs = jobs.map(\.id)
        let comments = Set(jobs.map(\.comment))
        jobCommentText = comments.count == 1 ? first.comment : ""
    }

    func resetCommentEditing() {
        editingCommentJob = nil
        editingCommentJobIDs = []
        jobCommentText = ""
    }

    func beginPendingJobRemoval(_ jobs: [DownloadJob]) {
        jobPendingRemoval = jobs.first
        jobPendingRemovalIDs = jobs.map(\.id)
    }

    func resetPendingJobRemoval() {
        jobPendingRemoval = nil
        jobPendingRemovalIDs = []
    }

    func beginQueueGroupPrompt(
        action: QueueGroupPromptAction,
        pendingJob: DownloadJob?,
        name: String
    ) {
        queueGroupPromptAction = action
        jobGroupPending = pendingJob
        jobGroupNameDraft = name
    }

    func resetQueueGroupPrompt() {
        queueGroupPromptAction = nil
        jobGroupPending = nil
        jobGroupNameDraft = ""
    }

    func queueGroupPromptTitle(language: AppInterfaceLanguage) -> String {
        switch queueGroupPromptAction {
        case .create:
            return AppLocalization.text("New Group", language: language)
        case .move:
            return AppLocalization.text("Move to Group", language: language)
        case .rename:
            return AppLocalization.text("Rename", language: language)
        case nil:
            return AppLocalization.text("Group", language: language)
        }
    }

    func queueGroupPromptButtonTitle(language: AppInterfaceLanguage) -> String {
        switch queueGroupPromptAction {
        case .create:
            return AppLocalization.text("Create", language: language)
        case .move:
            return AppLocalization.text("Move", language: language)
        case .rename:
            return AppLocalization.text("Rename", language: language)
        case nil:
            return AppLocalization.text("OK", language: language)
        }
    }

    func queueGroupPromptMessage(language: AppInterfaceLanguage) -> String {
        switch queueGroupPromptAction {
        case .create(let jobIDs):
            return jobIDs.isEmpty
                ? AppLocalization.text("Enter a name for the empty group.", language: language)
                : AppLocalization.format(
                    "Group the selected %@ tasks into a new group.",
                    language: language,
                    String(jobIDs.count)
                )
        case .move(let jobIDs):
            return AppLocalization.format(
                "Enter a new group name for %@ tasks.",
                language: language,
                String(jobIDs.count)
            )
        case .rename, nil:
            return AppLocalization.text("Enter a group name.", language: language)
        }
    }

    func beginQueueGroupRemoval(_ group: QueueGroup) {
        queueGroupPendingRemoval = group
    }

    func resetQueueGroupRemoval() {
        queueGroupPendingRemoval = nil
    }

    func beginQueueGroupRetry(_ group: QueueGroup) {
        queueGroupPendingRetry = group
    }

    func resetQueueGroupRetry() {
        queueGroupPendingRetry = nil
    }

    func beginOutputDeletion(
        job: DownloadJob?,
        jobIDs: [UUID],
        candidates: [OutputDeletionCandidate],
        removeJobsAfterDeletion: Bool
    ) {
        outputDeletionJob = job
        outputDeletionJobIDs = jobIDs
        outputDeletionCandidates = candidates
        removeJobAfterOutputDeletion = removeJobsAfterDeletion
    }

    func resetOutputDeletion() {
        outputDeletionJob = nil
        outputDeletionJobIDs = []
        outputDeletionCandidates = []
        removeJobAfterOutputDeletion = false
    }

    func pendingOutputDeletionJobCount(in jobs: [DownloadJob]) -> Int {
        let pending = Set(outputDeletionJobIDs)
        return jobs.lazy.filter { pending.contains($0.id) }.count
    }

    func outputDeletionConfirmationTitle(
        jobs: [DownloadJob],
        language: AppInterfaceLanguage
    ) -> String {
        guard removeJobAfterOutputDeletion else {
            return AppLocalization.text(
                "Move downloaded output to the Trash?",
                language: language
            )
        }
        let count = pendingOutputDeletionJobCount(in: jobs)
        return count > 1
            ? AppLocalization.format(
                "Delete %@ tasks and their downloaded files?",
                language: language,
                String(count)
            )
            : AppLocalization.text(
                "Delete the task and downloaded files?",
                language: language
            )
    }

    func outputDeletionDestructiveTitle(
        jobs: [DownloadJob],
        language: AppInterfaceLanguage
    ) -> String {
        let count = pendingOutputDeletionJobCount(in: jobs)
        return count > 1
            ? AppLocalization.format(
                "Delete %@ Tasks and All Downloaded Files",
                language: language,
                String(count)
            )
            : AppLocalization.text(
                "Delete Task and All Downloaded Files",
                language: language
            )
    }

    func outputDeletionConfirmationMessage(
        jobs: [DownloadJob],
        language: AppInterfaceLanguage
    ) -> String {
        guard removeJobAfterOutputDeletion else {
            return AppLocalization.text(
                "Choose downloaded output to move to the Trash. The task will remain in the list.",
                language: language
            )
        }

        let pending = Set(outputDeletionJobIDs)
        let selected = jobs.filter { pending.contains($0.id) }
        let heading = selected.count == 1
            ? AppLocalization.text(
                "Move all downloaded output to the macOS Trash and remove this task from the list.",
                language: language
            )
            : AppLocalization.format(
                "Move downloaded output for %@ selected tasks to the macOS Trash and remove them from the list.",
                language: language,
                String(selected.count)
            )
        let activeNote = selected.contains(where: {
            $0.status == .resolving || $0.status == .downloading
        })
            ? AppLocalization.text(
                "\nActive downloads will be cancelled immediately. Output downloaded so far will be moved to the Trash before removal.",
                language: language
            )
            : ""
        let titles = selected.prefix(10).map { job in
            "• \(job.title.trimmed.isEmpty ? job.source : job.title)"
        }.joined(separator: "\n")
        let remainder = selected.count > 10 ? "\n• ..." : ""
        return titles.isEmpty
            ? "\(heading)\(activeNote)"
            : "\(heading)\n\(titles)\(remainder)\(activeNote)"
    }

    func beginIncompleteRetry(jobIDs: [UUID]) {
        pendingIncompleteRetryJobIDs = jobIDs
    }

    func resetIncompleteRetry() {
        pendingIncompleteRetryJobIDs = []
    }

    func retryIncompleteJobsConfirmationMessage(
        language: AppInterfaceLanguage
    ) -> String {
        if pendingIncompleteRetryJobIDs.count == 1 {
            return AppLocalization.text(
                "Restart 1 incomplete task.",
                language: language
            )
        }
        return AppLocalization.format(
            "Restart %@ incomplete tasks.",
            language: language,
            String(pendingIncompleteRetryJobIDs.count)
        )
    }

    func beginCompletedRemoval(jobIDs: [UUID]) {
        pendingCompletedRemovalJobIDs = jobIDs
    }

    func resetCompletedRemoval() {
        pendingCompletedRemovalJobIDs = []
    }

    func completedJobsRemovalConfirmationMessage(
        language: AppInterfaceLanguage
    ) -> String {
        if pendingCompletedRemovalJobIDs.count == 1 {
            return AppLocalization.text(
                "Remove 1 completed task from the list.",
                language: language
            )
        }
        return AppLocalization.format(
            "Remove %@ completed tasks from the list.",
            language: language,
            String(pendingCompletedRemovalJobIDs.count)
        )
    }

    var pendingDuplicateAdditionCount: Int {
        pendingDuplicateAdditions.count
    }

    func beginDuplicateAdditionConfirmation(
        _ pending: [PendingDuplicateAddition],
        message: String
    ) {
        pendingDuplicateAdditions = pending
        pendingDuplicateAdditionStartsQueue = false
        duplicateAdditionMessage = message
    }

    func requestQueueStartAfterDuplicateAddition() {
        pendingDuplicateAdditionStartsQueue = true
    }

    func consumeDuplicateAdditions() -> (
        additions: [PendingDuplicateAddition],
        shouldStartQueue: Bool
    ) {
        let result = (
            additions: pendingDuplicateAdditions,
            shouldStartQueue: pendingDuplicateAdditionStartsQueue
        )
        resetDuplicateAdditionConfirmation()
        return result
    }

    @discardableResult
    func cancelDuplicateAdditionConfirmation() -> Int {
        let count = pendingDuplicateAdditions.count
        resetDuplicateAdditionConfirmation()
        return count
    }

    private func resetDuplicateAdditionConfirmation() {
        pendingDuplicateAdditions = []
        pendingDuplicateAdditionStartsQueue = false
        duplicateAdditionMessage = ""
    }

    func beginEditingJob(
        _ job: DownloadJob,
        namesText: String
    ) {
        editingJob = job
        jobEditTitle = job.title
        jobEditSource = job.source
        jobEditInput =
            job.metadata["input"] ??
            job.metadata["input_url"] ??
            job.metadata["source_input_url"] ??
            job.source
        jobEditOutputPath = job.outputPath
        jobEditArtist =
            job.metadata["artist"] ??
            job.metadata["artists"] ??
            job.metadata["author"] ??
            ""
        jobEditZipFile =
            job.metadata["zipfile"] ??
            job.metadata["zip"] ??
            job.metadata["archive"] ??
            ""
        jobEditStatus = job.status
        jobEditType =
            job.metadata["type"] ??
            job.metadata["category"] ??
            job.metadata["media_type"] ??
            ""
        jobEditSite =
            job.metadata["site"] ??
            job.metadata["host"] ??
            job.metadata["domain"] ??
            ""
        jobEditDate =
            job.metadata["date"] ??
            job.metadata["upload_date"] ??
            job.metadata["download_completed_at"] ??
            ""
        jobEditRange = job.rangeExpression
        jobEditNamesText = namesText
        jobEditComment = job.comment
        jobEditThumbnailPNGData = nil
        jobEditThumbnailChanged = false
        jobEditOriginalThumbnailPath =
            job.metadata[QueueThumbnailProvider.customThumbnailMetadataKey]?
                .trimmed ?? ""
        jobEditThumbnailIsCustom = !jobEditOriginalThumbnailPath.isEmpty
        jobEditThumbnailImage = nil
        jobEditThumbnailMessage = jobEditThumbnailIsCustom
            ? "Custom thumbnail"
            : "Loading thumbnail"
    }

    func resetJobEditing() {
        editingJob = nil
        jobEditTitle = ""
        jobEditSource = ""
        jobEditInput = ""
        jobEditOutputPath = ""
        jobEditArtist = ""
        jobEditZipFile = ""
        jobEditStatus = .queued
        jobEditType = ""
        jobEditSite = ""
        jobEditDate = ""
        jobEditRange = ""
        jobEditNamesText = ""
        jobEditComment = ""
        jobEditThumbnailImage = nil
        jobEditThumbnailIsCustom = false
        jobEditThumbnailMessage = "No thumbnail"
        jobEditThumbnailPNGData = nil
        jobEditThumbnailChanged = false
        jobEditOriginalThumbnailPath = ""
    }
}

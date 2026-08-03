import AppKit
import SwiftUI

@MainActor
struct ManagedQueueJobRow: View {
    let manager: DownloadManager
    @Environment(\.appNavigationCommands) private var navigation
    @ObservedObject var presentation: AppPresentationStore
    @ObservedObject var settingsStore: SettingsStore
    @ObservedObject var queueStore: QueueStore
    @ObservedObject var queueEditorStore: QueueEditorStore
    let job: DownloadJob
    let viewMode: QueueViewMode
    let groupOptions: [QueueGroup]
    let retryableIncompleteJobCount: Int
    let removableCompletedJobCount: Int
    let requestRemove: () -> Void
    let selectIconJob: () -> Void

    var body: some View {
        JobRow(
            job: job,
            isSelected: presentation.selectedJobIDs.contains(job.id),
            queueIsPaused: !queueStore.isQueueEnabled,
            showsDownloadDate: settingsStore.showDownloadDate,
            statusColorPalette: settingsStore.jobStatusColorPalette,
            groupOptions: groupOptions,
            currentGroupID: manager.jobGroupID(for: job),
            destinationPath: settingsStore.destinationPath,
            viewMode: viewMode,
            showsThumbnail: !settingsStore.queueThumbnailsHidden,
            thumbnailScale: settingsStore.queueThumbnailScale,
            hideArchiveIndicatorWhenFileMissing: settingsStore.hideArchiveIndicatorWhenFileMissing,
            actions: JobRowActions(
                reveal: {
                    manager.revealOutputs(startingAt: job)
                },
                openFirstOutput: {
            manager.openFirstOutputFile(for: job)
                },
                openArchive: {
            manager.openArchiveOutput(for: job)
                },
                openFirstSelectedOutputs: {
            manager.openFirstOutputFiles(startingAt: job)
                },
                viewOutputInBrowser: {
            manager.openOutputBrowserView(startingAt: job)
                },
                previewOutput: {
            manager.openOutputPreview(for: job)
                },
                createPDF: {
            manager.createPDF(for: job)
                },
                retry: {
            manager.retryJobs(startingAt: job)
                },
                directDownload: {
            manager.directDownloadJobs(startingAt: job)
                },
                stopLiveRecording: {
            manager.stopLiveRecording(for: job)
                },
                pauseAria2: {
            manager.pauseAria2(for: job)
                },
                resumeAria2: {
            manager.resumeAria2(for: job)
                },
                applyAria2Limits: {
            manager.applyCurrentAria2RuntimeLimits(for: job)
                },
                applyAria2Files: {
            manager.applyCurrentAria2RuntimeFileSelection(for: job)
                },
                applyAria2Seeding: {
            manager.applyCurrentAria2RuntimeSeeding(for: job)
                },
                previewAria2Files: {
            manager.previewAria2Files(for: job)
                },
                refreshAria2Peers: {
            manager.refreshAria2Peers(for: job)
                },
                markFinished: {
            manager.markJobsFinished(startingAt: job)
                },
                moveUp: {
            manager.moveJobUp(job)
                },
                moveDown: {
            manager.moveJobDown(job)
                },
                moveOutput: {
            manager.beginMovingOutputs(startingAt: job)
                },
                deleteJobAndOutput: {
            manager.beginDeletingOutputs(startingAt: job)
                },
                deleteOutput: {
            manager.beginDeletingOutput(for: job)
                },
                remove: {
            requestRemove()
                },
                copySource: {
            manager.copySource(for: job)
                },
                copyArtist: {
            manager.copyArtistName(for: job)
                },
                openSource: {
            manager.openSource(for: job)
                },
                openAccessHelp: {
            manager.openAccessHelp(for: job)
                },
                info: {
            queueEditorStore.infoJob = job
                },
                selectForContextMenu: {
            let eventType = NSApp.currentEvent?.type
            if viewMode == .icon && (eventType == .leftMouseDown || eventType == .leftMouseUp) {
                selectIconJob()
            } else if !presentation.selectedJobIDs.contains(job.id) {
                manager.setSelectedJobIDs([job.id])
            }
                },
                edit: {
            manager.beginEditingJob(job)
                },
                pages: {
            manager.beginPageSelector(for: job)
                },
                comment: {
            manager.beginEditingJobComment(job)
                },
                togglePin: {
            manager.toggleJobPins(startingAt: job)
                },
                toggleLock: {
            manager.toggleJobLocks(startingAt: job)
                },
                pinActionWillPin: {
            manager.jobPinActionWillPin(startingAt: job)
                },
                lockActionWillLock: {
            manager.jobLockActionWillLock(startingAt: job)
                },
                canToggleSelectedPins: {
            manager.canToggleJobPins(startingAt: job)
                },
                retryIncomplete: {
            manager.beginRetryIncompleteJobs()
                },
                clearCompleted: {
            manager.beginRemovingCompletedJobs()
                },
                isTagChecked: { tag in
            manager.isJobTagChecked(tag, for: job)
                },
                toggleTag: { tag in
            manager.toggleJobTag(tag, for: job)
                },
                tagName: { tag in
            settingsStore.taskTagDisplayName(tag)
                },
                openTagSettings: {
            navigation.openSettings(.theme)
                },
                convertImages: {
            manager.beginConvertingImages(startingAt: job)
                },
                moveToGroup: { groupID in
            let ids = presentation.selectedJobIDs.contains(job.id)
                ? presentation.selectedJobIDs
                : Set([job.id])
            _ = manager.moveJobs(ids, toQueueGroup: groupID)
                },
                moveToNewGroup: {
            manager.beginMovingJobToNewGroup(job)
                },
                beginReorder: {
            let ids = manager.queueJobIDsForDrag(startingAt: job.id)
            presentation.draggedQueueJobIDs = ids
            return QueueDropTypes.jobPasteboardItem(for: job.id)
                },
                endReorder: {
            manager.endQueueDrag()
                },
                canBeginReorder: {
            viewMode == .list &&
                settingsStore.queueSortMode == .manual &&
                presentation.queueFilter.trimmed.isEmpty &&
                queueStore.jobs.filter { $0.isPinned == job.isPinned }.count > 1
                },
                canMoveToGroup: {
            settingsStore.queueSortMode == .manual &&
                !queueStore.isRunning &&
                job.status != .resolving &&
                job.status != .downloading
                },
                canMoveUp: {
            manager.canMoveJobUp(job)
                },
                canMoveDown: {
            manager.canMoveJobDown(job)
                },
                canPauseAria2: {
            manager.canPauseAria2(for: job)
                },
                canResumeAria2: {
            manager.canResumeAria2(for: job)
                },
                canApplyAria2Limits: {
            manager.canApplyAria2RuntimeLimits(for: job)
                },
                canApplyAria2Files: {
            manager.canApplyAria2RuntimeFileSelection(for: job)
                },
                canApplyAria2Seeding: {
            manager.canApplyAria2RuntimeSeeding(for: job)
                },
                canPreviewAria2Files: {
            manager.canPreviewAria2Files(for: job)
                },
                canRefreshAria2Peers: {
            manager.canRefreshAria2Peers(for: job)
                },
                canMarkFinished: {
            manager.canMarkJobsFinished(startingAt: job)
                },
                canOpenPageSelector: {
            manager.canOpenPageSelector(for: job)
                },
                canDeleteOutput: {
            manager.canDeleteOutput(for: job)
                },
                canOpenFirstOutput: {
            manager.canOpenFirstOutputFile(for: job)
                },
                canOpenFirstSelectedOutputs: {
            manager.canOpenFirstOutputFiles(startingAt: job)
                },
                canViewOutputInBrowser: {
            manager.canOpenOutputBrowserView(startingAt: job)
                },
                canPreviewOutput: {
            manager.canOpenOutputPreview(for: job)
                },
                canCreatePDF: {
            manager.canCreatePDF(for: job)
                },
                canDirectDownload: {
            manager.canDirectDownloadJobs(startingAt: job)
                },
                canStopLiveRecording: {
            manager.canStopLiveRecording(for: job)
                },
                canMoveOutput: {
            manager.canMoveOutputs(startingAt: job)
                },
                canConvertImages: {
            manager.canConvertJobImages(startingAt: job)
                },
                canCopyArtist: {
            manager.artistName(for: job) != nil
                },
                canRetryIncomplete: {
            retryableIncompleteJobCount > 0
                },
                canClearCompleted: {
            removableCompletedJobCount > 0
                },
                canRevealSelectedOutputs: {
            manager.canRevealOutputs(startingAt: job)
                },
                canDeleteSelectedJobsAndOutput: {
            manager.canDeleteOutputsAndJobs(startingAt: job)
                },
                canRemoveSelectedJobs: {
            manager.canRemoveJobs(startingAt: job)
                },
                canRetrySelectedJobs: {
            manager.canRetryJobs(startingAt: job)
                }
            )
        )
    }
}

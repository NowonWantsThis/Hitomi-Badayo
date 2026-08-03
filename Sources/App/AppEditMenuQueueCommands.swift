import Foundation

@MainActor
extension DownloadManager {
    var canCopyEditMenuSelection: Bool {
        !editMenuSelectedJobs
            .map(\.source)
            .map(\.trimmed)
            .filter { !$0.isEmpty }
            .isEmpty
    }

    @discardableResult
    func copyEditMenuSelection() -> Bool {
        var seen = Set<String>()
        let sources = editMenuSelectedJobs.compactMap { job -> String? in
            let source = job.source.trimmed
            guard !source.isEmpty, seen.insert(source).inserted else {
                return nil
            }
            return source
        }
        guard !sources.isEmpty else { return false }

        let copied = clipboardCommandService.copyText(
            sources.joined(separator: "\n")
        )
        appStatusStore.setSummary(copied ? "URL copied" : "Copy failed")
        return copied
    }

    var canPasteEditMenuURLs: Bool {
        !(clipboardCommandService.inputText()?.trimmed.isEmpty ?? true)
    }

    @discardableResult
    func pasteEditMenuURLs() -> Bool {
        pasteAndDownloadURLs()
    }

    var canRemoveEditMenuSelection: Bool {
        editMenuSelectedJobs.contains {
            !$0.isLocked && !QueueJobMetadataPolicy.isPendingRemoval($0)
        }
    }

    @discardableResult
    func beginRemovingEditMenuSelection() -> Bool {
        guard let first = editMenuSelectedJobs.first,
              canRemoveEditMenuSelection else {
            return false
        }
        beginRemovingJobs(startingAt: first)
        return true
    }

    var canSelectAllVisibleJobsFromEditMenu: Bool {
        !editMenuVisibleJobIDs.isEmpty
    }

    @discardableResult
    func selectAllVisibleJobsFromEditMenu() -> Bool {
        let ids = editMenuVisibleJobIDs
        guard !ids.isEmpty else { return false }
        setSelectedJobIDs(ids)
        return true
    }

    private var editMenuSelectedJobs: [DownloadJob] {
        let selectedIDs = presentation.selectedJobIDs
        guard !selectedIDs.isEmpty else { return [] }
        return queueStore.jobs.filter { selectedIDs.contains($0.id) }
    }

    private var editMenuVisibleJobIDs: Set<UUID> {
        let snapshot = QueuePresentationReadModelService.snapshot(
            jobs: queueStore.jobs,
            groups: queueStore.queueGroups,
            scheduler: queueScheduler,
            query: presentation.queueFilter,
            sortMode: settingsStore.queueSortMode,
            descending: settingsStore.queueSortDescending,
            selectedJobIDs: presentation.selectedJobIDs,
            pendingRemovalIDs: queueEditorStore.jobPendingRemovalIDs,
            language: settingsStore.interfaceLanguage
        )
        return Set(snapshot.filteredJobs.map(\.id))
    }
}

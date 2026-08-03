import Foundation

@MainActor
struct TextViewerReadModelService {
    private let outputContentFileService: OutputContentFileService
    private let contentService: TextViewerContentService
    private let selectionService: TextViewerSelectionService

    init() {
        self.init(
            outputContentFileService: OutputContentFileService(),
            contentService: TextViewerContentService(),
            selectionService: TextViewerSelectionService()
        )
    }

    init(
        outputContentFileService: OutputContentFileService,
        contentService: TextViewerContentService,
        selectionService: TextViewerSelectionService
    ) {
        self.outputContentFileService = outputContentFileService
        self.contentService = contentService
        self.selectionService = selectionService
    }

    func entries(for jobs: [DownloadJob]) -> [TextViewerEntry] {
        jobs.flatMap { job in
            contentService.entries(
                for: job,
                files: contentFiles(for: job)
            )
        }
    }

    func visibleEntries(
        for jobs: [DownloadJob],
        filter: String
    ) -> [TextViewerEntry] {
        selectionService.visibleEntries(
            in: entries(for: jobs),
            filter: filter
        )
    }

    func ensuredSelectionID(
        for jobs: [DownloadJob],
        filter: String,
        currentSelectionID: String
    ) -> String {
        selectionService.ensuredSelectionID(
            in: visibleEntries(for: jobs, filter: filter),
            currentSelectionID: currentSelectionID
        )
    }

    func selectedEntry(
        for jobs: [DownloadJob],
        filter: String,
        selectedEntryID: String
    ) -> TextViewerEntry? {
        let entries = entries(for: jobs)
        let visibleEntries = selectionService.visibleEntries(
            in: entries,
            filter: filter
        )
        return selectionService.selectedEntry(
            in: entries,
            visibleEntries: visibleEntries,
            selectedEntryID: selectedEntryID
        )
    }

    func selectedDocument(
        for jobs: [DownloadJob],
        filter: String,
        selectedEntryID: String,
        limit: Int = 1_048_576
    ) -> TextViewerDocument {
        guard let entry = selectedEntry(
            for: jobs,
            filter: filter,
            selectedEntryID: selectedEntryID
        ) else {
            return TextViewerDocument(
                entry: nil,
                text: "",
                bytesRead: 0,
                byteCount: 0,
                truncated: false,
                errorMessage: nil
            )
        }
        let job = jobs.first { $0.id == entry.jobID }
        return contentService.document(
            for: entry,
            job: job,
            files: job.map(contentFiles(for:)) ?? [],
            limit: limit
        )
    }

    func rawFiles(
        for entry: TextViewerEntry?,
        jobs: [DownloadJob]
    ) -> [TextViewerRawFile]? {
        guard let entry,
              let job = jobs.first(where: { $0.id == entry.jobID }) else {
            return nil
        }
        return outputContentFileService.files(at: job.outputPath).map {
            TextViewerRawFile(
                originalIndex: $0.originalIndex,
                url: $0.url,
                isArchiveEntry: $0.archiveEntry != nil
            )
        }
    }

    private func contentFiles(
        for job: DownloadJob
    ) -> [TextViewerContentFile] {
        outputContentFileService.textCandidateFiles(
            in: outputContentFileService.files(at: job.outputPath)
        ).map { file in
            TextViewerContentFile(
                originalIndex: file.originalIndex,
                relativePath: file.relativePath,
                detail: file.archiveEntry == nil
                    ? OutputContentFileService.displayPath(file)
                    : "Archive entry",
                byteCount: OutputContentFileService.fileSize(file)
            ) { [outputContentFileService] limit in
                let read = try outputContentFileService.readTextFile(
                    file,
                    limit: limit
                )
                return TextViewerContentReadResult(
                    text: read.text,
                    bytesRead: read.bytesRead,
                    truncated: read.truncated
                )
            }
        }
    }
}

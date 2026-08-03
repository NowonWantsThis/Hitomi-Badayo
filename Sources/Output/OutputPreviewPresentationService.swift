import Foundation

struct OutputPreviewPresentationSnapshot {
    let job: DownloadJob?
    let title: String
    let summary: String
    let selectedFile: OutputPreviewFile?
    let imageFiles: [OutputPreviewFile]
}

enum OutputPreviewPresentationService {
    static func snapshot(
        jobs: [DownloadJob],
        selectedJobID: UUID?,
        files: [OutputPreviewFile],
        selectedFileIndex: Int,
        isLoading: Bool
    ) -> OutputPreviewPresentationSnapshot {
        let job = selectedJobID.flatMap { id in
            jobs.first { $0.id == id }
        }
        let imageFiles = files.filter(\.isImage)
        let selectedFile = files.first {
            $0.originalIndex == selectedFileIndex
        } ?? files.first
        let title: String
        if let job {
            title = job.title.trimmed.isEmpty ? job.source : job.title
        } else {
            title = "Output Preview"
        }
        let summary: String
        if let job {
            if isLoading {
                summary = "Scanning output..."
            } else {
                let archiveText = files.contains { $0.isArchiveEntry }
                    ? " · archive"
                    : ""
                summary =
                    "\(job.status.rawValue) · \(files.count) files · " +
                    "\(imageFiles.count) images\(archiveText)"
            }
        } else {
            summary = "No task selected"
        }

        return OutputPreviewPresentationSnapshot(
            job: job,
            title: title,
            summary: summary,
            selectedFile: selectedFile,
            imageFiles: imageFiles
        )
    }
}

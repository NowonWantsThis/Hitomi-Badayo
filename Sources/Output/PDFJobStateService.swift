import Foundation

final class PDFJobStateService {
    func recordingCreatedPDF(
        _ job: DownloadJob,
        pdfURL: URL,
        createdAt: String
    ) -> DownloadJob {
        var updated = job
        updated.metadata["pdf_path"] = pdfURL.path
        updated.metadata["pdf_created_at"] = createdAt
        updated.message = "PDF created"
        return updated
    }
}

import Foundation

struct TextViewerContentReadResult {
    var text: String
    var bytesRead: Int
    var truncated: Bool
}

struct TextViewerContentFile {
    var originalIndex: Int
    var relativePath: String
    var detail: String
    var byteCount: Int
    var read:
        @MainActor (Int) throws ->
            TextViewerContentReadResult
}

@MainActor
struct TextViewerContentService {
    func entries(
        for job: DownloadJob,
        files: [TextViewerContentFile]
    ) -> [TextViewerEntry] {
        var entries = files.map { file in
            TextViewerEntry(
                id: "\(job.id.uuidString):file:\(file.originalIndex)",
                jobID: job.id,
                fileIndex: file.originalIndex,
                kind: .file,
                title: job.title.isEmpty ? job.source : job.title,
                source: job.source,
                status: job.status,
                displayName: file.relativePath,
                detail: file.detail,
                byteCount: file.byteCount
            )
        }

        if !job.message.trimmed.isEmpty ||
            !job.comment.trimmed.isEmpty {
            let text = messageText(for: job)
            entries.append(
                TextViewerEntry(
                    id: "\(job.id.uuidString):message",
                    jobID: job.id,
                    fileIndex: nil,
                    kind: .message,
                    title:
                        job.title.isEmpty
                        ? job.source
                        : job.title,
                    source: job.source,
                    status: job.status,
                    displayName: "Task Messages",
                    detail:
                        job.message.trimmed.isEmpty
                        ? "Comment"
                        : "Message",
                    byteCount: text.utf8.count
                )
            )
        }

        return entries
    }

    func document(
        for entry: TextViewerEntry,
        job: DownloadJob?,
        files: [TextViewerContentFile],
        limit: Int
    ) -> TextViewerDocument {
        guard let job else {
            return TextViewerDocument(
                entry: entry,
                text: "",
                bytesRead: 0,
                byteCount: 0,
                truncated: false,
                errorMessage: "Task not found"
            )
        }

        if let fileIndex = entry.fileIndex {
            guard let file = files.first(where: {
                $0.originalIndex == fileIndex
            }) else {
                return TextViewerDocument(
                    entry: entry,
                    text: "",
                    bytesRead: 0,
                    byteCount: 0,
                    truncated: false,
                    errorMessage: "Text file not found"
                )
            }
            do {
                let read = try file.read(limit)
                return TextViewerDocument(
                    entry: entry,
                    text: read.text,
                    bytesRead: read.bytesRead,
                    byteCount: file.byteCount,
                    truncated: read.truncated,
                    errorMessage: nil
                )
            } catch {
                return TextViewerDocument(
                    entry: entry,
                    text: "",
                    bytesRead: 0,
                    byteCount: file.byteCount,
                    truncated: false,
                    errorMessage:
                        AppLocalization.errorText(error)
                )
            }
        }

        let text = messageText(for: job)
        return TextViewerDocument(
            entry: entry,
            text: text,
            bytesRead: text.utf8.count,
            byteCount: text.utf8.count,
            truncated: false,
            errorMessage: nil
        )
    }

    func messageText(for job: DownloadJob) -> String {
        [
            job.message.trimmed.isEmpty
                ? nil
                : "Message: \(job.message.trimmed)",
            job.comment.trimmed.isEmpty
                ? nil
                : "Comment: \(job.comment.trimmed)"
        ]
        .compactMap { $0 }
        .joined(separator: "\n\n")
    }
}

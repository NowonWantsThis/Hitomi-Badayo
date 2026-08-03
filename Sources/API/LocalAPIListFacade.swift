import Foundation

@MainActor
struct LocalAPIListFacade {
    private let pageRenderer: LocalAPIListPageRenderer

    init(pageRenderer: LocalAPIListPageRenderer = LocalAPIListPageRenderer()) {
        self.pageRenderer = pageRenderer
    }

    func page(
        request: LocalHTTPRequest,
        jobs: [DownloadJob],
        outputFiles: (DownloadJob) -> [APIOutputFile],
        fileSize: (APIOutputFile) -> Int,
        modifiedDate: (APIOutputFile) -> Date?
    ) -> String {
        let step = max(
            1,
            min(500, Int(request.query["step"] ?? "") ?? 50)
        )
        let requestedPage = max(
            0,
            Int(request.query["p"] ?? "") ?? 0
        )
        let usesRange = request.query["start"] != nil ||
            request.query["end"] != nil
        let usesPaging = request.query["p"] != nil ||
            request.query["step"] != nil
        let total = jobs.count
        let rangeStart = max(
            0,
            Int(request.query["start"] ?? "") ?? 0
        )
        let rangeEndInclusive = min(
            max(
                0,
                Int(request.query["end"] ?? "") ?? (total - 1)
            ),
            max(0, total - 1)
        )
        let start = usesRange
            ? min(rangeStart, total)
            : (usesPaging ? min(requestedPage * step, total) : 0)
        let end = usesRange
            ? (
                start <= rangeEndInclusive
                    ? min(rangeEndInclusive + 1, total)
                    : start
            )
            : (usesPaging ? min(start + step, total) : total)
        let visible = Array(jobs.enumerated())[start..<end]
        let items = visible.map { index, job in
            let files = outputFiles(job)
            return LocalAPIListPageItem(
                index: index,
                id: job.id,
                status: job.status.rawValue,
                progress: Int(
                    max(0, min(100, job.progress * 100)).rounded()
                ),
                completed: job.completed,
                total: job.total,
                title: job.title,
                source: job.source,
                message: job.message,
                comment: job.comment,
                outputPath: job.outputPath,
                badges: badges(
                    for: job,
                    files: files,
                    fileSize: fileSize,
                    modifiedDate: modifiedDate
                ),
                canCreatePDF: files.contains {
                    OutputContentFileService.imageExtensions.contains(
                        $0.url.pathExtension.lowercased()
                    )
                },
                canCreateZIP: LocalAPIOutputCommandService
                    .canArchiveOutputPath(job.outputPath)
            )
        }
        return pageRenderer.page(
            password: password(from: request),
            state: LocalAPIListPageState(
                items: Array(items),
                totalCount: total,
                usesRange: usesRange,
                usesPaging: usesPaging,
                requestedPage: requestedPage,
                step: step,
                singleMode: LocalAPIRequestDecoder.truthy(
                    request.query["single"]
                )
            )
        )
    }

    private func badges(
        for job: DownloadJob,
        files: [APIOutputFile],
        fileSize: (APIOutputFile) -> Int,
        modifiedDate: (APIOutputFile) -> Date?
    ) -> [String] {
        var badges: [String] = []
        var seen = Set<String>()

        func append(_ value: String?) {
            guard let value = value?.trimmed, !value.isEmpty else { return }
            let normalized = value.lowercased()
            guard seen.insert(normalized).inserted else { return }
            badges.append(value)
        }

        let metadata = job.metadata
        if job.isPinned { append("Pinned") }
        if job.isLocked { append("Locked") }
        append(
            Self.firstMetadataValue(
                metadata,
                keys: [
                    "artist", "author", "creator", "uploader", "channel",
                    "username", "user"
                ]
            )
        )
        append(
            Self.firstMetadataValue(
                metadata,
                keys: [
                    "language", "category", "tag", "tags", "series",
                    "site", "type"
                ]
            )
        )

        if !files.isEmpty {
            append("\(files.count) file\(files.count == 1 ? "" : "s")")
            let size = files.reduce(Int64(0)) {
                $0 + Int64(max(0, fileSize($1)))
            }
            if size > 0 { append(Self.byteCountString(size)) }
            if let date = files.compactMap(modifiedDate).max() {
                append(Self.listDateString(date))
            }
        } else {
            append(
                Self.firstMetadataValue(
                    metadata,
                    keys: [
                        "date", "upload_date", "published_date", "published",
                        "created_at"
                    ]
                )
            )
        }
        return badges
    }

    private static func firstMetadataValue(
        _ metadata: [String: String],
        keys: [String]
    ) -> String? {
        for key in keys {
            if let value = metadata[key]?.trimmed, !value.isEmpty {
                return value
            }
        }
        return nil
    }

    private static func byteCountString(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }

    private static func listDateString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private func password(from request: LocalHTTPRequest) -> String {
        request.query["pw"] ?? request.query["password"] ?? ""
    }
}

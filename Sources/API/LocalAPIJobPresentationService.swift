import Foundation

struct LocalAPIJobRuntimePresentation {
    var isPaused: Bool
    var handler: String
    var canLimit: Bool
    var canSelectFiles: Bool
    var canSeed: Bool
    var canListFiles: Bool
    var canShowPeers: Bool
}

@MainActor
struct LocalAPIJobPresentationService {
    func objects(
        jobs: [DownloadJob],
        in range: Range<Int>,
        runtime: (DownloadJob) -> LocalAPIJobRuntimePresentation
    ) -> [[String: Any]] {
        range.map { index in
            let job = jobs[index]
            let runtime = runtime(job)
            var object: [String: Any] = [
                "id": job.id.uuidString,
                "source": job.source,
                "title": job.title,
                "status": job.status.rawValue,
                "progress": job.progress,
                "completed": job.completed,
                "total": job.total,
                "message": job.message,
                "comment": job.comment,
                "range": job.rangeExpression,
                "outputPath": job.outputPath,
                "pinned": job.isPinned,
                "locked": job.isLocked,
                "runtimePaused": runtime.isPaused,
                "runtimeHandler": runtime.handler,
                "runtimeCanLimit": runtime.canLimit,
                "runtimeCanSelectFiles": runtime.canSelectFiles,
                "runtimeCanSeed": runtime.canSeed,
                "runtimeCanListFiles": runtime.canListFiles,
                "runtimeCanShowPeers": runtime.canShowPeers,
                "runtimeSelectedFiles": job.metadata["runtime_selected_files"] ?? job.metadata["selected_files"] ?? "",
                "runtimeMaxDownloadLimit": job.metadata["runtime_max_download_limit"] ?? job.metadata["max_download_limit"] ?? "",
                "runtimeMaxUploadLimit": job.metadata["runtime_max_upload_limit"] ?? job.metadata["max_upload_limit"] ?? "",
                "runtimeSeedTimeMinutes": job.metadata["runtime_seed_time_minutes"] ?? job.metadata["seed_time_minutes"] ?? "",
                "runtimeSeedRatio": job.metadata["runtime_seed_ratio"] ?? job.metadata["seed_ratio"] ?? "",
                "runtimeFileCount": job.metadata["aria2_file_count"] ?? "",
                "runtimePeerCount": job.metadata["aria2_peer_count"] ?? "",
                "metadata": job.metadata
            ]
            object["displayStatus"] = job.statusAPIValue
            object["partialFailure"] = job.partialFailureCounts != nil
            if let counts = job.partialFailureCounts {
                object["successfulFiles"] = counts.succeeded
                object["failedFiles"] = counts.failed
                object["totalFiles"] = counts.total
            }
            let legacy = OriginalHDT.lightTaskObject(
                job,
                pageCount: max(job.completed, job.total)
            )
            for (key, value) in legacy where object[key] == nil {
                object[key] = value
            }
            return object
        }
    }

    func infoObject(
        job: DownloadJob,
        index: Int,
        auth: String,
        files: [APIOutputFile],
        chapters: [APIChapterGroup],
        pdfAvailable: Bool
    ) -> [String: Any] {
        let uid = job.id.uuidString
        let imageIndexes = files.enumerated()
            .filter {
                OutputContentFileService.imageExtensions.contains(
                    $0.element.url.pathExtension.lowercased()
                )
            }
            .map(\.offset)
        let readerURL: Any = imageIndexes.isEmpty
            ? NSNull()
            : "/view?uid=\(uid)&mode=book&page=0\(auth)"

        var object: [String: Any] = [
            "index": index,
            "id": uid,
            "source": job.source,
            "title": job.title,
            "status": job.status.rawValue,
            "progress": job.progress,
            "completed": job.completed,
            "total": job.total,
            "message": job.message,
            "comment": job.comment,
            "range": job.rangeExpression,
            "outputPath": job.outputPath,
            "pinned": job.isPinned,
            "locked": job.isLocked,
            "tags": TaskTagColor.normalizedRawValues(job.tags),
            "metadata": job.metadata,
            "fileCount": files.count,
            "imageCount": imageIndexes.count,
            "files": fileObjects(files, uid: uid, auth: auth),
            "chapters": chapterObjects(
                chapters,
                files: files,
                uid: uid,
                auth: auth
            ),
            "reader": [
                "available": !imageIndexes.isEmpty,
                "imageCount": imageIndexes.count,
                "imageIndexes": imageIndexes,
                "firstPage": readerURL
            ],
            "links": [
                "view": "/view?uid=\(uid)\(auth)",
                "reader": readerURL,
                "pageSelector": "/page_selector?uid=\(uid)\(auth)",
                "pageSelectorAPI": "/api/page_selector?uid=\(uid)\(auth)",
                "pdf": "/pdf?uid=\(uid)\(auth)",
                "pdfDownload": "/pdf?uid=\(uid)&download=1\(auth)",
                "zip": "/zip?uid=\(uid)\(auth)",
                "zipDownload": "/zip?uid=\(uid)&download=1\(auth)",
                "archive": "/archive?uid=\(uid)\(auth)",
                "archiveDownload": "/archive?uid=\(uid)&download=1\(auth)"
            ]
        ]

        if files.isEmpty {
            object["chapters"] = []
        }
        object["pdf"] = [
            "available": pdfAvailable,
            "create": "/pdf?uid=\(uid)\(auth)",
            "download": "/pdf?uid=\(uid)&download=1\(auth)"
        ]
        object["archive"] = [
            "available": LocalAPIOutputCommandService.canArchiveOutputPath(
                job.outputPath
            ),
            "zip": "/zip?uid=\(uid)\(auth)",
            "zipDownload": "/zip?uid=\(uid)&download=1\(auth)",
            "cbz": "/cbz?uid=\(uid)\(auth)",
            "cbzDownload": "/cbz?uid=\(uid)&download=1\(auth)"
        ]
        return object
    }

    private func fileObjects(
        _ files: [APIOutputFile],
        uid: String,
        auth: String
    ) -> [[String: Any]] {
        files.enumerated().map { index, file in
            let type = SourceInputClassificationService.mediaType(
                for: file.url
            )
            var object: [String: Any] = [
                "index": index,
                "name": OutputContentFileService.displayName(file),
                "relativePath": file.relativePath,
                "path": OutputContentFileService.displayPath(file),
                "type": type,
                "mimeType": OutputFileHTTPResponseService.mimeType(
                    for: file.url
                ),
                "size": OutputContentFileService.fileSize(file),
                "modifiedAt": OutputContentFileService.modifiedDate(file)
                    .map(Self.dateString) ?? NSNull(),
                "file": "/file?uid=\(uid)&index=\(index)\(auth)",
                "download": "/file?uid=\(uid)&index=\(index)&download=1\(auth)",
                "view": "/view?uid=\(uid)&index=\(index)\(auth)"
            ]
            if let archiveURL = file.archiveURL {
                object["archivePath"] = archiveURL.path
                object["archiveEntry"] = file.relativePath
            }
            if type == "image" || type == "video" {
                object["thumb"] = "/thumb?uid=\(uid)&index=\(index)\(auth)"
            }
            return object
        }
    }

    private func chapterObjects(
        _ chapters: [APIChapterGroup],
        files: [APIOutputFile],
        uid: String,
        auth: String
    ) -> [[String: Any]] {
        chapters.enumerated().map { chapterIndex, group in
            let imageCount = group.indexes.filter {
                OutputContentFileService.imageExtensions.contains(
                    files[$0].url.pathExtension.lowercased()
                )
            }.count
            let start = group.indexes.first ?? 0
            let end = group.indexes.last ?? 0
            let title = Self.queryComponent(group.title)
            var object: [String: Any] = [
                "index": chapterIndex,
                "title": group.title,
                "path": group.path,
                "startIndex": start,
                "endIndex": end,
                "count": group.indexes.count,
                "imageCount": imageCount,
                "fileIndexes": group.indexes,
                "view": "/view?uid=\(uid)&start=\(start)&end=\(end)\(auth)&title=\(title)",
                "chapterView": "/view?uid=\(uid)&start_chapter=\(chapterIndex)&end_chapter=\(chapterIndex)\(auth)&title=\(title)"
            ]
            if imageCount > 0 {
                object["reader"] = "/view?uid=\(uid)&mode=book&page=0&start=\(start)&end=\(end)\(auth)&title=\(title)"
                object["chapterReader"] = "/view?uid=\(uid)&mode=book&page=0&start_chapter=\(chapterIndex)&end_chapter=\(chapterIndex)\(auth)&title=\(title)"
            }
            return object
        }
    }

    private static func queryComponent(_ value: String) -> String {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "&=+?#")
        return value.addingPercentEncoding(
            withAllowedCharacters: allowed
        ) ?? value
    }

    private nonisolated static func dateString(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }
}

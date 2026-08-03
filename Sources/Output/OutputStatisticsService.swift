import Foundation

enum OutputStatisticsService {
    private nonisolated static let minimumFreeDiskReserveBytes: Int64 =
        512 * 1024 * 1024

    nonisolated static func uniqueRecordedOutputURLs(
        jobs: [DownloadJob],
        history: [DownloadHistoryEntry]
    ) -> [URL] {
        var seenPaths = Set<String>()
        let rawPaths = jobs.map(\.outputPath) + history.map(\.outputPath)
        return rawPaths.compactMap { rawPath in
            let trimmed = rawPath.trimmed
            guard !trimmed.isEmpty else { return nil }
            let url = URL(fileURLWithPath: trimmed)
            let resolvedPath = url.resolvingSymlinksInPath()
                .standardizedFileURL.path
            guard seenPaths.insert(resolvedPath).inserted else { return nil }
            return url
        }
    }

    nonisolated static func outputURLs(
        for jobs: [DownloadJob],
        fileManager: FileManager = .default
    ) -> [URL] {
        let outputService = OutputService(fileManager: fileManager)
        var urls: [URL] = []
        var seenPaths = Set<String>()

        func append(_ url: URL) {
            let resolvedPath = url.resolvingSymlinksInPath()
                .standardizedFileURL.path
            guard seenPaths.insert(resolvedPath).inserted else { return }
            urls.append(url)
        }

        for job in jobs {
            for candidate in outputService.outputDeletionCandidates(for: job) {
                append(URL(fileURLWithPath: candidate.path))
            }
        }
        return urls
    }

    nonisolated static func statistics(
        for jobs: [DownloadJob],
        fileManager: FileManager = .default
    ) -> OutputFileStatistics {
        statistics(for: outputURLs(for: jobs, fileManager: fileManager))
    }

    nonisolated static func summaryText(
        for jobs: [DownloadJob],
        fileManager: FileManager = .default
    ) -> String {
        let statistics = statistics(for: jobs, fileManager: fileManager)
        guard statistics.fileCount > 0 || statistics.directoryCount > 0 else {
            return "no output"
        }
        let fileText = statistics.fileCount == 1
            ? "1 file"
            : "\(statistics.fileCount) files"
        return "\(fileText) · \(byteCountText(statistics.byteCount))"
    }

    nonisolated static func statistics(
        for urls: [URL]
    ) -> OutputFileStatistics {
        var statistics = OutputFileStatistics()
        var countedFiles = Set<String>()
        var countedDirectories = Set<String>()
        for url in urls {
            if shouldSkipPathAnalysis(for: url) {
                statistics.skippedPathAnalysisCount += 1
                continue
            }
            appendStatistics(
                at: url,
                statistics: &statistics,
                countedFiles: &countedFiles,
                countedDirectories: &countedDirectories
            )
        }
        return statistics
    }

    nonisolated static func diskSpaceStatus(
        destinationPath: String,
        jobs: [DownloadJob]
    ) -> DiskSpaceStatus {
        let path = destinationPath.trimmed
        let root = URL(
            fileURLWithPath: path.isEmpty
                ? AppPaths.defaultDownloadDirectory.path
                : path,
            isDirectory: true
        )
        guard let volumeURL = existingAncestorURL(for: root) else {
            return DiskSpaceStatus(
                path: root.path,
                availableByteCount: nil,
                totalByteCount: nil,
                estimatedRequiredByteCount: estimatedQueuedByteCount(for: jobs),
                warning: "Storage warning: destination folder is unavailable."
            )
        }

        let estimated = estimatedQueuedByteCount(for: jobs)
        if shouldSkipPathAnalysis(forExistingVolumeURL: volumeURL) {
            return DiskSpaceStatus(
                path: root.path,
                availableByteCount: nil,
                totalByteCount: nil,
                estimatedRequiredByteCount: estimated,
                warning: "",
                pathAnalysisSkipped: true
            )
        }

        let values = try? volumeURL.resourceValues(forKeys: [
            .volumeAvailableCapacityForImportantUsageKey,
            .volumeAvailableCapacityKey,
            .volumeTotalCapacityKey
        ])
        let available = values?.volumeAvailableCapacityForImportantUsage ??
            values?.volumeAvailableCapacity.map(Int64.init)
        let total = values?.volumeTotalCapacity.map(Int64.init)
        return DiskSpaceStatus(
            path: root.path,
            availableByteCount: available,
            totalByteCount: total,
            estimatedRequiredByteCount: estimated,
            warning: diskSpaceWarning(
                path: root.path,
                available: available,
                estimatedRequired: estimated
            )
        )
    }

    nonisolated static func estimatedQueuedByteCount(
        for jobs: [DownloadJob]
    ) -> Int64 {
        jobs.reduce(0) { total, job in
            guard job.status == .queued ||
                    job.status == .resolving ||
                    job.status == .downloading else {
                return total
            }
            return total + DownloadJobMetadataMetrics.estimatedByteCount(for: job)
        }
    }

    nonisolated static func shouldSkipPathAnalysis(
        volumeIsLocal: Bool?
    ) -> Bool {
        volumeIsLocal == false
    }

    nonisolated static func shouldSkipPathAnalysis(for url: URL) -> Bool {
        guard url.isFileURL else { return false }
        guard let volumeURL = existingAncestorURL(for: url) else { return false }
        return shouldSkipPathAnalysis(forExistingVolumeURL: volumeURL)
    }

    private nonisolated static func diskSpaceWarning(
        path: String,
        available: Int64?,
        estimatedRequired: Int64
    ) -> String {
        guard let available else { return "" }
        if estimatedRequired > 0 &&
            available < estimatedRequired + minimumFreeDiskReserveBytes {
            return "Storage warning: \(byteCountText(available)) available, " +
                "\(byteCountText(estimatedRequired)) known queued size."
        }
        if available < minimumFreeDiskReserveBytes {
            return "Storage warning: only \(byteCountText(available)) " +
                "available at the destination."
        }
        return ""
    }

    private nonisolated static func existingAncestorURL(for url: URL) -> URL? {
        let fileManager = FileManager.default
        var candidate = url
        while true {
            if fileManager.fileExists(atPath: candidate.path) {
                return candidate
            }
            let parent = candidate.deletingLastPathComponent()
            if parent.path == candidate.path {
                return nil
            }
            candidate = parent
        }
    }

    private nonisolated static func shouldSkipPathAnalysis(
        forExistingVolumeURL url: URL
    ) -> Bool {
        let values = try? url.resourceValues(forKeys: [.volumeIsLocalKey])
        return shouldSkipPathAnalysis(volumeIsLocal: values?.volumeIsLocal)
    }

    private nonisolated static func appendStatistics(
        at url: URL,
        statistics: inout OutputFileStatistics,
        countedFiles: inout Set<String>,
        countedDirectories: inout Set<String>
    ) {
        let fileManager = FileManager.default
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(
            atPath: url.path,
            isDirectory: &isDirectory
        ) else {
            return
        }

        let resolvedURL = url.resolvingSymlinksInPath().standardizedFileURL
        if isDirectory.boolValue {
            countDirectory(
                resolvedURL,
                statistics: &statistics,
                countedDirectories: &countedDirectories
            )
            guard let enumerator = fileManager.enumerator(
                at: url,
                includingPropertiesForKeys: [
                    .isRegularFileKey,
                    .isDirectoryKey,
                    .fileSizeKey
                ],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else {
                return
            }

            for case let fileURL as URL in enumerator {
                let values = try? fileURL.resourceValues(forKeys: [
                    .isRegularFileKey,
                    .isDirectoryKey,
                    .fileSizeKey
                ])
                let resolvedChild = fileURL.resolvingSymlinksInPath()
                    .standardizedFileURL
                if values?.isDirectory == true {
                    countDirectory(
                        resolvedChild,
                        statistics: &statistics,
                        countedDirectories: &countedDirectories
                    )
                } else if values?.isRegularFile == true {
                    countFile(
                        resolvedChild,
                        byteCount: values?.fileSize,
                        statistics: &statistics,
                        countedFiles: &countedFiles
                    )
                }
            }
        } else {
            let values = try? resolvedURL.resourceValues(
                forKeys: [.isRegularFileKey, .fileSizeKey]
            )
            guard values?.isRegularFile != false else { return }
            countFile(
                resolvedURL,
                byteCount: values?.fileSize,
                statistics: &statistics,
                countedFiles: &countedFiles
            )
        }
    }

    private nonisolated static func countDirectory(
        _ url: URL,
        statistics: inout OutputFileStatistics,
        countedDirectories: inout Set<String>
    ) {
        guard countedDirectories.insert(url.path).inserted else { return }
        statistics.directoryCount += 1
    }

    private nonisolated static func countFile(
        _ url: URL,
        byteCount: Int?,
        statistics: inout OutputFileStatistics,
        countedFiles: inout Set<String>
    ) {
        guard countedFiles.insert(url.path).inserted else { return }
        statistics.fileCount += 1
        statistics.byteCount += Int64(byteCount ?? 0)
    }

    private nonisolated static func byteCountText(_ byteCount: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: byteCount, countStyle: .file)
    }
}

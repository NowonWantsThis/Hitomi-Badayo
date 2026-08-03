import Foundation

struct CompletedOutputMetadataCandidate:
    Sendable,
    Equatable
{
    var jobID: UUID
    var originalOutputPath: String
    var needsByteCount: Bool
}

struct CompletedOutputMetadataResult:
    Sendable,
    Equatable
{
    var jobID: UUID
    var originalOutputPath: String
    var recoveredOutputPath: String
    var byteCount: Int64?
}

final class CompletedOutputMetadataService:
    @unchecked Sendable
{
    func resolvedFilenames(
        at outputPath: String
    ) async -> [String] {
        await Task.detached(priority: .utility) {
            self.resolvedFilenamesSynchronously(
                at: outputPath
            )
        }.value
    }

    func resolvedFilenamesSynchronously(
        at outputPath: String
    ) -> [String] {
        OutputPreviewFileScanner.files(
            at: outputPath
        ).map(\.relativePath)
    }

    func outputPathExists(
        _ outputPath: String
    ) -> Bool {
        OutputPreviewFileScanner.outputPathExists(
            outputPath
        )
    }

    func outputByteCountAsynchronously(
        forOutputPath outputPath: String
    ) async -> Int64? {
        await Task.detached(priority: .utility) {
            self.outputByteCount(
                forOutputPath: outputPath,
                fileManager: .default
            )
        }.value
    }

    func outputByteCount(
        forOutputPath outputPath: String,
        fileManager: FileManager = .default
    ) -> Int64? {
        let value = outputPath.trimmed
        guard !value.isEmpty else { return nil }

        let output = URL(
            fileURLWithPath:
                (value as NSString).expandingTildeInPath
        )
        var isDirectory = ObjCBool(false)
        guard fileManager.fileExists(
            atPath: output.path,
            isDirectory: &isDirectory
        ) else {
            return nil
        }
        if !isDirectory.boolValue {
            return fileManager.isReadableFile(
                atPath: output.path
            )
                ? outputFileByteCount(output)
                : nil
        }

        guard let enumerator = fileManager.enumerator(
            at: output,
            includingPropertiesForKeys: [
                .isRegularFileKey,
                .fileSizeKey
            ],
            options: [
                .skipsHiddenFiles,
                .skipsPackageDescendants
            ],
            errorHandler: { _, _ in true }
        ) else {
            return nil
        }

        var total: Int64 = 0
        var fileCount = 0
        for case let file as URL in enumerator {
            guard let values = try? file.resourceValues(
                forKeys: [
                    .isRegularFileKey,
                    .fileSizeKey
                ]
            ),
            values.isRegularFile == true,
            let size = values.fileSize,
            size >= 0 else {
                continue
            }
            let (sum, overflow) =
                total.addingReportingOverflow(
                    Int64(size)
                )
            total = overflow ? Int64.max : sum
            fileCount += 1
        }
        return fileCount > 0 ? total : nil
    }

    func completedOutputMetadataResults(
        for candidates:
            [CompletedOutputMetadataCandidate],
        destinationPath: String
    ) async -> [CompletedOutputMetadataResult] {
        let workerCount = min(4, candidates.count)
        return await withTaskGroup(
            of: [CompletedOutputMetadataResult].self
        ) { group in
            for workerIndex in 0..<workerCount {
                group.addTask(priority: .utility) {
                    var workerResults:
                        [CompletedOutputMetadataResult] = []
                    for candidateIndex in stride(
                        from: workerIndex,
                        to: candidates.count,
                        by: workerCount
                    ) {
                        guard !Task.isCancelled else {
                            break
                        }
                        let candidate =
                            candidates[candidateIndex]
                        guard let output =
                            QueueThumbnailProvider
                            .existingOutputURL(
                                forOutputPath:
                                    candidate
                                    .originalOutputPath,
                                destinationPath:
                                    destinationPath,
                                searchRelocatedOutputs:
                                    false
                            ) else {
                            continue
                        }
                        let byteCount =
                            candidate.needsByteCount
                            ? self.outputByteCount(
                                forOutputPath:
                                    output.path
                            )
                            : nil
                        workerResults.append(
                            CompletedOutputMetadataResult(
                                jobID: candidate.jobID,
                                originalOutputPath:
                                    candidate
                                    .originalOutputPath,
                                recoveredOutputPath:
                                    output.path,
                                byteCount: byteCount
                            )
                        )
                    }
                    return workerResults
                }
            }

            var results:
                [CompletedOutputMetadataResult] = []
            for await workerResults in group {
                results.append(
                    contentsOf: workerResults
                )
            }
            return results
        }
    }

    func hasLocalOutputByteCount(
        _ metadata: [String: String]
    ) -> Bool {
        metadata[
            "size_source"
        ]?.trimmed.lowercased() == "local-output" &&
            (metadataByteCount(
                metadata["byte_count"]
            ) ?? 0) > 0
    }

    func durationSeconds(
        forOutputPath outputPath: String,
        metadata: [String: String]
    ) async -> Double? {
        guard metadataNeedsLocalDuration(metadata),
              let outputURL = singleOutputMediaFileURL(
                from: URL(
                    fileURLWithPath: outputPath
                )
              ) else {
            return nil
        }
        return await MediaFileMetadataReader
            .durationSeconds(for: outputURL)
    }

    func metadataNeedsLocalDuration(
        _ metadata: [String: String]
    ) -> Bool {
        let durationKeys = [
            "duration_seconds",
            "duration",
            "duration_string",
            "duration_ms"
        ]
        return durationKeys.allSatisfy {
            metadata[$0]?.trimmed.isEmpty ?? true
        }
    }

    func metadataByAddingDuration(
        to metadata: [String: String],
        seconds: Double?
    ) -> [String: String] {
        MediaFileMetadataReader.metadataByAddingDuration(
            to: metadata,
            seconds: seconds
        )
    }

    func singleOutputMediaFileURL(
        from output: URL,
        fileManager: FileManager = .default
    ) -> URL? {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(
            atPath: output.path,
            isDirectory: &isDirectory
        ),
        !isDirectory.boolValue,
        MediaFileMetadataReader.canReadDuration(
            for: output
        ) else {
            return nil
        }
        return output
    }

    private func outputFileByteCount(
        _ file: URL
    ) -> Int64? {
        guard let values = try? file.resourceValues(
            forKeys: [.fileSizeKey]
        ),
        let size = values.fileSize,
        size >= 0 else {
            return nil
        }
        return Int64(size)
    }

    private func metadataByteCount(
        _ value: String?
    ) -> Int64? {
        guard let value = value?.trimmed,
              !value.isEmpty else {
            return nil
        }
        if let parsed = Int64(value), parsed >= 0 {
            return parsed
        }
        let digits = value.filter(\.isNumber)
        guard !digits.isEmpty,
              let parsed = Int64(digits),
              parsed >= 0 else {
            return nil
        }
        return parsed
    }
}

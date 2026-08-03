import Foundation

struct DirectSplitSegment:
    Equatable,
    Sendable
{
    var index: Int
    var lowerBound: Int
    var upperBound: Int

    var expectedByteCount: Int {
        upperBound - lowerBound + 1
    }
}

struct DirectSegmentDownloadReceipt:
    Equatable,
    Sendable
{
    var statusCode: Int?
    var byteCount: Int
}

final class DirectSegmentTransferService {
    typealias SegmentDownloader =
        (
            URL,
            URL,
            HTTPRequestOptions,
            DirectSplitSegment
        ) async throws ->
            DirectSegmentDownloadReceipt
    typealias ProgressHandler =
        @MainActor (Int) -> Void
    typealias JoinHandler =
        @MainActor () -> Void

    private let downloadSegment:
        SegmentDownloader

    init(
        downloadSegment:
            @escaping SegmentDownloader = {
                source,
                destination,
                headers,
                segment in
                let rangeHeader =
                    "bytes=\(segment.lowerBound)-" +
                    "\(segment.upperBound)"
                let response =
                    try await HTTPClient.shared.download(
                        from: source,
                        to: destination,
                        referer: headers.referer,
                        userAgent: headers.userAgent,
                        additionalHeaders: [
                            "Range": rangeHeader
                        ]
                    )
                let byteCount =
                    (
                        try? destination
                            .resourceValues(
                                forKeys: [.fileSizeKey]
                            )
                            .fileSize
                    ) ?? 0
                return DirectSegmentDownloadReceipt(
                    statusCode:
                        response?.statusCode,
                    byteCount: byteCount
                )
            }
    ) {
        self.downloadSegment = downloadSegment
    }

    func download(
        _ source: URL,
        segments: [DirectSplitSegment],
        to destination: URL,
        headers: HTTPRequestOptions,
        maximumConcurrentDownloads: Int,
        onProgress:
            @escaping ProgressHandler,
        onJoining:
            @escaping JoinHandler
    ) async throws {
        let partFolder =
            destination
            .deletingLastPathComponent()
            .appendingPathComponent(
                ".direct-\(UUID().uuidString).parts",
                isDirectory: true
            )
        try FileManager.default.createDirectory(
            at: partFolder,
            withIntermediateDirectories: true
        )
        defer {
            try? FileManager.default.removeItem(
                at: partFolder
            )
        }

        let limit = AsyncSemaphore(
            value: max(
                1,
                min(
                    8,
                    maximumConcurrentDownloads
                )
            )
        )
        var completedCount = 0
        let downloadSegment = downloadSegment
        try await withThrowingTaskGroup(
            of: Void.self
        ) { group in
            for segment in segments {
                group.addTask {
                    try Task.checkCancellation()
                    try await limit.withPermit {
                        let partURL =
                            partFolder
                            .appendingPathComponent(
                                String(
                                    format: "%06d.part",
                                    segment.index
                                )
                            )
                        let receipt =
                            try await downloadSegment(
                                source,
                                partURL,
                                headers,
                                segment
                            )
                        let rangeHeader =
                            "bytes=\(segment.lowerBound)-" +
                            "\(segment.upperBound)"
                        guard receipt.statusCode == 206 else {
                            throw NativeDownloadError
                                .unsupported(
                                    "Server did not honor byte range " +
                                    "\(rangeHeader)."
                                )
                        }
                        guard receipt.byteCount ==
                                segment.expectedByteCount else {
                            throw NativeDownloadError
                                .unsupported(
                                    "Byte range \(rangeHeader) returned " +
                                    "\(receipt.byteCount) bytes, expected " +
                                    "\(segment.expectedByteCount)."
                                )
                        }
                    }
                }
            }

            for try await _ in group {
                try Task.checkCancellation()
                completedCount += 1
                await onProgress(completedCount)
            }
        }

        await onJoining()
        try join(
            segments: segments,
            from: partFolder,
            to: destination
        )
    }

    private func join(
        segments: [DirectSplitSegment],
        from partFolder: URL,
        to destination: URL
    ) throws {
        if FileManager.default.fileExists(
            atPath: destination.path
        ) {
            try FileManager.default.removeItem(
                at: destination
            )
        }
        FileManager.default.createFile(
            atPath: destination.path,
            contents: nil
        )
        let writer = try FileHandle(
            forWritingTo: destination
        )
        defer {
            try? writer.close()
        }

        for segment in segments.sorted(
            by: { $0.index < $1.index }
        ) {
            try Task.checkCancellation()
            let partURL =
                partFolder.appendingPathComponent(
                    String(
                        format: "%06d.part",
                        segment.index
                    )
                )
            let reader = try FileHandle(
                forReadingFrom: partURL
            )
            defer {
                try? reader.close()
            }
            while true {
                let chunk =
                    try reader.read(
                        upToCount: 1_048_576
                    ) ?? Data()
                if chunk.isEmpty {
                    break
                }
                try writer.write(
                    contentsOf: chunk
                )
            }
        }
    }
}

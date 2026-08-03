import Foundation

struct LiveHLSRefreshContext {
    var playlistURL: URL
    var headers: HTTPRequestOptions
    var additionalHeaders: [String: String]
    var segmentReferer: String?
}

struct LiveHLSRecordingRequest {
    var initialResolved: ResolvedDownload
    var tempFolder: URL
    var output: URL
}

enum LiveHLSRecordingEvent {
    case starting(
        playlistURL: URL,
        pollInterval: TimeInterval,
        timeout: TimeInterval
    )
    case preparingBatch(count: Int, isInitialSnapshot: Bool)
    case preparingAppend
    case recordingBatch(
        segmentCount: Int,
        mediaCount: Int,
        recordedDuration: Double,
        outputBytes: Int64,
        speed: Int64,
        recordedAt: String,
        snapshotCount: Int
    )
    case waitingForSegments
    case recordingRefresh(
        pollCount: Int,
        pollInterval: TimeInterval
    )
    case recordingRefreshFailure(
        pollCount: Int,
        errorText: String
    )
    case finishingPolling(
        reason: String,
        pollCount: Int,
        outputBytes: Int64,
        hasPartialOutput: Bool
    )
    case recordingFailure(
        cancelled: Bool,
        pollCount: Int,
        outputBytes: Int64,
        hasPartialOutput: Bool
    )
}

struct LiveHLSRecordingOperations {
    var fallbackConcatenate: (
        _ assets: [ResolvedAsset],
        _ tempFolder: URL,
        _ output: URL
    ) async throws -> Void
    var downloadAssets: (
        _ assets: [ResolvedAsset],
        _ folder: URL
    ) async throws -> [URL]
    var resolvePlaylist: (
        _ context: LiveHLSRefreshContext
    ) async throws -> ResolvedDownload
    var stopRequested: () -> Bool
    var onEvent: (LiveHLSRecordingEvent) -> Void
    var now: () -> Date = Date.init
    var sleep: (_ nanoseconds: UInt64) async throws -> Void = {
        try await Task.sleep(nanoseconds: $0)
    }
}

@MainActor
final class LiveHLSRecordingCoordinator {
    private let fileManager: FileManager
    private let concatenationService: MediaConcatenationService

    init(
        fileManager: FileManager = .default,
        concatenationService: MediaConcatenationService =
            MediaConcatenationService()
    ) {
        self.fileManager = fileManager
        self.concatenationService = concatenationService
    }

    func execute(
        _ request: LiveHLSRecordingRequest,
        operations: LiveHLSRecordingOperations
    ) async throws {
        let initialResolved = request.initialResolved
        let tempFolder = request.tempFolder
        let output = request.output
        guard let refreshContext = Self.refreshContext(
            for: initialResolved
        ) else {
            try await operations.fallbackConcatenate(
                initialResolved.assets,
                tempFolder,
                output
            )
            return
        }

        if fileManager.fileExists(atPath: output.path) {
            try fileManager.removeItem(at: output)
        }
        fileManager.createFile(atPath: output.path, contents: nil)
        let writer = try FileHandle(forWritingTo: output)
        defer {
            try? writer.close()
            try? fileManager.removeItem(at: tempFolder)
        }

        var snapshot = initialResolved
        var isInitialSnapshot = true
        var visited = Set<String>()
        var outputOrdinal = 0
        var pollCount = 0
        var recordedSegmentCount = 0
        var recordedDuration: Double = 0
        var lastNewSegmentAt = operations.now()
        var lastTransferSampleAt = operations.now()
        var lastTransferBytes: Int64 = 0
        var pollInterval = Self.pollInterval(from: snapshot.metadata)
        let timeout = Self.timeout(from: initialResolved.metadata)

        operations.onEvent(
            .starting(
                playlistURL: refreshContext.playlistURL,
                pollInterval: pollInterval,
                timeout: timeout
            )
        )

        do {
            while true {
                try Task.checkCancellation()
                if operations.stopRequested() {
                    finish(
                        reason: "stopped",
                        pollCount: pollCount,
                        output: output,
                        operations: operations
                    )
                    break
                }

                let refreshedAssets = Self.preparedAssets(
                    snapshot.assets,
                    initialResolved: initialResolved,
                    applySiteAdjustments: !isInitialSnapshot
                )
                var batch: [ResolvedAsset] = []
                var batchIdentities: [String] = []
                for asset in refreshedAssets {
                    let identity = Self.assetIdentity(asset)
                    guard !visited.contains(identity),
                          !batchIdentities.contains(identity) else {
                        continue
                    }
                    var numbered = asset
                    numbered.filename = Self.filename(
                        for: asset,
                        ordinal: outputOrdinal + batch.count
                    )
                    batch.append(numbered)
                    batchIdentities.append(identity)
                }

                if !batch.isEmpty {
                    operations.onEvent(
                        .preparingBatch(
                            count: batch.count,
                            isInitialSnapshot: isInitialSnapshot
                        )
                    )
                    let batchFolder = tempFolder.appendingPathComponent(
                        String(format: "batch-%06d", pollCount),
                        isDirectory: true
                    )
                    try AppPaths.ensureDirectory(batchFolder)
                    let downloaded: [URL]
                    do {
                        downloaded = try await operations.downloadAssets(
                            batch,
                            batchFolder
                        )
                        operations.onEvent(.preparingAppend)
                        try concatenationService.appendFiles(
                            downloaded,
                            to: writer
                        )
                        try writer.synchronize()
                    } catch {
                        try? fileManager.removeItem(at: batchFolder)
                        throw error
                    }
                    try? fileManager.removeItem(at: batchFolder)

                    visited.formUnion(batchIdentities)
                    outputOrdinal += batch.count
                    recordedSegmentCount += batch.filter {
                        $0.metadata["type"] == "hls_segment"
                    }.count
                    recordedDuration += batch.reduce(0) {
                        $0 + (Double(
                            $1.metadata["duration_seconds"]
                                ?? $1.metadata["duration"]
                                ?? ""
                        ) ?? 0)
                    }
                    let now = operations.now()
                    let outputBytes = MediaFileInspection.byteCount(output)
                    let elapsed = max(
                        0.001,
                        now.timeIntervalSince(lastTransferSampleAt)
                    )
                    let speed = Int64(
                        Double(max(0, outputBytes - lastTransferBytes))
                            / elapsed
                    )
                    lastTransferSampleAt = now
                    lastTransferBytes = outputBytes
                    lastNewSegmentAt = now
                    operations.onEvent(
                        .recordingBatch(
                            segmentCount: recordedSegmentCount,
                            mediaCount: visited.count,
                            recordedDuration: recordedDuration,
                            outputBytes: outputBytes,
                            speed: speed,
                            recordedAt: ISO8601DateFormatter()
                                .string(from: now),
                            snapshotCount: pollCount + 1
                        )
                    )
                }

                if operations.stopRequested() {
                    finish(
                        reason: "stopped",
                        pollCount: pollCount,
                        output: output,
                        operations: operations
                    )
                    break
                }
                if !Self.metadataIsTrue(
                    snapshot.metadata["live"]
                        ?? snapshot.metadata["is_live"]
                ) {
                    finish(
                        reason: "endlist",
                        pollCount: pollCount,
                        output: output,
                        operations: operations
                    )
                    break
                }
                if operations.now().timeIntervalSince(lastNewSegmentAt)
                    >= timeout {
                    finish(
                        reason: "timeout",
                        pollCount: pollCount,
                        output: output,
                        operations: operations
                    )
                    break
                }

                operations.onEvent(.waitingForSegments)
                guard try await waitForPollInterval(
                    pollInterval,
                    operations: operations
                ) else {
                    finish(
                        reason: "stopped",
                        pollCount: pollCount,
                        output: output,
                        operations: operations
                    )
                    break
                }

                pollCount += 1
                do {
                    snapshot = try await operations.resolvePlaylist(
                        refreshContext
                    )
                    isInitialSnapshot = false
                    pollInterval = Self.pollInterval(
                        from: snapshot.metadata
                    )
                    operations.onEvent(
                        .recordingRefresh(
                            pollCount: pollCount,
                            pollInterval: pollInterval
                        )
                    )
                } catch is CancellationError {
                    throw CancellationError()
                } catch {
                    operations.onEvent(
                        .recordingRefreshFailure(
                            pollCount: pollCount,
                            errorText: AppLocalization.errorText(error)
                        )
                    )
                    if operations.now().timeIntervalSince(lastNewSegmentAt)
                        >= timeout {
                        finish(
                            reason: "timeout",
                            pollCount: pollCount,
                            output: output,
                            operations: operations
                        )
                        break
                    }
                }
            }
        } catch is CancellationError {
            recordFailure(
                cancelled: true,
                pollCount: pollCount,
                output: output,
                operations: operations
            )
            if !MediaFileInspection.hasContent(output) {
                try? fileManager.removeItem(at: output)
            }
            throw CancellationError()
        } catch {
            recordFailure(
                cancelled: false,
                pollCount: pollCount,
                output: output,
                operations: operations
            )
            if !MediaFileInspection.hasContent(output) {
                try? fileManager.removeItem(at: output)
            }
            throw error
        }
    }

    private func waitForPollInterval(
        _ interval: TimeInterval,
        operations: LiveHLSRecordingOperations
    ) async throws -> Bool {
        let deadline = operations.now().addingTimeInterval(max(0, interval))
        while operations.now() < deadline {
            try Task.checkCancellation()
            if operations.stopRequested() {
                return false
            }
            let remaining = deadline.timeIntervalSince(operations.now())
            let slice = min(0.25, max(0.01, remaining))
            try await operations.sleep(UInt64(slice * 1_000_000_000))
        }
        try Task.checkCancellation()
        return !operations.stopRequested()
    }

    private func finish(
        reason: String,
        pollCount: Int,
        output: URL,
        operations: LiveHLSRecordingOperations
    ) {
        operations.onEvent(
            .finishingPolling(
                reason: reason,
                pollCount: pollCount,
                outputBytes: MediaFileInspection.byteCount(output),
                hasPartialOutput: MediaFileInspection.hasContent(output)
            )
        )
    }

    private func recordFailure(
        cancelled: Bool,
        pollCount: Int,
        output: URL,
        operations: LiveHLSRecordingOperations
    ) {
        operations.onEvent(
            .recordingFailure(
                cancelled: cancelled,
                pollCount: pollCount,
                outputBytes: MediaFileInspection.byteCount(output),
                hasPartialOutput: MediaFileInspection.hasContent(output)
            )
        )
    }

    static func shouldPoll(_ resolved: ResolvedDownload) -> Bool {
        guard (resolved.metadata["type"] == "hls"
                || resolved.metadata["format"] == "m3u8"),
              metadataIsTrue(
                resolved.metadata["live"]
                    ?? resolved.metadata["is_live"]
              ),
              !metadataIsTrue(resolved.metadata["vod"]),
              resolved.metadata["playlist_type"]?.trimmed.uppercased()
                != "VOD",
              !metadataIsTrue(
                resolved.metadata["custom_segment_urls"]
              ),
              let rawURL = resolved.metadata["playlist_url"]?.trimmed,
              let url = URL(string: rawURL),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            return false
        }
        return true
    }

    static func refreshContext(
        for resolved: ResolvedDownload
    ) -> LiveHLSRefreshContext? {
        guard shouldPoll(resolved),
              let rawURL = resolved.metadata["playlist_url"]?.trimmed,
              let playlistURL = URL(string: rawURL),
              let prototype = resolved.assets.first(where: {
                $0.metadata["type"] == "hls_segment"
              }) ?? resolved.assets.first else {
            return nil
        }
        return LiveHLSRefreshContext(
            playlistURL: playlistURL,
            headers: HTTPRequestOptions(
                referer: prototype.referer,
                userAgent: prototype.userAgent
            ),
            additionalHeaders: prototype.additionalHeaderFields,
            segmentReferer: prototype.referer
        )
    }

    static func preparedAssets(
        _ assets: [ResolvedAsset],
        initialResolved: ResolvedDownload,
        applySiteAdjustments: Bool
    ) -> [ResolvedAsset] {
        var prepared = assets
        if applySiteAdjustments,
           initialResolved.metadata["site"]?.trimmed.lowercased()
            == "twitch" {
            prepared = TwitchVODResolver
                .adjustedLiveHLSAssetsForRefresh(prepared)
        }

        let prototypes = Dictionary(grouping: initialResolved.assets) {
            $0.metadata["type"] ?? ""
        }
        return prepared.map { asset in
            var copy = asset
            let prototype = prototypes[asset.metadata["type"] ?? ""]?.first
                ?? initialResolved.assets.first
            if copy.referer?.trimmed.isEmpty != false {
                copy.referer = prototype?.referer
            }
            if copy.userAgent?.trimmed.isEmpty != false {
                copy.userAgent = prototype?.userAgent
            }
            if copy.additionalHeaders.isEmpty {
                copy.additionalHeaders = prototype?.additionalHeaders ?? []
            }
            copy.pythonSegmentDecorator = prototype?.pythonSegmentDecorator
            for (key, value) in initialResolved.metadata
                where copy.metadata[key] == nil {
                copy.metadata[key] = value
            }
            if let prototype {
                for (key, value) in prototype.metadata
                    where copy.metadata[key] == nil {
                    copy.metadata[key] = value
                }
            }
            return copy
        }
    }

    static func assetIdentity(_ asset: ResolvedAsset) -> String {
        let type = asset.metadata["type"] ?? "hls_segment"
        let sequence = asset.metadata["media_sequence"]?.trimmed ?? ""
        let byteRange = asset.metadata["byte_range"]?.trimmed ?? ""
        var components = [
            type,
            sequence,
            canonicalURL(asset.remoteURL),
            byteRange
        ]
        if type == "hls_map" {
            components.append(
                asset.decryption.map { canonicalURL($0.keyURL) } ?? ""
            )
            components.append(
                asset.decryption?.iv.base64EncodedString() ?? ""
            )
        }
        return components.joined(separator: "|")
    }

    static func canonicalURL(_ url: URL) -> String {
        guard var components = URLComponents(
            url: url,
            resolvingAgainstBaseURL: false
        ) else {
            return url.absoluteString
        }
        components.query = nil
        components.fragment = nil
        components.user = nil
        components.password = nil
        return components.string ?? url.absoluteString
    }

    static func filename(
        for asset: ResolvedAsset,
        ordinal: Int
    ) -> String {
        let filenameExtension = (asset.filename as NSString)
            .pathExtension.trimmed
        let remoteExtension = asset.remoteURL.pathExtension.trimmed
        let ext = (
            filenameExtension.isEmpty
                ? (remoteExtension.isEmpty ? "ts" : remoteExtension)
                : filenameExtension
        ).lowercased()
        let suffix = asset.metadata["type"] == "hls_map" ? "-map" : ""
        return String(
            format: "%012d%@.%@",
            ordinal,
            suffix,
            ext
        ).sanitizedFilename()
    }

    static func pollInterval(
        from metadata: [String: String]
    ) -> TimeInterval {
        let target = Double(metadata["target_duration"]?.trimmed ?? "")
            ?? 10
        return min(10, max(0.1, target))
    }

    static func timeout(
        from metadata: [String: String]
    ) -> TimeInterval {
        let timeout = Double(metadata["live_timeout"]?.trimmed ?? "")
            ?? 180
        return min(86_400, max(1, timeout))
    }

    static func metadataIsTrue(_ value: String?) -> Bool {
        guard let value = value?.trimmed.lowercased(),
              !value.isEmpty else {
            return false
        }
        return ["1", "true", "yes", "on"].contains(value)
    }

}

import Foundation

struct YTDLPJobProgressSnapshot {
    var fraction: Double?
    var itemFraction: Double?
    var downloadedBytes: Int64?
    var totalBytes: Int64?
    var playlistIndex: Int
    var playlistCount: Int
}

struct YTDLPJobProgressState {
    private(set) var mediaID: String?
    private(set) var playlistIndex = 1
    private(set) var playlistCount = 1
    private var formatOrder: [String] = []
    private var expectedBytes: [String: Int64] = [:]
    private var downloadedBytes: [String: Int64] = [:]
    private var fractions: [String: Double] = [:]

    mutating func apply(
        _ update: YTDLPRuntimeUpdate
    ) -> YTDLPJobProgressSnapshot {
        let incomingMediaID = update.mediaID?.trimmed
        if let incomingMediaID,
           !incomingMediaID.isEmpty,
           incomingMediaID != mediaID {
            mediaID = incomingMediaID
            formatOrder.removeAll(keepingCapacity: true)
            expectedBytes.removeAll(keepingCapacity: true)
            downloadedBytes.removeAll(keepingCapacity: true)
            fractions.removeAll(keepingCapacity: true)
        }

        if let index = update.playlistIndex, index > 0 {
            playlistIndex = index
        }
        if let count = update.playlistCount, count > 0 {
            playlistCount = count
        }
        playlistCount = max(1, max(playlistCount, playlistIndex))

        if let planned = update.plannedFormats, !planned.isEmpty {
            formatOrder = []
            expectedBytes.removeAll(keepingCapacity: true)
            downloadedBytes.removeAll(keepingCapacity: true)
            fractions.removeAll(keepingCapacity: true)
            for format in planned {
                let formatID = format.formatID.trimmed
                guard !formatID.isEmpty,
                      !formatOrder.contains(formatID) else {
                    continue
                }
                formatOrder.append(formatID)
                if let bytes = format.expectedBytes, bytes > 0 {
                    expectedBytes[formatID] = bytes
                }
            }
        }

        let explicitFormatID = update.formatID?.trimmed
        let formatID: String? = {
            if let explicitFormatID, !explicitFormatID.isEmpty {
                return explicitFormatID
            }
            if formatOrder.count == 1 {
                return formatOrder[0]
            }
            if formatOrder.isEmpty,
               update.downloadedBytes != nil ||
                update.fraction != nil {
                return "current"
            }
            return nil
        }()

        if let formatID {
            if !formatOrder.contains(formatID) {
                formatOrder.append(formatID)
            }
            if let total = update.totalBytes, total > 0 {
                expectedBytes[formatID] = total
            }
            if let downloaded = update.downloadedBytes,
               downloaded >= 0 {
                downloadedBytes[formatID] = max(
                    downloadedBytes[formatID] ?? 0,
                    downloaded
                )
            }
            if let fraction = update.fraction {
                fractions[formatID] = max(
                    fractions[formatID] ?? 0,
                    min(1, max(0, fraction))
                )
            } else if let downloaded = downloadedBytes[formatID],
                      let total = expectedBytes[formatID],
                      total > 0 {
                fractions[formatID] = min(
                    1,
                    max(0, Double(downloaded) / Double(total))
                )
            }
            if update.transferStatus?.lowercased() == "finished" {
                fractions[formatID] = 1
                if let total = expectedBytes[formatID] {
                    downloadedBytes[formatID] = total
                }
            }
        }

        let hasCompleteBytePlan =
            !formatOrder.isEmpty &&
            formatOrder.allSatisfy {
                (expectedBytes[$0] ?? 0) > 0
            }
        let aggregateTotal: Int64? = hasCompleteBytePlan
            ? formatOrder.reduce(0) {
                $0 + (expectedBytes[$1] ?? 0)
            }
            : update.totalBytes
        let aggregateDownloaded: Int64? = hasCompleteBytePlan
            ? formatOrder.reduce(0) { sum, formatID in
                sum + min(
                    expectedBytes[formatID] ?? 0,
                    downloadedBytes[formatID] ?? 0
                )
            }
            : update.downloadedBytes

        let itemFraction: Double? = {
            if let aggregateDownloaded,
               let aggregateTotal,
               aggregateTotal > 0 {
                return min(
                    1,
                    max(
                        0,
                        Double(aggregateDownloaded) /
                            Double(aggregateTotal)
                    )
                )
            }
            guard !formatOrder.isEmpty else {
                return update.fraction
            }
            guard formatOrder.contains(where: {
                fractions[$0] != nil
            }) else {
                return update.fraction
            }
            return formatOrder.reduce(0) {
                $0 + (fractions[$1] ?? 0)
            } / Double(formatOrder.count)
        }()
        let overallFraction = itemFraction.map {
            itemFraction in
            let boundedIndex = min(
                playlistCount,
                max(1, playlistIndex)
            )
            return min(
                1,
                max(
                    0,
                    (
                        Double(boundedIndex - 1) +
                            itemFraction
                    ) /
                        Double(max(1, playlistCount))
                )
            )
        }

        return YTDLPJobProgressSnapshot(
            fraction: overallFraction,
            itemFraction: itemFraction,
            downloadedBytes: aggregateDownloaded,
            totalBytes: aggregateTotal,
            playlistIndex: playlistIndex,
            playlistCount: playlistCount
        )
    }
}

@MainActor
final class YTDLPProgressUpdateService {
    private let now: () -> Date
    private var progressStates:
        [UUID: YTDLPJobProgressState] = [:]

    init(now: @escaping () -> Date = Date.init) {
        self.now = now
    }

    func beginTracking(jobID: UUID) {
        progressStates[jobID] =
            YTDLPJobProgressState()
    }

    func endTracking(jobID: UUID) {
        progressStates.removeValue(forKey: jobID)
    }

    func snapshot(
        applying update: YTDLPRuntimeUpdate,
        jobID: UUID
    ) -> YTDLPJobProgressSnapshot {
        var state =
            progressStates[jobID] ??
            YTDLPJobProgressState()
        let snapshot = state.apply(update)
        progressStates[jobID] = state
        return snapshot
    }

    func applyingLiveMetadata(
        _ update: YTDLPRuntimeUpdate,
        to job: DownloadJob
    ) -> DownloadJob? {
        guard let isLive = update.isLive else {
            return nil
        }

        var updated = job
        updated.metadata["ytdlp_live"] =
            isLive ? "true" : "false"
        if isLive {
            updated.metadata["live"] = "true"
            updated.metadata["is_live"] = "true"
            updated.metadata["was_live"] = "true"
            updated.metadata["live_active"] = "true"
            updated.metadata["live_polling"] = "false"
        }
        if let liveStatus = update.liveStatus {
            updated.metadata["live_status"] = liveStatus
        }
        if let title = update.title?.trimmed,
           !title.isEmpty {
            updated.title = title
        }
        return updated
    }

    func applyingTransferMetadata(
        _ update: YTDLPRuntimeUpdate,
        snapshot: YTDLPJobProgressSnapshot,
        to job: DownloadJob,
        interfaceLanguage: AppInterfaceLanguage
    ) -> DownloadJob {
        var updated = job
        if let downloaded = snapshot.downloadedBytes,
           downloaded >= 0 {
            updated.metadata["downloaded_bytes"] =
                String(downloaded)
        }
        if let total = snapshot.totalBytes, total > 0 {
            updated.metadata["total_bytes"] = String(total)
        }
        if let speed = update.speedBytesPerSecond,
           speed >= 0 {
            updated.metadata["speed_bytes_per_second"] =
                String(speed)
        }
        if let eta = update.etaSeconds, eta >= 0 {
            updated.metadata["eta_seconds"] = String(eta)
        }
        if let itemFraction = snapshot.itemFraction {
            updated.metadata["transfer_item_fraction"] =
                String(itemFraction)
        }
        updated.metadata["transfer_item_index"] =
            String(snapshot.playlistIndex)
        updated.metadata["transfer_item_count"] =
            String(snapshot.playlistCount)
        if let formatID = update.formatID {
            updated.metadata["transfer_format_id"] = formatID
        }
        if let fraction = snapshot.fraction {
            let bounded = min(0.995, max(0, fraction))
            updated.progress = max(updated.progress, bounded)
            updated.metadata["transfer_fraction"] =
                String(fraction)
        }
        if snapshot.playlistCount > 1 {
            updated.total = snapshot.playlistCount
            updated.completed = max(
                updated.completed,
                min(
                    snapshot.playlistCount,
                    snapshot.playlistIndex - 1
                )
            )
        }

        guard update.downloadedBytes != nil ||
                update.speedBytesPerSecond != nil ||
                update.fraction != nil ||
                update.transferStatus != nil else {
            return updated
        }
        updated.metadata["transfer_active"] = "true"
        updated.metadata["last_transfer_at"] =
            ISO8601DateFormatter().string(from: now())
        let live = Self.metadataIsTrue(
            updated.metadata["ytdlp_live"]
        )
        let base = AppLocalization.text(
            live
                ? "Recording YouTube live"
                : "Downloading with yt-dlp",
            language: interfaceLanguage
        )
        if let downloaded = snapshot.downloadedBytes,
           downloaded > 0 {
            updated.message =
                "\(base) · \(Self.byteCountText(downloaded))"
        } else {
            updated.message = base
        }
        return updated
    }

    private static func metadataIsTrue(
        _ value: String?
    ) -> Bool {
        guard let value = value?.trimmed.lowercased(),
              !value.isEmpty else {
            return false
        }
        return ["1", "true", "yes", "on"].contains(value)
    }

    private static func byteCountText(
        _ byteCount: Int64
    ) -> String {
        ByteCountFormatter.string(
            fromByteCount: byteCount,
            countStyle: .file
        )
    }
}

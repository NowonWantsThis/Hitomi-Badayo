import Foundation

final class NativeTransferProgressService {
    private let now: () -> Date

    init(now: @escaping () -> Date = Date.init) {
        self.now = now
    }

    func shouldReportProgress(
        for asset: ResolvedAsset,
        jobMetadata: [String: String]
    ) -> Bool {
        let site = (
            asset.metadata["site"] ??
                jobMetadata["site"] ??
                ""
        ).trimmed.lowercased()
        let type = (
            asset.metadata["type"] ??
                asset.metadata["media_type"] ??
                ""
        ).trimmed.lowercased()
        return site.contains("chzzk") &&
            !type.contains("segment") &&
            !type.contains("hls")
    }

    func applying(
        _ update: HTTPDownloadProgress,
        to job: DownloadJob,
        interfaceLanguage: AppInterfaceLanguage
    ) -> DownloadJob {
        var updated = job
        updated.metadata["transfer_active"] = "true"
        updated.metadata["downloaded_bytes"] =
            String(update.downloadedBytes)
        updated.metadata["last_transfer_at"] =
            ISO8601DateFormatter().string(from: now())
        if let total = update.totalBytes, total > 0 {
            let fraction = min(
                1,
                max(
                    0,
                    Double(update.downloadedBytes) /
                        Double(total)
                )
            )
            updated.metadata["total_bytes"] = String(total)
            updated.metadata["transfer_fraction"] =
                String(fraction)
            updated.progress = min(0.995, fraction)
        }
        if let speed = update.speedBytesPerSecond,
           speed > 0 {
            updated.metadata["speed_bytes_per_second"] =
                String(speed)
        }
        let downloadedText = ByteCountFormatter.string(
            fromByteCount: update.downloadedBytes,
            countStyle: .file
        )
        updated.message = AppLocalization.format(
            "Downloading Chzzk video · %@",
            language: interfaceLanguage,
            downloadedText
        )
        return updated
    }
}

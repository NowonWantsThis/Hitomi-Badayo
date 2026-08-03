import Foundation

final class SourceResolverProgressJobStateService {
    func applying(
        _ progress: SourceResolverExecutionProgress,
        to job: DownloadJob,
        language: AppInterfaceLanguage
    ) -> DownloadJob {
        var updated = job
        switch progress {
        case .pixivCollection(let pixivProgress):
            updated.message = AppLocalization.format(
                "Reading Pixiv works %@ / %@ · %@ images",
                language: language,
                String(
                    pixivProgress
                        .processedArtworkCount
                ),
                String(
                    pixivProgress
                        .listedArtworkCount
                ),
                String(pixivProgress.assetCount)
            )
        }
        return updated
    }
}

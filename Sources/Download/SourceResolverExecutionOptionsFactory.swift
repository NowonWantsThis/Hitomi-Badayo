import Foundation

struct SourceResolverExecutionPreferences: Equatable {
    var preferWebP: Bool
    var preferOriginalEHentaiImages: Bool
    var preferJapaneseEHentaiTitle: Bool
    var eHentaiSourceMode: EHentaiSourceMode
    var pawchiveSiteAddresses: [String]
    var pawchiveDownloadLargeOriginalFiles: Bool
    var pawchiveFileTypeSelection: PawchiveFileTypeSelection
    var pixivArtwork: PixivArtworkResolverExecutionOptions
    var youtubePreferredResolution: String
    var soopPreferredResolution: String
    var youtubeVideoCodecPriority: [YouTubeVideoCodec]
    var youtubeReversePlaylist: Bool
    var numberPlaylistFiles: Bool
    var instagramIncludeStories: Bool
}

struct SourceResolverExecutionOptionsFactory {
    func makeOptions(
        rangeExpression: String,
        assetLimit: Int?,
        metadata: [String: String],
        preferences: SourceResolverExecutionPreferences
    ) -> SourceResolverExecutionOptions {
        SourceResolverExecutionOptions(
            rangeExpression: rangeExpression,
            assetLimit: assetLimit,
            metadata: metadata,
            hitomi: HitomiResolverExecutionOptions(
                preferWebP: preferences.preferWebP,
                preferOriginalImages:
                    preferences.preferOriginalEHentaiImages,
                preferJapaneseTitle:
                    preferences.preferJapaneseEHentaiTitle
            ),
            eHentai: EHentaiResolverExecutionOptions(
                sourceMode: preferences.eHentaiSourceMode,
                preferWebP: preferences.preferWebP,
                preferOriginalImages:
                    preferences.preferOriginalEHentaiImages,
                preferJapaneseTitle:
                    preferences.preferJapaneseEHentaiTitle
            ),
            pawchive: PawchiveResolverExecutionOptions(
                siteAddresses: preferences.pawchiveSiteAddresses,
                downloadLargeOriginalFiles:
                    preferences.pawchiveDownloadLargeOriginalFiles,
                fileTypeSelection: preferences.pawchiveFileTypeSelection
            ),
            pixiv: preferences.pixivArtwork,
            media: SourceResolverMediaOptions(
                preferredResolution:
                    preferences.youtubePreferredResolution,
                soopPreferredResolution:
                    preferences.soopPreferredResolution,
                youtubeCodecPriority:
                    preferences.youtubeVideoCodecPriority,
                reverseYouTubePlaylist:
                    preferences.youtubeReversePlaylist,
                numberPlaylistFiles:
                    preferences.numberPlaylistFiles,
                includeInstagramStories:
                    preferences.instagramIncludeStories
            )
        )
    }
}

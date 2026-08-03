import Foundation

struct SourceResolverFallbackPolicy {
    private static let routes: Set<SourceResolverRoute> = [
        .tikTok,
        .twitterCollection,
        .twitter,
        .bilibiliCollection,
        .bilibili,
        .pornhubCollection,
        .pornhubMedia,
        .xVideoCollection,
        .xHamsterCollection,
        .iwaraCollection,
        .iwaraVideo,
        .niconicoLive,
        .kissJAV,
        .tokyoMotion,
        .etcVideoPage,
        .naverTV,
        .chzzkCollection,
        .hanime,
        .instagram,
        .facebookPhotoCollection,
        .facebookPhoto,
        .facebookVideo,
        .twitchClipCollection,
        .twitchVOD,
        .soopVOD,
        .kakaoTV,
        .youtubeCollection,
        .youtube,
        .vLive,
        .niconico
    ]

    func allowsYTDLPFallback(
        for route: SourceResolverRoute,
        url: URL,
        ytdlpCanResolve: Bool
    ) -> Bool {
        guard Self.routes.contains(route) else { return false }
        if ytdlpCanResolve {
            return true
        }

        switch route {
        case .tikTok:
            return TikTokResolver.videoID(from: url) != nil ||
                TikTokResolver.profileUsername(from: url) != nil ||
                TikTokResolver.shortLinkCode(from: url) != nil
        case .twitter:
            return TwitterResolver.tweetID(from: url) != nil ||
                TwitterResolver.twitpicID(from: url) != nil ||
                TwitterResolver.twitterSpaceID(from: url) != nil ||
                TwitterResolver.twitterBroadcastID(from: url) != nil
        case .bilibili:
            return BilibiliResolver.tvVideoID(from: url) != nil ||
                BilibiliResolver.shortLinkCode(from: url) != nil
        case .pornhubMedia:
            return PornhubMediaResolver.request(from: url)?.kind == .video
        case .etcVideoPage:
            return EtcVideoPageResolver.site(for: url) == .tver &&
                EtcVideoPageResolver.contentID(from: url) != nil
        case .facebookVideo:
            return FacebookVideoResolver.videoID(from: url) != nil
        case .vLive:
            return VLiveResolver.contentID(from: url) != nil
        default:
            return false
        }
    }
}

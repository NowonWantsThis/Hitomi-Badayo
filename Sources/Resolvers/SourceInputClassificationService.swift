import Foundation

struct SourceInputClassification: Equatable {
    var type: String
    var resolver: String
    var valid: Bool
}

@MainActor
struct SourceInputClassificationService {
    private let registry: SourceResolverRegistry
    private let aria2Bridge: Aria2Bridge
    private let ytdlpBridge: YTDLPBridge

    init(
        registry: SourceResolverRegistry,
        aria2Bridge: Aria2Bridge,
        ytdlpBridge: YTDLPBridge
    ) {
        self.registry = registry
        self.aria2Bridge = aria2Bridge
        self.ytdlpBridge = ytdlpBridge
    }

    func classification(
        for source: String,
        url: URL?,
        pawchiveSiteAddresses: [String],
        siteRules: [SiteRule]
    ) -> SourceInputClassification {
        if registry.discordEmojiResolver.canResolve(source) {
            return result("emoji", "Discord Emoji")
        }

        guard let url,
              let scheme = url.scheme?.lowercased(),
              !scheme.isEmpty else {
            return unsupported
        }

        if scheme == "magnet" {
            return result("torrent", "aria2")
        }
        if scheme == "file" {
            return aria2Bridge.canResolve(url)
                ? result("torrent", "aria2")
                : result("file", "Local File")
        }
        guard scheme == "http" || scheme == "https" else {
            return unsupported
        }

        if aria2Bridge.canResolve(url) {
            return result("torrent", "aria2")
        }
        if registry.mpdResolver.canResolve(url) {
            return result("dash", "MPD")
        }
        if registry.m3u8Resolver.canResolve(url) {
            return result("hls", "M3U8")
        }
        if registry.matchesPawchive(
            url,
            siteAddresses: pawchiveSiteAddresses
        ) {
            return result("gallery", "Kemono friends")
        }

        if InstagramResolver.storyCollectionUsername(from: url) != nil {
            return result("gallery", "Instagram Stories")
        }
        if InstagramResolver.profileUsername(from: url) != nil {
            return result("gallery", "Instagram Profile")
        }

        if let route = registry.firstMatchingStandardRoute(for: url),
           let routeResult = classification(for: route) {
            return routeResult
        }
        if hasCustomCommandRule(for: url, siteRules: siteRules) {
            return result("custom", "Custom Command")
        }
        if ytdlpBridge.canResolve(url, siteRules: siteRules) {
            return result("media", "yt-dlp")
        }

        let mediaType = Self.mediaType(for: url)
        if mediaType != "file", !url.pathExtension.isEmpty {
            return result(mediaType, "Direct File")
        }
        if registry.genericPageResolver.canResolve(url) {
            return result("web", "Generic Page")
        }
        return result("file", "Direct File")
    }

    func classification(
        for route: SourceResolverRoute
    ) -> SourceInputClassification? {
        switch route {
        case .pawchive:
            return result("gallery", "Kemono friends")
        case .mpd:
            return result("dash", "MPD")
        case .m3u8:
            return result("hls", "M3U8")
        case .hitomi:
            return result("gallery", "Hitomi")
        case .nhentai:
            return result("gallery", "NHentai")
        case .nhentaiCom:
            return result("gallery", "NHentai.com")
        case .asmHentai:
            return result("gallery", "AsmHentai")
        case .eHentai:
            return result("gallery", "E-Hentai")
        case .myReadingManga:
            return result("gallery", "MyReadingManga")
        case .narou:
            return result("text", "Narou")
        case .kakuyomu:
            return result("text", "Kakuyomu")
        case .hameln:
            return result("text", "Hameln")
        case .artStation:
            return result("gallery", "ArtStation")
        case .imgur:
            return result("gallery", "Imgur")
        case .deviantArt:
            return result("gallery", "DeviantArt")
        case .coub:
            return result("media", "Coub")
        case .vimeo:
            return result("video", "Vimeo")
        case .tumblr:
            return result("gallery", "Tumblr")
        case .bdsmLr:
            return result("gallery", "BDSMlr")
        case .luscious:
            return result("gallery", "Luscious")
        case .soundCloud:
            return result("audio", "SoundCloud")
        case .tikTok:
            return result("video", "TikTok")
        case .twitterCollection:
            return result("gallery", "Twitter Profile")
        case .twitter:
            return result("media", "Twitter")
        case .fediverse:
            return result("media", "Fediverse")
        case .bilibiliCollection:
            return result("video", "Bilibili Collection")
        case .bilibili:
            return result("video", "Bilibili")
        case .fourChan:
            return result("gallery", "4chan")
        case .arcalive:
            return result("gallery", "Arcalive")
        case .dcInside:
            return result("gallery", "DCInside")
        case .flickr:
            return result("gallery", "Flickr")
        case .pinterest:
            return result("gallery", "Pinterest")
        case .wikiArt:
            return result("gallery", "WikiArt")
        case .newgrounds:
            return result("gallery", "Newgrounds")
        case .nijie:
            return result("gallery", "Nijie")
        case .nozomi:
            return result("gallery", "Nozomi")
        case .v2ph:
            return result("gallery", "V2PH")
        case .hentaiCosplay:
            return result("gallery", "Hentai Cosplay")
        case .hentaiFoundry:
            return result("gallery", "Hentai Foundry")
        case .talkOPGG:
            return result("gallery", "Talk OP.GG")
        case .bcy:
            return result("gallery", "BCY")
        case .waybackMachine:
            return result("gallery", "Wayback Machine")
        case .fc2:
            return result("video", "FC2")
        case .pornhubCollection:
            return result("video", "Pornhub Collection")
        case .pornhubMedia:
            return result("video", "Pornhub")
        case .xVideoCollection:
            return result("video", "XVideos Channel")
        case .xVideoPage:
            return result("video", "XVideo")
        case .xHamsterCollection:
            return result("video", "xHamster Channel")
        case .xHamsterGallery:
            return result("gallery", "xHamster")
        case .iwaraCollection:
            return result("gallery", "Iwara Profile")
        case .iwaraImage:
            return result("gallery", "Iwara Image")
        case .iwaraVideo:
            return result("video", "Iwara Video")
        case .weiboStatus:
            return result("gallery", "Weibo")
        case .spankBang:
            return result("video", "SpankBang")
        case .niconicoLive:
            return result("video", "Niconico Live")
        case .tokyoMotion:
            return result("media", "TokyoMotion")
        case .etcVideoPage:
            return result("video", "Video Page")
        case .hiyobi:
            return result("gallery", "Hiyobi")
        case .manatoki:
            return result("gallery", "Manatoki")
        case .lhScan:
            return result("gallery", "LHScan")
        case .jMana:
            return result("gallery", "JMana")
        case .webtoon:
            return result("gallery", "WEBTOON")
        case .naverWebtoon:
            return result("gallery", "Naver Webtoon")
        case .naverPost:
            return result("gallery", "Naver Post")
        case .naverBlog:
            return result("gallery", "Naver Blog")
        case .naverCafe:
            return result("gallery", "Naver Cafe")
        case .naverTV:
            return result("video", "Naver TV")
        case .chzzkCollection:
            return result("video", "Chzzk Videos")
        case .chzzk:
            return result("video", "Chzzk")
        case .hanime:
            return result("video", "Hanime")
        case .instagram:
            return result("media", "Instagram")
        case .facebookPhotoCollection:
            return result("gallery", "Facebook Photos")
        case .facebookPhoto:
            return result("gallery", "Facebook Photo")
        case .facebookVideo:
            return result("video", "Facebook Video")
        case .twitchClipCollection:
            return result("video", "Twitch Clips")
        case .twitchVOD:
            return result("video", "Twitch")
        case .soopVOD:
            return result("video", "SOOP")
        case .kakaoTV:
            return result("video", "KakaoTV")
        case .youtube:
            return result("video", "YouTube")
        case .vLive:
            return result("video", "V LIVE")
        case .niconico:
            return result("video", "Niconico")
        case .lezhin:
            return result("gallery", "Lezhin Comics")
        case .kakaoWebtoon:
            return result("gallery", "Kakao Webtoon")
        case .kakaoPage:
            return result("gallery", "KakaoPage")
        case .pixivArtwork:
            return result("gallery", "Pixiv Artwork")
        case .pixivComic:
            return result("gallery", "Pixiv Comic")
        case .comicWalker:
            return result("gallery", "ComicWalker")
        case .sankaku:
            return result("gallery", "Sankaku")
        case .booru:
            return result("gallery", "Booru")
        case .avgle, .kissJAV, .youtubeCollection:
            return nil
        }
    }

    nonisolated static func mediaType(for url: URL) -> String {
        let ext = url.pathExtension.lowercased()
        if OutputContentFileService.imageExtensions.contains(ext) {
            return "image"
        }
        if OutputContentFileService.videoExtensions.contains(ext) {
            return "video"
        }
        if OutputContentFileService.audioExtensions.contains(ext) {
            return "audio"
        }
        if OutputContentFileService.documentExtensions.contains(ext) {
            return "document"
        }
        return "file"
    }

    private func hasCustomCommandRule(
        for url: URL,
        siteRules: [SiteRule]
    ) -> Bool {
        guard url.host != nil else { return false }
        return siteRules
            .filter {
                $0.handler == .customCommand &&
                    !($0.commandTemplate?.trimmed.isEmpty ?? true)
            }
            .sorted { $0.matchSpecificity > $1.matchSpecificity }
            .contains { $0.matches(url) }
    }

    private var unsupported: SourceInputClassification {
        SourceInputClassification(
            type: "unsupported",
            resolver: "unsupported",
            valid: false
        )
    }

    private func result(
        _ type: String,
        _ resolver: String
    ) -> SourceInputClassification {
        SourceInputClassification(
            type: type,
            resolver: resolver,
            valid: true
        )
    }
}

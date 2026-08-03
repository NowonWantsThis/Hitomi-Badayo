import Foundation

enum SourceResolverRoute: String, CaseIterable {
    case pawchive
    case mpd
    case m3u8
    case hitomi
    case nhentai
    case nhentaiCom
    case asmHentai
    case eHentai
    case myReadingManga
    case narou
    case kakuyomu
    case hameln
    case artStation
    case imgur
    case deviantArt
    case coub
    case vimeo
    case tumblr
    case bdsmLr
    case luscious
    case soundCloud
    case tikTok
    case twitterCollection
    case twitter
    case fediverse
    case bilibiliCollection
    case bilibili
    case fourChan
    case arcalive
    case dcInside
    case flickr
    case pinterest
    case wikiArt
    case newgrounds
    case nijie
    case nozomi
    case v2ph
    case hentaiCosplay
    case hentaiFoundry
    case talkOPGG
    case bcy
    case waybackMachine
    case fc2
    case pornhubCollection
    case pornhubMedia
    case xVideoCollection
    case xVideoPage
    case xHamsterCollection
    case xHamsterGallery
    case iwaraCollection
    case iwaraImage
    case iwaraVideo
    case weiboStatus
    case spankBang
    case avgle
    case niconicoLive
    case kissJAV
    case tokyoMotion
    case etcVideoPage
    case hiyobi
    case manatoki
    case lhScan
    case jMana
    case webtoon
    case naverWebtoon
    case naverPost
    case naverBlog
    case naverCafe
    case naverTV
    case chzzkCollection
    case chzzk
    case hanime
    case instagram
    case facebookPhotoCollection
    case facebookPhoto
    case facebookVideo
    case twitchClipCollection
    case twitchVOD
    case soopVOD
    case kakaoTV
    case youtubeCollection
    case youtube
    case vLive
    case niconico
    case lezhin
    case kakaoWebtoon
    case kakaoPage
    case pixivArtwork
    case pixivComic
    case comicWalker
    case sankaku
    case booru
}

@MainActor
final class SourceResolverRegistry {
    let hitomiResolver = HitomiResolver()
    let nhentaiResolver = NHentaiResolver()
    let nhentaiComResolver = NHentaiComResolver()
    let asmHentaiResolver = AsmHentaiResolver()
    let eHentaiResolver = EHentaiResolver()
    lazy var eHentaiSourceResolver = EHentaiSourceResolver(
        hitomiResolver: hitomiResolver,
        eHentaiResolver: eHentaiResolver
    )
    let myReadingMangaResolver = MyReadingMangaResolver()
    let narouResolver = NarouResolver()
    let kakuyomuResolver = KakuyomuResolver()
    let hamelnResolver = HamelnResolver()
    let artStationResolver = ArtStationResolver()
    let imgurResolver = ImgurResolver()
    let deviantArtResolver = DeviantArtResolver()
    let discordEmojiResolver = DiscordEmojiResolver()
    let coubResolver = CoubResolver()
    let vimeoResolver = VimeoResolver()
    let tumblrResolver = TumblrResolver()
    let bdsmLrResolver = BDSMlrResolver()
    let lusciousResolver = LusciousResolver()
    let soundCloudResolver = SoundCloudResolver()
    let tikTokResolver = TikTokResolver()
    let twitterCollectionResolver = TwitterCollectionResolver()
    let twitterResolver = TwitterResolver()
    let fediverseResolver = FediverseResolver()
    let bilibiliCollectionResolver = BilibiliCollectionResolver()
    let bilibiliResolver = BilibiliResolver()
    let fourChanResolver = FourChanResolver()
    let arcaliveResolver = ArcaliveResolver()
    let dcInsideResolver = DCInsideResolver()
    let flickrResolver = FlickrResolver()
    let pinterestResolver = PinterestResolver()
    let wikiArtResolver = WikiArtResolver()
    let newgroundsResolver = NewgroundsResolver()
    let nijieResolver = NijieResolver()
    let nozomiResolver = NozomiResolver()
    let v2phResolver = V2PHResolver()
    let hentaiCosplayResolver = HentaiCosplayResolver()
    let hentaiFoundryResolver = HentaiFoundryResolver()
    let talkOPGGResolver = TalkOPGGResolver()
    let bcyResolver = BCYResolver()
    let waybackMachineResolver = WaybackMachineResolver()
    let fc2Resolver = FC2Resolver()
    let pornhubCollectionResolver = PornhubCollectionResolver()
    let pornhubMediaResolver = PornhubMediaResolver()
    let xVideoCollectionResolver = XVideoCollectionResolver()
    let xVideoPageResolver = XVideoPageResolver()
    let xHamsterCollectionResolver = XHamsterCollectionResolver()
    let xHamsterGalleryResolver = XHamsterGalleryResolver()
    let iwaraCollectionResolver = IwaraCollectionResolver()
    let iwaraImageResolver = IwaraImageResolver()
    let iwaraVideoResolver = IwaraVideoResolver()
    let weiboStatusResolver = WeiboStatusResolver()
    let spankBangResolver = SpankBangResolver()
    let avgleResolver = AvgleResolver()
    let kissJAVResolver = KissJAVResolver()
    let tokyoMotionResolver = TokyoMotionResolver()
    let etcVideoPageResolver = EtcVideoPageResolver()
    let hiyobiResolver = HiyobiResolver()
    let manatokiResolver = ManatokiResolver()
    let lhScanResolver = LHScanResolver()
    let jManaResolver = JManaResolver()
    let webtoonResolver = WebtoonResolver()
    let naverWebtoonResolver = NaverWebtoonResolver()
    let naverPostResolver = NaverPostResolver()
    let naverBlogResolver = NaverBlogResolver()
    let naverCafeResolver = NaverCafeResolver()
    let naverTVResolver = NaverTVResolver()
    let chzzkCollectionResolver = ChzzkCollectionResolver()
    let chzzkResolver = ChzzkResolver()
    let hanimeResolver = HanimeResolver()
    let instagramResolver = InstagramResolver()
    let facebookPhotoCollectionResolver = FacebookPhotoCollectionResolver()
    let facebookPhotoResolver = FacebookPhotoResolver()
    let facebookVideoResolver = FacebookVideoResolver()
    let twitchClipCollectionResolver = TwitchClipCollectionResolver()
    let twitchVODResolver = TwitchVODResolver()
    let soopVODResolver = SOOPVODResolver()
    let kakaoTVResolver = KakaoTVResolver()
    let youtubeCollectionResolver = YouTubeCollectionResolver()
    let youtubeResolver = YouTubeResolver()
    let vLiveResolver = VLiveResolver()
    let niconicoResolver = NiconicoResolver()
    let niconicoLiveResolver: NiconicoLiveResolver
    let lezhinResolver = LezhinResolver()
    let kakaoWebtoonResolver = KakaoWebtoonResolver()
    let kakaoPageResolver = KakaoPageResolver()
    let pixivArtworkResolver = PixivArtworkResolver()
    let pixivComicResolver = PixivComicResolver()
    let pawchiveResolver = PawchiveResolver()
    let comicWalkerResolver = ComicWalkerResolver()
    let sankakuResolver = SankakuResolver()
    let m3u8Resolver = M3U8Resolver()
    let mpdResolver = MPDResolver()
    let booruResolver = BooruResolver()
    let genericPageResolver = GenericPageResolver()

    init(niconicoLiveResolver: NiconicoLiveResolver = NiconicoLiveResolver()) {
        self.niconicoLiveResolver = niconicoLiveResolver
    }

    func firstMatchingRoute(
        for url: URL,
        pawchiveSiteAddresses: [String]
    ) -> SourceResolverRoute? {
        if matchesPawchive(url, siteAddresses: pawchiveSiteAddresses) {
            return .pawchive
        }
        return firstMatchingStandardRoute(for: url)
    }

    func matchesPawchive(_ url: URL, siteAddresses: [String]) -> Bool {
        pawchiveResolver.canResolve(url, siteAddresses: siteAddresses)
    }

    func firstMatchingStandardRoute(for url: URL) -> SourceResolverRoute? {
        if mpdResolver.canResolve(url) { return .mpd }
        if m3u8Resolver.canResolve(url) { return .m3u8 }
        if hitomiResolver.canResolve(url) { return .hitomi }
        if nhentaiResolver.canResolve(url) { return .nhentai }
        if nhentaiComResolver.canResolve(url) { return .nhentaiCom }
        if asmHentaiResolver.canResolve(url) { return .asmHentai }
        if eHentaiResolver.canResolve(url) { return .eHentai }
        if myReadingMangaResolver.canResolve(url) { return .myReadingManga }
        if narouResolver.canResolve(url) { return .narou }
        if kakuyomuResolver.canResolve(url) { return .kakuyomu }
        if hamelnResolver.canResolve(url) { return .hameln }
        if artStationResolver.canResolve(url) { return .artStation }
        if imgurResolver.canResolve(url) { return .imgur }
        if deviantArtResolver.canResolve(url) { return .deviantArt }
        if coubResolver.canResolve(url) { return .coub }
        if vimeoResolver.canResolve(url) { return .vimeo }
        if tumblrResolver.canResolve(url) { return .tumblr }
        if bdsmLrResolver.canResolve(url) { return .bdsmLr }
        if lusciousResolver.canResolve(url) { return .luscious }
        if soundCloudResolver.canResolve(url) { return .soundCloud }
        if tikTokResolver.canResolve(url) { return .tikTok }
        if twitterCollectionResolver.canResolve(url) { return .twitterCollection }
        if twitterResolver.canResolve(url) { return .twitter }
        if fediverseResolver.canResolve(url) { return .fediverse }
        if bilibiliCollectionResolver.canResolve(url) { return .bilibiliCollection }
        if bilibiliResolver.canResolve(url) { return .bilibili }
        if fourChanResolver.canResolve(url) { return .fourChan }
        if arcaliveResolver.canResolve(url) { return .arcalive }
        if dcInsideResolver.canResolve(url) { return .dcInside }
        if flickrResolver.canResolve(url) { return .flickr }
        if pinterestResolver.canResolve(url) { return .pinterest }
        if wikiArtResolver.canResolve(url) { return .wikiArt }
        if newgroundsResolver.canResolve(url) { return .newgrounds }
        if nijieResolver.canResolve(url) { return .nijie }
        if nozomiResolver.canResolve(url) { return .nozomi }
        if v2phResolver.canResolve(url) { return .v2ph }
        if hentaiCosplayResolver.canResolve(url) { return .hentaiCosplay }
        if hentaiFoundryResolver.canResolve(url) { return .hentaiFoundry }
        if talkOPGGResolver.canResolve(url) { return .talkOPGG }
        if bcyResolver.canResolve(url) { return .bcy }
        if waybackMachineResolver.canResolve(url) { return .waybackMachine }
        if fc2Resolver.canResolve(url) { return .fc2 }
        if pornhubCollectionResolver.canResolve(url) { return .pornhubCollection }
        if pornhubMediaResolver.canResolve(url) { return .pornhubMedia }
        if xVideoCollectionResolver.canResolve(url) { return .xVideoCollection }
        if xVideoPageResolver.canResolve(url) { return .xVideoPage }
        if xHamsterCollectionResolver.canResolve(url) { return .xHamsterCollection }
        if xHamsterGalleryResolver.canResolve(url) { return .xHamsterGallery }
        if iwaraCollectionResolver.canResolve(url) { return .iwaraCollection }
        if iwaraImageResolver.canResolve(url) { return .iwaraImage }
        if iwaraVideoResolver.canResolve(url) { return .iwaraVideo }
        if weiboStatusResolver.canResolve(url) { return .weiboStatus }
        if spankBangResolver.canResolve(url) { return .spankBang }
        if avgleResolver.canResolve(url) { return .avgle }
        if niconicoLiveResolver.canResolve(url) { return .niconicoLive }
        if kissJAVResolver.canResolve(url) { return .kissJAV }
        if tokyoMotionResolver.canResolve(url) { return .tokyoMotion }
        if etcVideoPageResolver.canResolve(url) { return .etcVideoPage }
        if hiyobiResolver.canResolve(url) { return .hiyobi }
        if manatokiResolver.canResolve(url) { return .manatoki }
        if lhScanResolver.canResolve(url) { return .lhScan }
        if jManaResolver.canResolve(url) { return .jMana }
        if webtoonResolver.canResolve(url) { return .webtoon }
        if naverWebtoonResolver.canResolve(url) { return .naverWebtoon }
        if naverPostResolver.canResolve(url) { return .naverPost }
        if naverBlogResolver.canResolve(url) { return .naverBlog }
        if naverCafeResolver.canResolve(url) { return .naverCafe }
        if naverTVResolver.canResolve(url) { return .naverTV }
        if chzzkCollectionResolver.canResolve(url) { return .chzzkCollection }
        if chzzkResolver.canResolve(url) { return .chzzk }
        if hanimeResolver.canResolve(url) { return .hanime }
        if instagramResolver.canResolve(url) { return .instagram }
        if facebookPhotoCollectionResolver.canResolve(url) { return .facebookPhotoCollection }
        if facebookPhotoResolver.canResolve(url) { return .facebookPhoto }
        if facebookVideoResolver.canResolve(url) { return .facebookVideo }
        if twitchClipCollectionResolver.canResolve(url) { return .twitchClipCollection }
        if twitchVODResolver.canResolve(url) { return .twitchVOD }
        if soopVODResolver.canResolve(url) { return .soopVOD }
        if kakaoTVResolver.canResolve(url) { return .kakaoTV }
        if youtubeCollectionResolver.canResolve(url) { return .youtubeCollection }
        if youtubeResolver.canResolve(url) { return .youtube }
        if vLiveResolver.canResolve(url) { return .vLive }
        if niconicoResolver.canResolve(url) { return .niconico }
        if lezhinResolver.canResolve(url) { return .lezhin }
        if kakaoWebtoonResolver.canResolve(url) { return .kakaoWebtoon }
        if kakaoPageResolver.canResolve(url) { return .kakaoPage }
        if pixivArtworkResolver.canResolve(url) { return .pixivArtwork }
        if pixivComicResolver.canResolve(url) { return .pixivComic }
        if comicWalkerResolver.canResolve(url) { return .comicWalker }
        if sankakuResolver.canResolve(url) { return .sankaku }
        if booruResolver.canResolve(url) { return .booru }
        return nil
    }
}

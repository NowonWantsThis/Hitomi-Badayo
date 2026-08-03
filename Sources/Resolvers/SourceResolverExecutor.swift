import Foundation

struct PawchiveResolverExecutionOptions: Equatable {
    var siteAddresses: [String]
    var downloadLargeOriginalFiles: Bool
    var fileTypeSelection: PawchiveFileTypeSelection
}

struct HitomiResolverExecutionOptions: Equatable {
    var preferWebP: Bool
    var preferOriginalImages: Bool
    var preferJapaneseTitle: Bool
}

struct EHentaiResolverExecutionOptions: Equatable {
    var sourceMode: EHentaiSourceMode
    var preferWebP: Bool
    var preferOriginalImages: Bool
    var preferJapaneseTitle: Bool

    static func == (
        lhs: EHentaiResolverExecutionOptions,
        rhs: EHentaiResolverExecutionOptions
    ) -> Bool {
        lhs.sourceMode.rawValue == rhs.sourceMode.rawValue &&
            lhs.preferWebP == rhs.preferWebP &&
            lhs.preferOriginalImages == rhs.preferOriginalImages &&
            lhs.preferJapaneseTitle == rhs.preferJapaneseTitle
    }
}

struct PixivArtworkResolverExecutionOptions: Equatable {
    var ugoiraFileFormat: PixivUgoiraFileFormat
    var ugoiraDither: Bool
    var ugoiraQuality: Int

    static func == (
        lhs: PixivArtworkResolverExecutionOptions,
        rhs: PixivArtworkResolverExecutionOptions
    ) -> Bool {
        lhs.ugoiraFileFormat.rawValue == rhs.ugoiraFileFormat.rawValue &&
            lhs.ugoiraDither == rhs.ugoiraDither &&
            lhs.ugoiraQuality == rhs.ugoiraQuality
    }
}

struct SourceResolverMediaOptions: Equatable {
    var preferredResolution = ""
    var soopPreferredResolution = ""
    var youtubeCodecPriority = YouTubeVideoCodec.originalDefaultPriority
    var reverseYouTubePlaylist = false
    var numberPlaylistFiles = false
    var includeInstagramStories = false
}

struct SourceResolverExecutionOptions: Equatable {
    var rangeExpression = ""
    var assetLimit: Int?
    var metadata: [String: String] = [:]
    var hitomi: HitomiResolverExecutionOptions?
    var eHentai: EHentaiResolverExecutionOptions?
    var pawchive: PawchiveResolverExecutionOptions?
    var pixiv: PixivArtworkResolverExecutionOptions?
    var media = SourceResolverMediaOptions()
}

enum SourceResolverAuthenticationRequest: Equatable {
    case arcalive(loginURL: URL)
    case chzzk
    case naverCafe
    case pixiv
    case pornhub
    case twitter
}

enum SourceResolverExecutionProgress: Equatable, Sendable {
    case pixivCollection(PixivCollectionProgress)
}

struct SourceResolverExecutionContext {
    let ensureActive: @MainActor () throws -> Void
    let reportStage: @MainActor (String) -> Void
    let reportCompletion: @MainActor (String) throws -> Void
    let reportProgress: @MainActor (SourceResolverExecutionProgress) -> Void
    let waitForAuthentication: (
        @MainActor (SourceResolverAuthenticationRequest) async -> Void
    )?

    init(
        ensureActive: @escaping @MainActor () throws -> Void = {
            try Task.checkCancellation()
        },
        reportStage: @escaping @MainActor (String) -> Void = { _ in },
        reportCompletion: @escaping @MainActor (String) throws -> Void = { _ in },
        reportProgress: @escaping @MainActor (
            SourceResolverExecutionProgress
        ) -> Void = { _ in },
        waitForAuthentication: (@MainActor (
            SourceResolverAuthenticationRequest
        ) async -> Void)? = nil
    ) {
        self.ensureActive = ensureActive
        self.reportStage = reportStage
        self.reportCompletion = reportCompletion
        self.reportProgress = reportProgress
        self.waitForAuthentication = waitForAuthentication
    }
}

enum SourceResolverExecutionFallback: Equatable {
    case none
    case ytDLP
}

enum SourceResolverDownloadFailureCleanup: Equatable {
    case none
    case niconicoLiveSession(metadataKey: String)
}

struct SourceResolverExecutionResult {
    let download: ResolvedDownload
    let sourceURLOverride: URL?
}

struct SourceResolverExecutionPlan {
    let route: SourceResolverRoute
    let statusMessage: String
    let options: SourceResolverExecutionOptions
    let fallback: SourceResolverExecutionFallback
    let downloadFailureCleanup: SourceResolverDownloadFailureCleanup
    private let operation: @MainActor () async throws -> SourceResolverExecutionResult

    init(
        route: SourceResolverRoute,
        statusMessage: String,
        options: SourceResolverExecutionOptions,
        fallback: SourceResolverExecutionFallback = .none,
        downloadFailureCleanup: SourceResolverDownloadFailureCleanup = .none,
        operation: @escaping @MainActor () async throws -> ResolvedDownload
    ) {
        self.route = route
        self.statusMessage = statusMessage
        self.options = options
        self.fallback = fallback
        self.downloadFailureCleanup = downloadFailureCleanup
        self.operation = {
            SourceResolverExecutionResult(
                download: try await operation(),
                sourceURLOverride: nil
            )
        }
    }

    init(
        route: SourceResolverRoute,
        statusMessage: String,
        options: SourceResolverExecutionOptions,
        fallback: SourceResolverExecutionFallback = .none,
        downloadFailureCleanup: SourceResolverDownloadFailureCleanup = .none,
        resultOperation: @escaping @MainActor () async throws -> SourceResolverExecutionResult
    ) {
        self.route = route
        self.statusMessage = statusMessage
        self.options = options
        self.fallback = fallback
        self.downloadFailureCleanup = downloadFailureCleanup
        self.operation = resultOperation
    }

    @MainActor
    func resolve() async throws -> ResolvedDownload {
        try await resolveResult().download
    }

    @MainActor
    func resolveResult() async throws -> SourceResolverExecutionResult {
        try await operation()
    }
}

@MainActor
final class SourceResolverExecutor {
    let registry: SourceResolverRegistry
    let authenticationCoordinator: SourceResolverAuthenticationCoordinator

    init(
        registry: SourceResolverRegistry,
        authenticationCoordinator: SourceResolverAuthenticationCoordinator? = nil
    ) {
        self.registry = registry
        self.authenticationCoordinator =
            authenticationCoordinator ?? SourceResolverAuthenticationCoordinator()
    }

    func executionPlan(
        for route: SourceResolverRoute,
        url: URL,
        headers: HTTPRequestOptions,
        options: SourceResolverExecutionOptions = SourceResolverExecutionOptions(),
        context: SourceResolverExecutionContext = SourceResolverExecutionContext()
    ) -> SourceResolverExecutionPlan? {
        switch route {
        case .pawchive:
            guard let pawchive = options.pawchive else { return nil }
            return plan(route, "Reading Pawchive posts", options: options) { [registry] in
                try await registry.pawchiveResolver.resolve(
                    url,
                    headers: headers,
                    siteAddresses: pawchive.siteAddresses,
                    downloadLargeOriginalFiles: pawchive.downloadLargeOriginalFiles,
                    fileTypeSelection: pawchive.fileTypeSelection,
                    rangeExpression: options.rangeExpression
                )
            }
        case .mpd:
            return plan(route, "Reading DASH manifest") { [registry] in
                try await registry.mpdResolver.resolve(url, headers: headers)
            }
        case .m3u8:
            return plan(route, "Reading M3U8 playlist") { [registry] in
                try await registry.m3u8Resolver.resolve(url, headers: headers)
            }
        case .hitomi:
            guard let hitomi = options.hitomi else { return nil }
            return plan(
                route,
                "Reading gallery metadata",
                options: options
            ) { [registry] in
                try context.ensureActive()
                let resolution = try await registry.eHentaiSourceResolver.resolveHitomiSource(
                    url,
                    preferWebP: hitomi.preferWebP,
                    headers: headers,
                    preferOriginalImages: hitomi.preferOriginalImages,
                    preferJapaneseTitle: hitomi.preferJapaneseTitle,
                    onFallbackToOriginal: {
                        context.reportStage(Self.hitomiFallbackStatus())
                    },
                    onStage: { message in
                        context.reportStage(message)
                    }
                )
                try context.reportCompletion(
                    Self.hitomiCompletionStatus(for: resolution.selectedSource)
                )
                return resolution.download
            }
        case .eHentai:
            guard let eHentai = options.eHentai else { return nil }
            return resultPlan(
                route,
                Self.eHentaiInitialStatus(for: eHentai.sourceMode),
                options: options
            ) { [registry] in
                try context.ensureActive()
                let resolution = try await registry.eHentaiSourceResolver.resolve(
                    url,
                    mode: eHentai.sourceMode,
                    preferWebP: eHentai.preferWebP,
                    headers: headers,
                    preferOriginalImages: eHentai.preferOriginalImages,
                    preferJapaneseTitle: eHentai.preferJapaneseTitle,
                    onFallbackToOriginal: {
                        context.reportStage(Self.eHentaiFallbackStatus())
                    },
                    onStage: { message in
                        context.reportStage(message)
                    }
                )
                try context.ensureActive()
                try context.reportCompletion(
                    Self.eHentaiCompletionStatus(
                        for: resolution.selectedSource,
                        usedFallback: resolution.usedFallback
                    )
                )
                return SourceResolverExecutionResult(
                    download: resolution.download,
                    sourceURLOverride: resolution.sourceURL == url
                        ? nil
                        : resolution.sourceURL
                )
            }
        case .nhentai:
            return plan(route, "Reading gallery metadata") { [registry] in
                try await registry.nhentaiResolver.resolve(url, headers: headers)
            }
        case .nhentaiCom:
            return plan(route, "Reading nhentai.com comic") { [registry] in
                try await registry.nhentaiComResolver.resolve(url, headers: headers)
            }
        case .asmHentai:
            return plan(route, "Reading AsmHentai gallery") { [registry] in
                try await registry.asmHentaiResolver.resolve(url, headers: headers)
            }
        case .myReadingManga:
            return plan(route, "Reading MyReadingManga post") { [registry] in
                try await registry.myReadingMangaResolver.resolve(url, headers: headers)
            }
        case .imgur:
            return plan(route, "Reading Imgur media") { [registry] in
                try await registry.imgurResolver.resolve(url, headers: headers)
            }
        case .coub:
            return plan(route, "Reading Coub media") { [registry] in
                try await registry.coubResolver.resolve(url, headers: headers)
            }
        case .vimeo:
            return plan(route, "Reading Vimeo media") { [registry] in
                try await registry.vimeoResolver.resolve(url, headers: headers)
            }
        case .fourChan:
            return plan(route, "Reading 4chan thread") { [registry] in
                try await registry.fourChanResolver.resolve(url, headers: headers)
            }
        case .arcalive:
            guard let waitForAuthentication = context.waitForAuthentication else {
                return nil
            }
            return plan(
                route,
                "Reading Arcalive article",
                options: options
            ) { [registry, authenticationCoordinator] in
                try await authenticationCoordinator.resolve(
                    operation: {
                        try await registry.arcaliveResolver.resolve(
                            url,
                            headers: headers
                        )
                    },
                    authenticationRequest: { error in
                        guard let resolverError = error as? ArcaliveResolverError,
                              case .authenticationRequired(let loginURL) = resolverError else {
                            return nil
                        }
                        return loginURL
                    },
                    waitForAuthentication: { loginURL in
                        await waitForAuthentication(
                            .arcalive(loginURL: loginURL)
                        )
                    },
                    ensureActive: context.ensureActive
                )
            }
        case .dcInside:
            return plan(route, "Reading DCInside article") { [registry] in
                try await registry.dcInsideResolver.resolve(url, headers: headers)
            }
        case .wikiArt:
            return plan(route, "Reading WikiArt paintings") { [registry] in
                try await registry.wikiArtResolver.resolve(url, headers: headers)
            }
        case .newgrounds:
            return plan(route, "Reading Newgrounds art") { [registry] in
                try await registry.newgroundsResolver.resolve(url, headers: headers)
            }
        case .talkOPGG:
            return plan(route, "Reading Talk OP.GG article") { [registry] in
                try await registry.talkOPGGResolver.resolve(url, headers: headers)
            }
        case .waybackMachine:
            return plan(route, "Reading Wayback snapshots") { [registry] in
                try await registry.waybackMachineResolver.resolve(url, headers: headers)
            }
        case .fc2:
            return plan(route, "Reading FC2 video") { [registry] in
                try await registry.fc2Resolver.resolve(url, headers: headers)
            }
        case .pornhubCollection:
            guard let waitForAuthentication = context.waitForAuthentication else {
                return nil
            }
            return plan(
                route,
                "Reading Pornhub collection",
                options: options,
                fallback: .ytDLP
            ) { [registry, authenticationCoordinator] in
                try await authenticationCoordinator.resolve(
                    operation: {
                        try await registry.pornhubCollectionResolver.resolve(
                            url,
                            headers: headers,
                            rangeExpression: options.rangeExpression,
                            preferredResolution: options.media.preferredResolution
                        )
                    },
                    authenticationRequest: { error in
                        guard let resolverError = error as? PornhubResolverError,
                              case .authenticationRequired = resolverError else {
                            return nil
                        }
                        return SourceResolverAuthenticationRequest.pornhub
                    },
                    waitForAuthentication: { request in
                        await waitForAuthentication(request)
                    },
                    ensureActive: context.ensureActive
                )
            }
        case .pornhubMedia:
            guard let waitForAuthentication = context.waitForAuthentication else {
                return nil
            }
            return plan(
                route,
                "Reading Pornhub media",
                options: options,
                fallback: .ytDLP
            ) { [registry, authenticationCoordinator] in
                try await authenticationCoordinator.resolve(
                    operation: {
                        try await registry.pornhubMediaResolver.resolve(
                            url,
                            headers: headers,
                            preferredResolution: options.media.preferredResolution
                        )
                    },
                    authenticationRequest: { error in
                        guard let resolverError = error as? PornhubResolverError,
                              case .authenticationRequired = resolverError else {
                            return nil
                        }
                        return SourceResolverAuthenticationRequest.pornhub
                    },
                    waitForAuthentication: { request in
                        await waitForAuthentication(request)
                    },
                    ensureActive: context.ensureActive
                )
            }
        case .xVideoPage:
            return plan(route, "Reading video page") { [registry] in
                try await registry.xVideoPageResolver.resolve(url, headers: headers)
            }
        case .xHamsterGallery:
            return plan(route, "Reading xHamster gallery") { [registry] in
                try await registry.xHamsterGalleryResolver.resolve(url, headers: headers)
            }
        case .iwaraImage:
            return plan(route, "Reading Iwara image post") { [registry] in
                try await registry.iwaraImageResolver.resolve(url, headers: headers)
            }
        case .iwaraVideo:
            return plan(route, "Reading Iwara video", fallback: .ytDLP) { [registry] in
                try await registry.iwaraVideoResolver.resolve(url, headers: headers)
            }
        case .spankBang:
            return plan(route, "Reading SpankBang video") { [registry] in
                try await registry.spankBangResolver.resolve(url, headers: headers)
            }
        case .hiyobi:
            return plan(route, "Reading Hiyobi gallery") { [registry] in
                try await registry.hiyobiResolver.resolve(url, headers: headers)
            }
        case .manatoki:
            return plan(route, "Reading Manatoki pages") { [registry] in
                try await registry.manatokiResolver.resolve(url, headers: headers)
            }
        case .lhScan:
            return plan(route, "Reading LHScan pages") { [registry] in
                try await registry.lhScanResolver.resolve(url, headers: headers)
            }
        case .jMana:
            return plan(route, "Reading JMana pages") { [registry] in
                try await registry.jManaResolver.resolve(url, headers: headers)
            }
        case .naverPost:
            return plan(route, "Reading Naver Post") { [registry] in
                try await registry.naverPostResolver.resolve(url, headers: headers)
            }
        case .naverBlog:
            return plan(route, "Reading Naver Blog") { [registry] in
                try await registry.naverBlogResolver.resolve(url, headers: headers)
            }
        case .naverCafe:
            guard let waitForAuthentication = context.waitForAuthentication else {
                return nil
            }
            return plan(
                route,
                "Reading Naver Cafe",
                options: options
            ) { [registry, authenticationCoordinator] in
                try await authenticationCoordinator.resolve(
                    operation: {
                        try await registry.naverCafeResolver.resolve(
                            url,
                            headers: headers
                        )
                    },
                    authenticationRequest: { error in
                        guard let resolverError = error as? NaverCafeResolverError,
                              case .authenticationRequired = resolverError else {
                            return nil
                        }
                        return SourceResolverAuthenticationRequest.naverCafe
                    },
                    waitForAuthentication: { request in
                        await waitForAuthentication(request)
                    },
                    ensureActive: context.ensureActive
                )
            }
        case .kakaoWebtoon:
            return plan(route, "Rendering Kakao Webtoon") { [registry] in
                try await registry.kakaoWebtoonResolver.resolve(url, headers: headers)
            }
        case .pixivArtwork:
            guard let pixiv = options.pixiv,
                  let waitForAuthentication = context.waitForAuthentication else {
                return nil
            }
            return plan(
                route,
                "Reading Pixiv artwork",
                options: options
            ) { [registry, authenticationCoordinator] in
                try await authenticationCoordinator.resolve(
                    operation: {
                        try await registry.pixivArtworkResolver.resolve(
                            url,
                            headers: headers,
                            ugoiraFileFormat: pixiv.ugoiraFileFormat,
                            ugoiraDither: pixiv.ugoiraDither,
                            ugoiraQuality: pixiv.ugoiraQuality,
                            rangeExpression: options.rangeExpression,
                            progress: { progress in
                                await context.reportProgress(
                                    .pixivCollection(progress)
                                )
                            }
                        )
                    },
                    authenticationRequest: { error in
                        guard let resolverError = error as? PixivArtworkResolverError,
                              case .authenticationRequired = resolverError else {
                            return nil
                        }
                        return SourceResolverAuthenticationRequest.pixiv
                    },
                    waitForAuthentication: { request in
                        await waitForAuthentication(request)
                    },
                    ensureActive: context.ensureActive
                )
            }
        case .pixivComic:
            return plan(route, "Reading Pixiv Comic") { [registry] in
                try await registry.pixivComicResolver.resolve(url, headers: headers)
            }
        case .narou:
            return plan(route, "Reading Narou text", options: options) { [registry] in
                try await registry.narouResolver.resolve(
                    url,
                    headers: headers,
                    assetLimit: options.assetLimit
                )
            }
        case .kakuyomu:
            return plan(route, "Reading Kakuyomu text", options: options) { [registry] in
                try await registry.kakuyomuResolver.resolve(
                    url,
                    headers: headers,
                    assetLimit: options.assetLimit
                )
            }
        case .hameln:
            return plan(route, "Reading Hameln text", options: options) { [registry] in
                try await registry.hamelnResolver.resolve(
                    url,
                    headers: headers,
                    assetLimit: options.assetLimit
                )
            }
        case .artStation:
            return plan(route, "Reading ArtStation metadata", options: options) { [registry] in
                try await registry.artStationResolver.resolve(
                    url,
                    headers: headers,
                    assetLimit: options.assetLimit
                )
            }
        case .deviantArt:
            return plan(route, "Reading DeviantArt page", options: options) { [registry] in
                try await registry.deviantArtResolver.resolve(
                    url,
                    headers: headers,
                    rangeExpression: options.rangeExpression
                )
            }
        case .tumblr:
            return plan(route, "Reading Tumblr posts", options: options) { [registry] in
                try await registry.tumblrResolver.resolve(
                    url,
                    headers: headers,
                    assetLimit: options.assetLimit
                )
            }
        case .bdsmLr:
            return plan(route, "Reading BDSMlr posts", options: options) { [registry] in
                try await registry.bdsmLrResolver.resolve(
                    url,
                    headers: headers,
                    assetLimit: options.assetLimit
                )
            }
        case .luscious:
            return plan(route, "Reading Luscious media", options: options) { [registry] in
                try await registry.lusciousResolver.resolve(
                    url,
                    headers: headers,
                    assetLimit: options.assetLimit
                )
            }
        case .soundCloud:
            return plan(route, "Reading SoundCloud audio", options: options) { [registry] in
                try await registry.soundCloudResolver.resolve(
                    url,
                    headers: headers,
                    assetLimit: options.assetLimit
                )
            }
        case .tikTok:
            return plan(route, "Reading TikTok video", fallback: .ytDLP) { [registry] in
                try await registry.tikTokResolver.resolve(url, headers: headers)
            }
        case .twitterCollection:
            guard let waitForAuthentication = context.waitForAuthentication else {
                return nil
            }
            return plan(
                route,
                "Reading Twitter profile media",
                options: options,
                fallback: .ytDLP
            ) { [registry, authenticationCoordinator] in
                try await authenticationCoordinator.resolve(
                    operation: {
                        try await registry.twitterCollectionResolver.resolve(
                            url,
                            headers: headers,
                            rangeExpression: options.rangeExpression
                        )
                    },
                    authenticationRequest: { error in
                        guard let resolverError = error as? TwitterCollectionResolverError,
                              case .authenticationRequired = resolverError else {
                            return nil
                        }
                        return SourceResolverAuthenticationRequest.twitter
                    },
                    waitForAuthentication: { request in
                        await waitForAuthentication(request)
                    },
                    ensureActive: context.ensureActive
                )
            }
        case .twitter:
            guard let waitForAuthentication = context.waitForAuthentication else {
                return nil
            }
            return plan(
                route,
                "Reading Twitter media",
                fallback: .ytDLP
            ) { [registry, authenticationCoordinator] in
                try await authenticationCoordinator.resolve(
                    operation: {
                        try await registry.twitterResolver.resolve(
                            url,
                            headers: headers
                        )
                    },
                    authenticationRequest: { error in
                        guard let resolverError = error as? TwitterGraphQLAPIError,
                              case .authenticationRequired = resolverError else {
                            return nil
                        }
                        return SourceResolverAuthenticationRequest.twitter
                    },
                    waitForAuthentication: { request in
                        await waitForAuthentication(request)
                    },
                    ensureActive: context.ensureActive
                )
            }
        case .fediverse:
            return plan(route, "Reading Fediverse media", options: options) { [registry] in
                try await registry.fediverseResolver.resolve(
                    url,
                    headers: headers,
                    assetLimit: options.assetLimit
                )
            }
        case .bilibili:
            return plan(route, "Reading Bilibili video", fallback: .ytDLP) { [registry] in
                try await registry.bilibiliResolver.resolve(url, headers: headers)
            }
        case .flickr:
            return plan(route, "Reading Flickr page", options: options) { [registry] in
                try await registry.flickrResolver.resolve(
                    url,
                    headers: headers,
                    rangeExpression: options.rangeExpression
                )
            }
        case .pinterest:
            return plan(route, "Reading Pinterest media", options: options) { [registry] in
                try await registry.pinterestResolver.resolve(
                    url,
                    headers: headers,
                    pinLimit: options.assetLimit
                )
            }
        case .nijie:
            return plan(route, "Reading Nijie illustrations", options: options) { [registry] in
                try await registry.nijieResolver.resolve(
                    url,
                    headers: headers,
                    rangeExpression: options.rangeExpression
                )
            }
        case .nozomi:
            return plan(route, "Reading Nozomi posts", options: options) { [registry] in
                try await registry.nozomiResolver.resolve(
                    url,
                    headers: headers,
                    rangeExpression: options.rangeExpression
                )
            }
        case .v2ph:
            return plan(route, "Reading V2PH album", options: options) { [registry] in
                try await registry.v2phResolver.resolve(
                    url,
                    headers: headers,
                    assetLimit: options.assetLimit
                )
            }
        case .hentaiCosplay:
            return plan(route, "Reading Hentai Cosplay media", options: options) { [registry] in
                try await registry.hentaiCosplayResolver.resolve(
                    url,
                    headers: headers,
                    assetLimit: options.assetLimit
                )
            }
        case .hentaiFoundry:
            return plan(route, "Reading Hentai Foundry media", options: options) { [registry] in
                try await registry.hentaiFoundryResolver.resolve(
                    url,
                    headers: headers,
                    postLimit: options.assetLimit
                )
            }
        case .bcy:
            return plan(route, "Reading BCY post", options: options) { [registry] in
                try await registry.bcyResolver.resolve(
                    url,
                    headers: headers,
                    assetLimit: options.assetLimit
                )
            }
        case .weiboStatus:
            return plan(route, "Reading Weibo status", options: options) { [registry] in
                try await registry.weiboStatusResolver.resolve(
                    url,
                    headers: headers,
                    assetLimit: options.assetLimit
                )
            }
        case .webtoon:
            return plan(route, "Reading WEBTOON episode", options: options) { [registry] in
                try await registry.webtoonResolver.resolve(
                    url,
                    headers: headers,
                    rangeExpression: options.rangeExpression
                )
            }
        case .naverWebtoon:
            return plan(route, "Reading Naver Webtoon episode", options: options) { [registry] in
                try await registry.naverWebtoonResolver.resolve(
                    url,
                    headers: headers,
                    rangeExpression: options.rangeExpression
                )
            }
        case .lezhin:
            return plan(route, "Reading Lezhin comic", options: options) { [registry] in
                try await registry.lezhinResolver.resolve(
                    url,
                    headers: headers,
                    rangeExpression: options.rangeExpression
                )
            }
        case .kakaoPage:
            return plan(route, "Reading KakaoPage", options: options) { [registry] in
                try await registry.kakaoPageResolver.resolve(
                    url,
                    headers: headers,
                    rangeExpression: options.rangeExpression
                )
            }
        case .comicWalker:
            return plan(route, "Reading ComicWalker episode", options: options) { [registry] in
                try await registry.comicWalkerResolver.resolve(
                    url,
                    headers: headers,
                    rangeExpression: options.rangeExpression
                )
            }
        case .sankaku:
            return plan(route, "Reading Sankaku media", options: options) { [registry] in
                try await registry.sankakuResolver.resolve(
                    url,
                    headers: headers,
                    assetLimit: options.assetLimit
                )
            }
        case .booru:
            return plan(route, "Reading booru metadata", options: options) { [registry] in
                try await registry.booruResolver.resolve(
                    url,
                    headers: headers,
                    assetLimit: options.assetLimit
                )
            }
        case .avgle:
            return plan(route, "Reading Avgle extension data", options: options) { [registry] in
                try await registry.avgleResolver.resolve(
                    url,
                    metadata: options.metadata,
                    headers: headers
                )
            }
        case .tokyoMotion:
            return plan(route, "Reading TokyoMotion media", fallback: .ytDLP) { [registry] in
                try await registry.tokyoMotionResolver.resolve(url, headers: headers)
            }
        case .etcVideoPage:
            return plan(route, "Reading video page", fallback: .ytDLP) { [registry] in
                try await registry.etcVideoPageResolver.resolve(url, headers: headers)
            }
        case .naverTV:
            return plan(route, "Reading Naver TV", fallback: .ytDLP) { [registry] in
                try await registry.naverTVResolver.resolve(url, headers: headers)
            }
        case .facebookPhoto:
            return plan(route, "Reading Facebook photo", fallback: .ytDLP) { [registry] in
                try await registry.facebookPhotoResolver.resolve(url, headers: headers)
            }
        case .facebookVideo:
            return plan(route, "Reading Facebook video", fallback: .ytDLP) { [registry] in
                try await registry.facebookVideoResolver.resolve(url, headers: headers)
            }
        case .kakaoTV:
            return plan(route, "Reading KakaoTV", fallback: .ytDLP) { [registry] in
                try await registry.kakaoTVResolver.resolve(url, headers: headers)
            }
        case .vLive:
            return plan(route, "Reading V LIVE", fallback: .ytDLP) { [registry] in
                try await registry.vLiveResolver.resolve(url, headers: headers)
            }
        case .bilibiliCollection:
            return plan(
                route,
                "Reading Bilibili collection",
                options: options,
                fallback: .ytDLP
            ) { [registry] in
                try await registry.bilibiliCollectionResolver.resolve(
                    url,
                    headers: headers,
                    rangeExpression: options.rangeExpression
                )
            }
        case .xVideoCollection:
            return plan(
                route,
                "Reading XVideos channel",
                options: options,
                fallback: .ytDLP
            ) { [registry] in
                try await registry.xVideoCollectionResolver.resolve(
                    url,
                    headers: headers,
                    rangeExpression: options.rangeExpression
                )
            }
        case .xHamsterCollection:
            return plan(
                route,
                "Reading xHamster channel",
                options: options,
                fallback: .ytDLP
            ) { [registry] in
                try await registry.xHamsterCollectionResolver.resolve(
                    url,
                    headers: headers,
                    rangeExpression: options.rangeExpression
                )
            }
        case .iwaraCollection:
            return plan(
                route,
                "Reading Iwara profile",
                options: options,
                fallback: .ytDLP
            ) { [registry] in
                try await registry.iwaraCollectionResolver.resolve(
                    url,
                    headers: headers,
                    rangeExpression: options.rangeExpression
                )
            }
        case .kissJAV:
            return plan(
                route,
                "Reading KissJAV video",
                options: options,
                fallback: .ytDLP
            ) { [registry] in
                try await registry.kissJAVResolver.resolve(
                    url,
                    headers: headers,
                    preferredResolution: options.media.preferredResolution
                )
            }
        case .chzzkCollection:
            return plan(
                route,
                "Reading Chzzk videos",
                options: options,
                fallback: .ytDLP
            ) { [registry] in
                try await registry.chzzkCollectionResolver.resolve(
                    url,
                    headers: headers,
                    preferredResolution: options.media.preferredResolution,
                    rangeExpression: options.rangeExpression
                )
            }
        case .chzzk:
            guard let waitForAuthentication = context.waitForAuthentication else {
                return nil
            }
            return plan(
                route,
                "Reading Chzzk media",
                options: options
            ) { [registry, authenticationCoordinator] in
                try await authenticationCoordinator.resolve(
                    operation: {
                        try await registry.chzzkResolver.resolve(
                            url,
                            headers: headers,
                            preferredResolution: options.media.preferredResolution
                        )
                    },
                    authenticationRequest: { error in
                        guard let resolverError = error as? ChzzkResolverError,
                              case .authenticationRequired = resolverError else {
                            return nil
                        }
                        return SourceResolverAuthenticationRequest.chzzk
                    },
                    waitForAuthentication: { request in
                        await waitForAuthentication(request)
                    },
                    ensureActive: context.ensureActive
                )
            }
        case .hanime:
            return plan(
                route,
                "Reading Hanime video",
                options: options,
                fallback: .ytDLP
            ) { [registry] in
                try await registry.hanimeResolver.resolve(
                    url,
                    headers: headers,
                    preferredResolution: options.media.preferredResolution
                )
            }
        case .instagram:
            return plan(
                route,
                "Reading Instagram media",
                options: options,
                fallback: .ytDLP
            ) { [registry] in
                try await registry.instagramResolver.resolve(
                    url,
                    headers: headers,
                    includeProfileStories: options.media.includeInstagramStories,
                    rangeExpression: options.rangeExpression
                )
            }
        case .facebookPhotoCollection:
            return plan(
                route,
                "Reading Facebook photos",
                options: options,
                fallback: .ytDLP
            ) { [registry] in
                try await registry.facebookPhotoCollectionResolver.resolve(
                    url,
                    headers: headers,
                    rangeExpression: options.rangeExpression
                )
            }
        case .twitchClipCollection:
            return plan(
                route,
                "Reading Twitch clips",
                options: options,
                fallback: .ytDLP
            ) { [registry] in
                try await registry.twitchClipCollectionResolver.resolve(
                    url,
                    headers: headers,
                    preferredResolution: options.media.preferredResolution,
                    rangeExpression: options.rangeExpression
                )
            }
        case .twitchVOD:
            return plan(
                route,
                "Reading Twitch media",
                options: options,
                fallback: .ytDLP
            ) { [registry] in
                try await registry.twitchVODResolver.resolve(
                    url,
                    headers: headers,
                    preferredResolution: options.media.preferredResolution
                )
            }
        case .soopVOD:
            return plan(
                route,
                "Reading SOOP media",
                options: options,
                fallback: .ytDLP
            ) { [registry] in
                try await registry.soopVODResolver.resolve(
                    url,
                    headers: headers,
                    preferredResolution: options.media.soopPreferredResolution
                )
            }
        case .youtubeCollection:
            return plan(
                route,
                "Reading YouTube collection",
                options: options,
                fallback: .ytDLP
            ) { [registry] in
                try await registry.youtubeCollectionResolver.resolve(
                    url,
                    headers: headers,
                    preferredResolution: options.media.preferredResolution,
                    codecPriority: options.media.youtubeCodecPriority,
                    reverse: options.media.reverseYouTubePlaylist,
                    numberPlaylistFiles: options.media.numberPlaylistFiles,
                    rangeExpression: options.rangeExpression
                )
            }
        case .youtube:
            return plan(
                route,
                "Reading YouTube",
                options: options,
                fallback: .ytDLP
            ) { [registry] in
                try await registry.youtubeResolver.resolve(
                    url,
                    headers: headers,
                    preferredResolution: options.media.preferredResolution,
                    codecPriority: options.media.youtubeCodecPriority
                )
            }
        case .niconicoLive:
            return plan(
                route,
                "Reading Niconico Live",
                options: options,
                fallback: .ytDLP,
                downloadFailureCleanup: .niconicoLiveSession(
                    metadataKey: "niconico_live_session_token"
                )
            ) { [registry] in
                try await registry.niconicoLiveResolver.resolve(
                    url,
                    headers: headers,
                    preferredResolution: options.media.preferredResolution
                )
            }
        case .niconico:
            return plan(
                route,
                "Reading Niconico",
                options: options,
                fallback: .ytDLP
            ) { [registry] in
                try await registry.niconicoResolver.resolve(
                    url,
                    headers: headers,
                    preferredResolution: options.media.preferredResolution
                )
            }
        }
    }

    func cleanUpAfterDownloadFailure(
        for plan: SourceResolverExecutionPlan,
        resolved: ResolvedDownload
    ) async {
        switch plan.downloadFailureCleanup {
        case .none:
            return
        case .niconicoLiveSession(let metadataKey):
            guard let token = resolved.metadata[metadataKey] else { return }
            await registry.niconicoLiveResolver.stopSession(token)
        }
    }

    nonisolated static func hitomiFallbackStatus() -> String {
        "Hitomi gallery unavailable; checking E-Hentai"
    }

    nonisolated static func hitomiCompletionStatus(
        for selectedSource: EHentaiSelectedSource
    ) -> String {
        selectedSource == .hitomi
            ? "Using Hitomi gallery"
            : "Using original E-Hentai source"
    }

    nonisolated static func eHentaiInitialStatus(
        for sourceMode: EHentaiSourceMode
    ) -> String {
        switch sourceMode {
        case .automatic:
            return "Checking Hitomi mirror"
        case .hitomi:
            return "Reading Hitomi mirror"
        case .original:
            return "Reading E-Hentai gallery"
        }
    }

    nonisolated static func eHentaiFallbackStatus() -> String {
        "Hitomi mirror not found; reading E-Hentai gallery"
    }

    nonisolated static func eHentaiCompletionStatus(
        for selectedSource: EHentaiSelectedSource,
        usedFallback: Bool
    ) -> String {
        switch selectedSource {
        case .hitomi:
            return "Using Hitomi mirror"
        case .original:
            return usedFallback
                ? "Using original E-Hentai source"
                : "Reading E-Hentai gallery"
        }
    }

    private func plan(
        _ route: SourceResolverRoute,
        _ statusMessage: String,
        options: SourceResolverExecutionOptions = SourceResolverExecutionOptions(),
        fallback: SourceResolverExecutionFallback = .none,
        downloadFailureCleanup: SourceResolverDownloadFailureCleanup = .none,
        operation: @escaping @MainActor () async throws -> ResolvedDownload
    ) -> SourceResolverExecutionPlan {
        SourceResolverExecutionPlan(
            route: route,
            statusMessage: statusMessage,
            options: options,
            fallback: fallback,
            downloadFailureCleanup: downloadFailureCleanup,
            operation: operation
        )
    }

    private func resultPlan(
        _ route: SourceResolverRoute,
        _ statusMessage: String,
        options: SourceResolverExecutionOptions = SourceResolverExecutionOptions(),
        fallback: SourceResolverExecutionFallback = .none,
        downloadFailureCleanup: SourceResolverDownloadFailureCleanup = .none,
        operation: @escaping @MainActor () async throws -> SourceResolverExecutionResult
    ) -> SourceResolverExecutionPlan {
        SourceResolverExecutionPlan(
            route: route,
            statusMessage: statusMessage,
            options: options,
            fallback: fallback,
            downloadFailureCleanup: downloadFailureCleanup,
            resultOperation: operation
        )
    }
}

import Foundation

protocol SearchResultResolving {
    func supports(_ baseURL: URL) -> Bool
    func extract(from context: SearchResultResolverContext) -> [SearchResultLink]
}

struct SearchResultResolverContext {
    let anchors: [AnchorEntry]
    let baseURL: URL
    let limit: Int

    private let resolveHref: (String, URL) -> URL?
    private let titleProvider: (AnchorEntry, URL) -> String
    private let fallbackTitleProvider: (AnchorEntry, String) -> String
    private let contributorMetadataProvider: (
        AnchorEntry,
        String?,
        String?,
        String?
    ) -> [String: String]
    private let embeddedImageAttributesProvider: (AnchorEntry) -> [String: String]
    private let semanticAttributesProvider: (AnchorEntry) -> [String: String]
    private let canonicalQueueURLProvider: (URL) -> URL
    private let nestedAnchorsProvider: (String) -> [AnchorEntry]
    private let bodyTextProvider: (AnchorEntry) -> String
    private let embeddedImageTitleProvider: (AnchorEntry) -> String?
    private let tagAttributesProvider: (String) -> [String: String]

    init(
        anchors: [AnchorEntry],
        baseURL: URL,
        limit: Int,
        resolveHref: @escaping (String, URL) -> URL?,
        titleProvider: @escaping (AnchorEntry, URL) -> String,
        fallbackTitleProvider: @escaping (AnchorEntry, String) -> String,
        contributorMetadataProvider: @escaping (
            AnchorEntry,
            String?,
            String?,
            String?
        ) -> [String: String],
        embeddedImageAttributesProvider: @escaping (AnchorEntry) -> [String: String],
        semanticAttributesProvider: @escaping (AnchorEntry) -> [String: String],
        canonicalQueueURLProvider: @escaping (URL) -> URL,
        nestedAnchorsProvider: @escaping (String) -> [AnchorEntry],
        bodyTextProvider: @escaping (AnchorEntry) -> String,
        embeddedImageTitleProvider: @escaping (AnchorEntry) -> String?,
        tagAttributesProvider: @escaping (String) -> [String: String]
    ) {
        self.anchors = anchors
        self.baseURL = baseURL
        self.limit = limit
        self.resolveHref = resolveHref
        self.titleProvider = titleProvider
        self.fallbackTitleProvider = fallbackTitleProvider
        self.contributorMetadataProvider = contributorMetadataProvider
        self.embeddedImageAttributesProvider = embeddedImageAttributesProvider
        self.semanticAttributesProvider = semanticAttributesProvider
        self.canonicalQueueURLProvider = canonicalQueueURLProvider
        self.nestedAnchorsProvider = nestedAnchorsProvider
        self.bodyTextProvider = bodyTextProvider
        self.embeddedImageTitleProvider = embeddedImageTitleProvider
        self.tagAttributesProvider = tagAttributesProvider
    }

    func resolvedURL(for anchor: AnchorEntry) -> URL? {
        guard let href = anchor.attributes["href"]?.trimmed else { return nil }
        return resolveHref(href, baseURL)
    }

    func resolvedURL(
        for anchor: AnchorEntry,
        relativeTo baseURL: URL
    ) -> URL? {
        guard let href = anchor.attributes["href"]?.trimmed else { return nil }
        return resolveHref(href, baseURL)
    }

    func title(for anchor: AnchorEntry, fallbackURL: URL) -> String {
        titleProvider(anchor, fallbackURL)
    }

    func title(for anchor: AnchorEntry, fallback: String) -> String {
        fallbackTitleProvider(anchor, fallback)
    }

    func contributorMetadata(for anchor: AnchorEntry) -> [String: String] {
        contributorMetadataProvider(anchor, nil, nil, nil)
    }

    func contributorMetadata(
        for anchor: AnchorEntry,
        fallbackName: String?,
        fallbackUsername: String?,
        fallbackUserID: String? = nil
    ) -> [String: String] {
        contributorMetadataProvider(
            anchor,
            fallbackName,
            fallbackUsername,
            fallbackUserID
        )
    }

    func semanticAttributes(for anchor: AnchorEntry) -> [String: String] {
        semanticAttributesProvider(anchor)
    }

    func attributesIncludingEmbeddedImage(for anchor: AnchorEntry) -> [String: String] {
        embeddedImageAttributesProvider(anchor)
    }

    func canonicalQueueURL(for url: URL) -> URL {
        canonicalQueueURLProvider(url)
    }

    func nestedAnchors(in html: String) -> [AnchorEntry] {
        nestedAnchorsProvider(html)
    }

    func bodyText(for anchor: AnchorEntry) -> String {
        bodyTextProvider(anchor)
    }

    func embeddedImageTitle(for anchor: AnchorEntry) -> String? {
        embeddedImageTitleProvider(anchor)
    }

    func attributes(inTag tag: String) -> [String: String] {
        tagAttributesProvider(tag)
    }
}

struct SearchResultResolverRegistry {
    enum PriorityDataAttributeResolution {
        case unhandled
        case handled(String?)
    }

    static let standard = SearchResultResolverRegistry(resolvers: [
        GoogleSearchResultResolver(),
        GallerySearchResultResolver(),
        MediaSearchResultResolver(),
        LiteratureSearchResultResolver(),
        FC2SearchResultResolver(),
        FlickrSearchResultResolver(),
        FourChanSearchResultResolver(),
        WikiArtSearchResultResolver(),
        SankakuSearchResultResolver(),
        NijieSearchResultResolver(),
        V2PHSearchResultResolver(),
        HentaiCosplaySearchResultResolver(),
        HentaiFoundrySearchResultResolver(),
        TalkOPGGSearchResultResolver(),
        AsmHentaiSearchResultResolver(),
        MyReadingMangaSearchResultResolver(),
        LusciousSearchResultResolver(),
        BDSMlrSearchResultResolver(),
        NaverBlogSearchResultResolver(),
        NaverPostSearchResultResolver(),
        NaverCafeSearchResultResolver(),
        NaverTVSearchResultResolver(),
        WebtoonSearchResultResolver(),
        NaverWebtoonSearchResultResolver(),
        PixivComicSearchResultResolver(),
        KakaoPageSearchResultResolver(),
        KakaoWebtoonSearchResultResolver(),
        HiyobiSearchResultResolver(),
        ManatokiSearchResultResolver(),
        LHScanSearchResultResolver(),
        JManaSearchResultResolver(),
        WaybackSearchResultResolver(),
        ImgurSearchResultResolver(),
        TumblrSearchResultResolver(),
        XVideoSearchResultResolver(),
        SpankBangSearchResultResolver(),
        WeiboSearchResultResolver(),
        PornhubSearchResultResolver(),
        FacebookSearchResultResolver(),
        InstagramSearchResultResolver(),
        IwaraSearchResultResolver(),
        TwitchSearchResultResolver(),
        NiconicoSearchResultResolver(),
        KakaoTVSearchResultResolver(),
        SOOPSearchResultResolver(),
        ChzzkSearchResultResolver(),
        BilibiliSearchResultResolver(),
        TikTokSearchResultResolver(),
        TwitterSearchResultResolver(),
        YouTubeSearchResultResolver(),
        NewgroundsSearchResultResolver(),
        PinterestSearchResultResolver(),
        DeviantArtSearchResultResolver(),
        BCYSearchResultResolver(),
        ArtStationSearchResultResolver(),
        PixivSearchResultResolver(),
        HitomiSearchResultResolver(),
        BooruSearchResultResolver(),
        FediverseSearchResultResolver(),
        EtcVideoSearchResultResolver()
    ])
    static let originalMediaFallback = SearchResultResolverRegistry(
        resolvers: [OriginalYTDLPMediaSearchResultResolver()]
    )

    static func priorityDataAttributeResolution(
        in attributes: [String: String],
        baseURL: URL?
    ) -> PriorityDataAttributeResolution {
        if let link = WaybackSearchResultResolver.dataAttributeLinkValue(
            in: attributes,
            baseURL: baseURL
        ) {
            return .handled(link)
        }
        if let host = baseURL?.host?.lowercased(),
           GoogleSearchResultResolver.isGoogleHost(host) {
            return .handled(
                GoogleSearchResultResolver.dataAttributeLinkValue(
                    in: attributes,
                    baseURL: baseURL
                )
            )
        }
        return .unhandled
    }

    static func canonicalQueueURL(for url: URL) -> URL {
        YouTubeSearchResultResolver.queueURL(from: url) ?? url
    }

    static func dataAttributeLinkValue(
        in attributes: [String: String],
        baseURL: URL?
    ) -> String? {
        if let link = HitomiSearchResultResolver.dataAttributeLinkValue(
            in: attributes,
            baseURL: baseURL
        ) {
            return link
        }
        if let link = GallerySearchResultResolver.dataAttributeLinkValue(
            in: attributes,
            baseURL: baseURL
        ) {
            return link
        }
        if let link = BooruSearchResultResolver.dataAttributeLinkValue(
            in: attributes,
            baseURL: baseURL
        ) {
            return link
        }
        if let link = ArtStationSearchResultResolver.dataAttributeLinkValue(
            in: attributes,
            baseURL: baseURL
        ) {
            return link
        }
        if let link = BCYSearchResultResolver.dataAttributeLinkValue(
            in: attributes,
            baseURL: baseURL
        ) {
            return link
        }
        if let link = FC2SearchResultResolver.dataAttributeLinkValue(
            in: attributes,
            baseURL: baseURL
        ) {
            return link
        }
        if let link = PinterestSearchResultResolver.dataAttributeLinkValue(
            in: attributes,
            baseURL: baseURL
        ) {
            return link
        }
        if let link = DeviantArtSearchResultResolver.dataAttributeLinkValue(
            in: attributes,
            baseURL: baseURL
        ) {
            return link
        }
        if let link = NewgroundsSearchResultResolver.dataAttributeLinkValue(
            in: attributes,
            baseURL: baseURL
        ) {
            return link
        }
        if let link = FlickrSearchResultResolver.dataAttributeLinkValue(
            in: attributes,
            baseURL: baseURL
        ) {
            return link
        }
        if let link = MediaSearchResultResolver.dataAttributeLinkValue(
            in: attributes,
            baseURL: baseURL
        ) {
            return link
        }
        if let link = KakaoTVSearchResultResolver.dataAttributeLinkValue(
            in: attributes,
            baseURL: baseURL
        ) {
            return link
        }
        if let link = TwitterSearchResultResolver.dataAttributeLinkValue(
            in: attributes,
            baseURL: baseURL
        ) {
            return link
        }
        if let link = TikTokSearchResultResolver.dataAttributeLinkValue(
            in: attributes,
            baseURL: baseURL
        ) {
            return link
        }
        if let link = BilibiliSearchResultResolver.dataAttributeLinkValue(
            in: attributes,
            baseURL: baseURL
        ) {
            return link
        }
        if let link = ChzzkSearchResultResolver.dataAttributeLinkValue(
            in: attributes,
            baseURL: baseURL
        ) {
            return link
        }
        if let link = SOOPSearchResultResolver.dataAttributeLinkValue(
            in: attributes,
            baseURL: baseURL
        ) {
            return link
        }
        if let link = NiconicoSearchResultResolver.dataAttributeLinkValue(
            in: attributes,
            baseURL: baseURL
        ) {
            return link
        }
        if let link = TwitchSearchResultResolver.dataAttributeLinkValue(
            in: attributes,
            baseURL: baseURL
        ) {
            return link
        }
        if let link = IwaraSearchResultResolver.dataAttributeLinkValue(
            in: attributes,
            baseURL: baseURL
        ) {
            return link
        }
        if let link = InstagramSearchResultResolver.dataAttributeLinkValue(
            in: attributes,
            baseURL: baseURL
        ) {
            return link
        }
        if let link = FacebookSearchResultResolver.dataAttributeLinkValue(
            in: attributes,
            baseURL: baseURL
        ) {
            return link
        }
        if let link = PornhubSearchResultResolver.dataAttributeLinkValue(
            in: attributes,
            baseURL: baseURL
        ) {
            return link
        }
        if let link = WeiboSearchResultResolver.dataAttributeLinkValue(
            in: attributes,
            baseURL: baseURL
        ) {
            return link
        }
        if let link = SpankBangSearchResultResolver.dataAttributeLinkValue(
            in: attributes,
            baseURL: baseURL
        ) {
            return link
        }
        if let link = XVideoSearchResultResolver.dataAttributeLinkValue(
            in: attributes,
            baseURL: baseURL
        ) {
            return link
        }
        if let link = EtcVideoSearchResultResolver.dataAttributeLinkValue(
            in: attributes,
            baseURL: baseURL
        ) {
            return link
        }
        if let link =
            OriginalYTDLPMediaSearchResultResolver.dataAttributeLinkValue(
                in: attributes,
                baseURL: baseURL
            ) {
            return link
        }
        if let link = ImgurSearchResultResolver.dataAttributeLinkValue(
            in: attributes,
            baseURL: baseURL
        ) {
            return link
        }
        if let link = TumblrSearchResultResolver.dataAttributeLinkValue(
            in: attributes,
            baseURL: baseURL
        ) {
            return link
        }
        if let link = FourChanSearchResultResolver.dataAttributeLinkValue(
            in: attributes,
            baseURL: baseURL
        ) {
            return link
        }
        if let link = WikiArtSearchResultResolver.dataAttributeLinkValue(
            in: attributes,
            baseURL: baseURL
        ) {
            return link
        }
        if let link = FediverseSearchResultResolver.dataAttributeLinkValue(
            in: attributes,
            baseURL: baseURL
        ) {
            return link
        }
        if let link = SankakuSearchResultResolver.dataAttributeLinkValue(
            in: attributes,
            baseURL: baseURL
        ) {
            return link
        }
        if let link = NijieSearchResultResolver.dataAttributeLinkValue(
            in: attributes,
            baseURL: baseURL
        ) {
            return link
        }
        if let link = V2PHSearchResultResolver.dataAttributeLinkValue(
            in: attributes,
            baseURL: baseURL
        ) {
            return link
        }
        if let link =
            HentaiCosplaySearchResultResolver.dataAttributeLinkValue(
                in: attributes,
                baseURL: baseURL
            ) {
            return link
        }
        if let link =
            HentaiFoundrySearchResultResolver.dataAttributeLinkValue(
                in: attributes,
                baseURL: baseURL
            ) {
            return link
        }
        if let link = TalkOPGGSearchResultResolver.dataAttributeLinkValue(
            in: attributes,
            baseURL: baseURL
        ) {
            return link
        }
        if let link = AsmHentaiSearchResultResolver.dataAttributeLinkValue(
            in: attributes,
            baseURL: baseURL
        ) {
            return link
        }
        if let link =
            MyReadingMangaSearchResultResolver.dataAttributeLinkValue(
                in: attributes,
                baseURL: baseURL
            ) {
            return link
        }
        if let link = LusciousSearchResultResolver.dataAttributeLinkValue(
            in: attributes,
            baseURL: baseURL
        ) {
            return link
        }
        if let link = BDSMlrSearchResultResolver.dataAttributeLinkValue(
            in: attributes,
            baseURL: baseURL
        ) {
            return link
        }
        if let link = LiteratureSearchResultResolver.dataAttributeLinkValue(
            in: attributes,
            baseURL: baseURL
        ) {
            return link
        }

        if let baseURL {
            if let link =
                NaverBlogSearchResultResolver.dataAttributeLinkValue(
                    in: attributes,
                    baseURL: baseURL
                ) {
                return link
            }
            if let link =
                NaverPostSearchResultResolver.dataAttributeLinkValue(
                    in: attributes,
                    baseURL: baseURL
                ) {
                return link
            }
            if let link =
                NaverCafeSearchResultResolver.dataAttributeLinkValue(
                    in: attributes,
                    baseURL: baseURL
                ) {
                return link
            }
            if let link =
                NaverTVSearchResultResolver.dataAttributeLinkValue(
                    in: attributes,
                    baseURL: baseURL
                ) {
                return link
            }
            if let link =
                WebtoonSearchResultResolver.dataAttributeLinkValue(
                    in: attributes,
                    baseURL: baseURL
                ) {
                return link
            }
            if let link =
                NaverWebtoonSearchResultResolver.dataAttributeLinkValue(
                    in: attributes,
                    baseURL: baseURL
                ) {
                return link
            }
            if let link =
                PixivComicSearchResultResolver.dataAttributeLinkValue(
                    in: attributes,
                    baseURL: baseURL
                ) {
                return link
            }
            if let link =
                KakaoPageSearchResultResolver.dataAttributeLinkValue(
                    in: attributes,
                    baseURL: baseURL
                ) {
                return link
            }
            if let link =
                KakaoWebtoonSearchResultResolver.dataAttributeLinkValue(
                    in: attributes,
                    baseURL: baseURL
                ) {
                return link
            }
            if let link =
                HiyobiSearchResultResolver.dataAttributeLinkValue(
                    in: attributes,
                    baseURL: baseURL
                ) {
                return link
            }
            if let link =
                ManatokiSearchResultResolver.dataAttributeLinkValue(
                    in: attributes,
                    baseURL: baseURL
                ) {
                return link
            }
            if let link =
                LHScanSearchResultResolver.dataAttributeLinkValue(
                    in: attributes,
                    baseURL: baseURL
                ) {
                return link
            }
            if let link =
                JManaSearchResultResolver.dataAttributeLinkValue(
                    in: attributes,
                    baseURL: baseURL
                ) {
                return link
            }
        }

        if let link = PixivSearchResultResolver.dataAttributeLinkValue(
            in: attributes,
            baseURL: baseURL
        ) {
            return link
        }
        if let link = YouTubeSearchResultResolver.dataAttributeLinkValue(
            in: attributes,
            baseURL: baseURL
        ) {
            return link
        }
        return nil
    }

    private let resolvers: [any SearchResultResolving]

    init(resolvers: [any SearchResultResolving]) {
        self.resolvers = resolvers
    }

    func extract(from context: SearchResultResolverContext) -> [SearchResultLink]? {
        guard let resolver = resolvers.first(where: { $0.supports(context.baseURL) }) else {
            return nil
        }
        let results = resolver.extract(from: context)
        return results.isEmpty ? nil : results
    }
}

enum SearchResultResolverSupport {
    static func appendUniqueResult(
        title: String,
        url: URL,
        id: String,
        sitePrefix: String,
        results: inout [SearchResultLink],
        indexByID: inout [String: Int],
        metadata extraMetadata: [String: String] = [:]
    ) {
        let metadata = DownloadMetadata.clean([
            "site": sitePrefix,
            "result_id": id,
            "source_url": url.absoluteString,
            "page_url": url.absoluteString,
            "search_site": sitePrefix,
            "search_result_id": id,
            "search_url": url.absoluteString
        ]).merging(DownloadMetadata.clean(extraMetadata)) { current, _ in current }

        if let existingIndex = indexByID[id] {
            if isWeakTitle(results[existingIndex].title, id: id, sitePrefix: sitePrefix),
               !isWeakTitle(title, id: id, sitePrefix: sitePrefix) {
                results[existingIndex].title = title
                results[existingIndex].metadata["title"] = title
                results[existingIndex].metadata["search_title"] = title
            }
            results[existingIndex].metadata = metadata.merging(results[existingIndex].metadata) { _, existing in existing }
            return
        }

        indexByID[id] = results.count
        results.append(SearchResultLink(
            title: title,
            url: url.absoluteString,
            siteIdentifier: sitePrefix,
            metadata: metadata
        ))
    }

    private static func isWeakTitle(_ title: String, id: String, sitePrefix: String) -> Bool {
        let value = title.trimmed.lowercased()
        return value.isEmpty ||
            value == "download" ||
            value == id ||
            value == "\(id).html" ||
            value == "\(sitePrefix) \(id)" ||
            value.contains("/\(id)")
    }
}

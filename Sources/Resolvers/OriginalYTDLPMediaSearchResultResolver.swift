import Foundation

struct OriginalYTDLPMediaSearchResultResolver: SearchResultResolving {
    func supports(_ baseURL: URL) -> Bool {
        guard let host = baseURL.host?.lowercased() else { return false }
        return Self.isSupportedHost(host)
    }

    func extract(
        from context: SearchResultResolverContext
    ) -> [SearchResultLink] {
        var results: [SearchResultLink] = []
        var indexByURL: [String: Int] = [:]

        for anchor in context.anchors {
            guard results.count < context.limit,
                  let absolute = context.resolvedURL(for: anchor),
                  let target = Self.mediaURL(from: absolute) else {
                continue
            }

            SearchResultResolverSupport.appendUniqueResult(
                title: context.title(for: anchor, fallbackURL: target),
                url: target,
                id: URLIdentity.normalize(target.absoluteString),
                sitePrefix: "media",
                results: &results,
                indexByID: &indexByURL
            )
        }

        return results
    }

    static func dataAttributeLinkValue(
        in attributes: [String: String],
        baseURL: URL?
    ) -> String? {
        guard let host = baseURL?.host?.lowercased(),
              isSupportedHost(host) else {
            return nil
        }

        if isAvgleHost(host),
           let id = dataAttributeVideoID(in: attributes),
           dataAttributeLooksLikeVideoCard(attributes) {
            return "/video/\(id)"
        }

        if isHanimeHost(host),
           let slug = dataAttributeSlug(in: attributes),
           dataAttributeLooksLikeVideoCard(attributes) {
            return "/videos/hentai/\(slug)"
        }

        if isKissJAVHost(host),
           let slug = dataAttributeSlug(in: attributes),
           dataAttributeLooksLikeVideoCard(attributes) {
            return "/videos/\(slug)"
        }

        if isTokyoMotionHost(host) {
            if let albumID = dataAttributeAlbumID(in: attributes),
               dataAttributeLooksLikeAlbumCard(attributes) {
                return "/album/\(albumID)"
            }
            if let id = dataAttributeVideoID(in: attributes),
               dataAttributeLooksLikeVideoCard(attributes) {
                return "/video/\(id)"
            }
        }

        if isThisVidHost(host),
           let slug = dataAttributeSlug(in: attributes),
           dataAttributeLooksLikeVideoCard(attributes) {
            return "/videos/\(slug)"
        }

        if isIxiguaHost(host),
           let id = dataAttributeIxiguaID(in: attributes),
           dataAttributeLooksLikeVideoCard(attributes) {
            return "/\(id)"
        }

        if isYourPornHost(host),
           let slug = dataAttributeSlug(in: attributes),
           dataAttributeLooksLikePostCard(attributes) {
            return "/post/\(slug)"
        }

        if isXHamsterHost(host) {
            if let galleryID = dataAttributeAlbumID(in: attributes),
               dataAttributeLooksLikeGalleryCard(attributes) {
                return "/photos/gallery/\(galleryID)"
            }
            if let slug = dataAttributeSlug(in: attributes),
               dataAttributeLooksLikeVideoCard(attributes) {
                return "/videos/\(slug)"
            }
        }

        if isYouPornHost(host),
           let id = dataAttributeVideoID(in: attributes),
           dataAttributeLooksLikeVideoCard(attributes) {
            return "/watch/\(id)"
        }

        if isYoukuHost(host),
           let id = dataAttributeYoukuID(in: attributes),
           dataAttributeLooksLikeVideoCard(attributes) {
            return "/v_show/id_\(id).html"
        }

        return nil
    }

    private static func mediaURL(from url: URL) -> URL? {
        guard let host = url.host?.lowercased(),
              isSupportedHost(host),
              let clean = cleanedURL(url) else {
            return nil
        }

        let parts = clean.path
            .split(separator: "/", omittingEmptySubsequences: true)
            .map(String.init)
        guard !parts.isEmpty else { return nil }
        let lower = parts.map { $0.lowercased() }

        if isAvgleHost(host) {
            return lower.first == "video" && parts.count >= 2
                ? clean
                : nil
        }

        if isHanimeHost(host) {
            if lower.count >= 3,
               lower[0] == "videos",
               lower[1] == "hentai" {
                return clean
            }
            if ["watch", "video"].contains(lower.first ?? ""),
               parts.count >= 2 {
                return clean
            }
            return nil
        }

        if isKissJAVHost(host) {
            return ["video", "videos"].contains(lower.first ?? "") &&
                parts.count >= 2
                ? clean
                : nil
        }

        if isTokyoMotionHost(host) {
            return TokyoMotionResolver.canonicalURL(for: clean)
        }

        if InstagramSearchResultResolver.isSupportedHost(host) {
            return InstagramResolver.canonicalInputURL(for: clean)
        }

        if FacebookSearchResultResolver.isSupportedHost(host) {
            return FacebookSearchResultResolver.mediaURL(from: url)
        }

        if KakaoTVSearchResultResolver.isSupportedHost(host) {
            return KakaoTVSearchResultResolver.mediaURL(from: url)
        }

        if IwaraSearchResultResolver.isSupportedHost(host) {
            return IwaraSearchResultResolver.mediaURL(from: clean)
        }

        if NiconicoSearchResultResolver.isSupportedHost(host) {
            return NiconicoSearchResultResolver.mediaURL(from: clean)
        }

        if TwitchSearchResultResolver.isSupportedHost(host) {
            return TwitchSearchResultResolver.mediaURL(from: clean)
        }

        if PornhubSearchResultResolver.isSupportedHost(host) {
            return PornhubSearchResultResolver.mediaURL(from: url)
        }

        if WeiboSearchResultResolver.isSupportedHost(host) {
            return WeiboSearchResultResolver.mediaURL(from: clean)
        }

        if SpankBangSearchResultResolver.isSupportedHost(host) {
            return spankBangMediaURL(from: clean)
        }

        if isThisVidHost(host) {
            return thisVidMediaURL(from: clean)
        }

        if isIxiguaHost(host) {
            return ixiguaMediaURL(from: clean)
        }

        if isYourPornHost(host) {
            return yourPornMediaURL(from: clean)
        }

        if isXHamsterHost(host) {
            return xHamsterMediaURL(from: clean)
        }

        if XVideoSearchResultResolver.isXNXXHost(host) ||
            XVideoSearchResultResolver.isXVideosHost(host) {
            return XVideoPageResolver.canonicalURL(for: clean)
        }

        if isYouPornHost(host) {
            return lower.first == "watch" && parts.count >= 2
                ? clean
                : nil
        }

        if isYoukuHost(host) {
            return (lower.first == "video" || lower.first == "v_show") &&
                parts.contains(where: { $0.hasPrefix("id_") })
                ? clean
                : nil
        }

        return nil
    }

    private static func xHamsterMediaURL(from url: URL) -> URL? {
        guard let clean = cleanedURL(url) else { return nil }
        let parts = clean.path
            .split(separator: "/", omittingEmptySubsequences: true)
            .map(String.init)
        let lower = parts.map { $0.lowercased() }

        if lower.first == "videos", parts.count >= 2 {
            return clean
        }

        if let photosIndex = lower.firstIndex(of: "photos"),
           photosIndex + 2 < parts.count,
           lower[photosIndex + 1] == "gallery",
           isValidPathSlug(parts[photosIndex + 2]) {
            let prefix = photosIndex > 0
                ? "/" + parts[..<photosIndex].joined(separator: "/")
                : ""
            return cleanedURL(
                clean,
                path: "\(prefix)/photos/gallery/\(parts[photosIndex + 2])"
            )
        }

        return nil
    }

    private static func spankBangMediaURL(from url: URL) -> URL? {
        guard let clean = cleanedURL(url) else { return nil }
        let parts = clean.path
            .split(separator: "/", omittingEmptySubsequences: true)
            .map(String.init)
        guard let first = parts.first, isValidPathSlug(first) else {
            return nil
        }
        let reserved = Set([
            "s", "search", "tag", "tags", "category", "categories",
            "users", "user", "channels", "channel", "pornstars",
            "playlist"
        ])
        return reserved.contains(first.lowercased()) ? nil : clean
    }

    private static func thisVidMediaURL(from url: URL) -> URL? {
        guard let clean = cleanedURL(url) else { return nil }
        let parts = clean.path
            .split(separator: "/", omittingEmptySubsequences: true)
            .map(String.init)
        let lower = parts.map { $0.lowercased() }
        guard let first = lower.first,
              ["video", "videos"].contains(first),
              parts.count >= 2,
              isValidPathSlug(parts[1]) else {
            return nil
        }
        return cleanedURL(clean, path: "/\(first)/\(parts[1])/") ?? clean
    }

    private static func ixiguaMediaURL(from url: URL) -> URL? {
        guard let clean = cleanedURL(url) else { return nil }
        let parts = clean.path
            .split(separator: "/", omittingEmptySubsequences: true)
            .map(String.init)
        let lower = parts.map { $0.lowercased() }

        if let id = parts.first,
           parts.count == 1,
           isIxiguaVideoID(id) {
            return cleanedURL(clean, path: "/\(id)") ?? clean
        }

        if lower.first == "video",
           parts.count >= 2,
           isIxiguaVideoID(parts[1]) {
            return cleanedURL(clean, path: "/video/\(parts[1])") ?? clean
        }

        return nil
    }

    private static func yourPornMediaURL(from url: URL) -> URL? {
        guard let clean = cleanedURL(url) else { return nil }
        let parts = clean.path
            .split(separator: "/", omittingEmptySubsequences: true)
            .map(String.init)
        let lower = parts.map { $0.lowercased() }
        guard ["post", "watch"].contains(lower.first ?? ""),
              parts.count >= 2,
              isValidPathSlug(parts[1]) else {
            return nil
        }
        return clean
    }

    private static func dataAttributeVideoID(
        in attributes: [String: String]
    ) -> String? {
        let keys = [
            "data-video-id", "data-videoid", "data-media-id",
            "data-mediaid", "data-content-id", "data-contentid",
            "video-id"
        ]
        if let value = firstAttributeValue(
            in: attributes,
            keys: keys,
            matching: isValidPathSlug
        ) {
            return value
        }
        if let id = attributes["data-id"]?.trimmed,
           isValidPathSlug(id),
           typeHint(
               in: attributes,
               containsAnyOf: ["video", "watch", "movie"]
           ) {
            return id
        }
        return nil
    }

    private static func dataAttributeSlug(
        in attributes: [String: String]
    ) -> String? {
        let keys = [
            "data-video-slug", "data-videoslug", "data-content-slug",
            "data-contentslug", "data-post-slug", "data-postslug",
            "data-title-slug", "data-slug", "slug"
        ]
        if let value = firstAttributeValue(
            in: attributes,
            keys: keys,
            matching: isValidPathSlug
        ) {
            return value
        }
        if let id = attributes["data-id"]?.trimmed,
           isValidPathSlug(id),
           typeHint(
               in: attributes,
               containsAnyOf: [
                   "video", "watch", "hentai", "movie", "post"
               ]
           ) {
            return id
        }
        return nil
    }

    private static func dataAttributeAlbumID(
        in attributes: [String: String]
    ) -> String? {
        let keys = [
            "data-album-id", "data-albumid", "data-gallery-id",
            "data-galleryid", "album-id"
        ]
        if let value = firstAttributeValue(
            in: attributes,
            keys: keys,
            matching: isValidPathSlug
        ) {
            return value
        }
        if let id = attributes["data-id"]?.trimmed,
           isValidPathSlug(id),
           typeHint(
               in: attributes,
               containsAnyOf: ["album", "gallery"]
           ) {
            return id
        }
        return nil
    }

    private static func dataAttributeIxiguaID(
        in attributes: [String: String]
    ) -> String? {
        let keys = [
            "data-video-id", "data-videoid", "data-group-id",
            "data-groupid", "data-item-id", "data-itemid", "video-id"
        ]
        if let value = firstAttributeValue(
            in: attributes,
            keys: keys,
            matching: isIxiguaVideoID
        ) {
            return value
        }
        if let id = attributes["data-id"]?.trimmed,
           isIxiguaVideoID(id),
           typeHint(
               in: attributes,
               containsAnyOf: ["video", "watch"]
           ) {
            return id
        }
        return nil
    }

    private static func dataAttributeYoukuID(
        in attributes: [String: String]
    ) -> String? {
        let keys = [
            "data-video-id", "data-videoid", "data-show-id",
            "data-showid", "video-id"
        ]
        let predicate: (String) -> Bool = {
            normalizedYoukuID($0) != nil
        }
        if let value = firstAttributeValue(
            in: attributes,
            keys: keys,
            matching: predicate
        ),
           let id = normalizedYoukuID(value) {
            return id
        }
        if let raw = attributes["data-id"]?.trimmed,
           let id = normalizedYoukuID(raw),
           typeHint(
               in: attributes,
               containsAnyOf: ["video", "watch", "youku"]
           ) {
            return id
        }
        return nil
    }

    private static func normalizedYoukuID(_ value: String) -> String? {
        var id = value.trimmed
        if id.lowercased().hasPrefix("id_") {
            id = String(id.dropFirst(3))
        }
        id = id.replacingOccurrences(
            of: ".html",
            with: "",
            options: [.caseInsensitive]
        )
        guard isValidPathSlug(id) else { return nil }
        return id
    }

    private static func dataAttributeLooksLikeVideoCard(
        _ attributes: [String: String]
    ) -> Bool {
        let keys = [
            "data-video-id", "data-videoid", "data-video-slug",
            "data-videoslug", "data-content-id", "data-contentid",
            "data-content-slug", "data-contentslug", "data-media-id",
            "data-mediaid", "data-group-id", "data-groupid",
            "data-item-id", "data-itemid", "data-show-id",
            "data-showid", "video-id"
        ]
        if keys.contains(where: {
            attributes[$0]?.trimmed.isEmpty == false
        }) {
            return true
        }
        return typeHint(
            in: attributes,
            containsAnyOf: ["video", "watch", "hentai", "movie"]
        )
    }

    private static func dataAttributeLooksLikeAlbumCard(
        _ attributes: [String: String]
    ) -> Bool {
        let keys = ["data-album-id", "data-albumid", "album-id"]
        if keys.contains(where: {
            attributes[$0]?.trimmed.isEmpty == false
        }) {
            return true
        }
        return typeHint(in: attributes, containsAnyOf: ["album"])
    }

    private static func dataAttributeLooksLikeGalleryCard(
        _ attributes: [String: String]
    ) -> Bool {
        let keys = [
            "data-gallery-id", "data-galleryid", "data-album-id",
            "data-albumid", "gallery-id", "album-id"
        ]
        if keys.contains(where: {
            attributes[$0]?.trimmed.isEmpty == false
        }) {
            return true
        }
        return typeHint(
            in: attributes,
            containsAnyOf: ["gallery", "album"]
        )
    }

    private static func dataAttributeLooksLikePostCard(
        _ attributes: [String: String]
    ) -> Bool {
        let keys = [
            "data-post-id", "data-postid", "data-post-slug",
            "data-postslug"
        ]
        if keys.contains(where: {
            attributes[$0]?.trimmed.isEmpty == false
        }) {
            return true
        }
        return typeHint(
            in: attributes,
            containsAnyOf: ["post", "video", "watch"]
        )
    }

    private static func isSupportedHost(_ host: String) -> Bool {
        isAvgleHost(host) ||
            isHanimeHost(host) ||
            isKissJAVHost(host) ||
            isTokyoMotionHost(host) ||
            InstagramSearchResultResolver.isSupportedHost(host) ||
            FacebookSearchResultResolver.isSupportedHost(host) ||
            KakaoTVSearchResultResolver.isSupportedHost(host) ||
            IwaraSearchResultResolver.isSupportedHost(host) ||
            NiconicoSearchResultResolver.isSupportedHost(host) ||
            TwitchSearchResultResolver.isSupportedHost(host) ||
            PornhubSearchResultResolver.isSupportedHost(host) ||
            WeiboSearchResultResolver.isSupportedHost(host) ||
            SpankBangSearchResultResolver.isSupportedHost(host) ||
            isThisVidHost(host) ||
            isIxiguaHost(host) ||
            isYourPornHost(host) ||
            isXHamsterHost(host) ||
            XVideoSearchResultResolver.isXNXXHost(host) ||
            XVideoSearchResultResolver.isXVideosHost(host) ||
            isYouPornHost(host) ||
            isYoukuHost(host)
    }

    private static func isAvgleHost(_ host: String) -> Bool {
        host == "avgle.com" ||
            host == "www.avgle.com" ||
            host == "avgle.test" ||
            host == "www.avgle.test"
    }

    private static func isHanimeHost(_ host: String) -> Bool {
        host == "hanime.tv" ||
            host == "www.hanime.tv" ||
            host == "hanime.test" ||
            host == "www.hanime.test"
    }

    private static func isKissJAVHost(_ host: String) -> Bool {
        KissJAVResolver.isSupportedHost(host)
    }

    private static func isTokyoMotionHost(_ host: String) -> Bool {
        TokyoMotionResolver.isSupportedHost(host)
    }

    private static func isThisVidHost(_ host: String) -> Bool {
        host == "thisvid.com" ||
            host == "www.thisvid.com" ||
            host.hasSuffix(".thisvid.com") ||
            host == "thisvid.test" ||
            host == "www.thisvid.test"
    }

    private static func isIxiguaHost(_ host: String) -> Bool {
        host == "ixigua.com" ||
            host == "www.ixigua.com" ||
            host == "m.ixigua.com" ||
            host.hasSuffix(".ixigua.com") ||
            host == "ixigua.test" ||
            host == "www.ixigua.test" ||
            host == "m.ixigua.test"
    }

    private static func isYourPornHost(_ host: String) -> Bool {
        host == "yourporn.sexy" ||
            host == "www.yourporn.sexy" ||
            host.hasSuffix(".yourporn.sexy") ||
            host == "yourporn.test" ||
            host == "www.yourporn.test"
    }

    private static func isXHamsterHost(_ host: String) -> Bool {
        if host == "xhamster.test" || host == "www.xhamster.test" {
            return true
        }
        guard let labels = hostLabels(host), labels.count >= 2 else {
            return false
        }
        let base = labels[labels.count - 2]
        let topLevelDomain = labels[labels.count - 1]
        guard topLevelDomain.range(
            of: #"^[a-z0-9]{2,24}$"#,
            options: .regularExpression
        ) != nil else {
            return false
        }
        return base.range(
            of: #"^(xhamster|xhwebsite|xhofficial|xhlocal|xhopen|xhtotal|megaxh|xhwide|xhtab|xhtime|xhamsterlive)[0-9]*$"#,
            options: .regularExpression
        ) != nil
    }

    private static func isYouPornHost(_ host: String) -> Bool {
        host == "youporn.com" ||
            host == "www.youporn.com" ||
            host == "youporn.test" ||
            host == "www.youporn.test"
    }

    private static func isYoukuHost(_ host: String) -> Bool {
        host == "youku.com" ||
            host == "www.youku.com" ||
            host == "v.youku.com" ||
            host == "youku.test" ||
            host == "www.youku.test" ||
            host == "v.youku.test"
    }

    private static func hostLabels(_ host: String) -> [String]? {
        let labels = host
            .lowercased()
            .split(separator: ".")
            .map(String.init)
            .filter { !$0.isEmpty }
        return labels.count >= 2 ? labels : nil
    }

    private static func cleanedURL(
        _ url: URL,
        path: String? = nil
    ) -> URL? {
        guard var components = URLComponents(
            url: url,
            resolvingAgainstBaseURL: false
        ) else {
            return nil
        }
        if let path {
            components.path = path
        }
        components.queryItems = nil
        components.fragment = nil
        return components.url
    }

    private static func isIxiguaVideoID(_ value: String) -> Bool {
        value.range(
            of: #"^[0-9]{6,}$"#,
            options: .regularExpression
        ) != nil
    }

    private static func isValidPathSlug(_ value: String) -> Bool {
        !value.isEmpty &&
            value.range(
                of: #"^[A-Za-z0-9][A-Za-z0-9_-]*$"#,
                options: .regularExpression
            ) != nil
    }

    private static func firstAttributeValue(
        in attributes: [String: String],
        keys: [String],
        matching predicate: (String) -> Bool
    ) -> String? {
        for key in keys {
            if let value = attributes[key]?.trimmed, predicate(value) {
                return value
            }
        }
        return nil
    }

    private static func typeHint(
        in attributes: [String: String],
        containsAnyOf needles: [String]
    ) -> Bool {
        let keys = [
            "data-type", "data-kind", "data-content-type",
            "data-renderer", "class", "role"
        ]
        let values = keys.compactMap {
            attributes[$0]?.lowercased()
        }
        return values.contains { value in
            needles.contains { value.contains($0) }
        }
    }
}

import Foundation

struct KakaoTVSearchResultResolver: SearchResultResolving {
    func supports(_ baseURL: URL) -> Bool {
        guard let host = baseURL.host?.lowercased() else { return false }
        return Self.isSupportedHost(host)
    }

    static func isSupportedHost(_ host: String) -> Bool {
        host == "tv.kakao.com" ||
            host.hasSuffix(".tv.kakao.com") ||
            host == "kakao.tv" ||
            host.hasSuffix(".kakao.tv") ||
            host == "kakaotv.daum.net" ||
            host.hasSuffix(".kakaotv.daum.net") ||
            host == "tv.kakao.test" ||
            host.hasSuffix(".tv.kakao.test") ||
            host == "kakao.test" ||
            host.hasSuffix(".kakao.test") ||
            host == "kakaotv.daum.test" ||
            host.hasSuffix(".kakaotv.daum.test")
    }

    static func dataAttributeLinkValue(
        in attributes: [String: String],
        baseURL: URL?
    ) -> String? {
        guard let host = baseURL?.host?.lowercased(),
              isSupportedHost(host),
              let id = dataAttributeClipID(in: attributes),
              dataAttributeLooksLikeClipCard(attributes) else {
            return nil
        }
        if let channelID = firstValidPathSlug(
            in: attributes,
            keys: [
                "data-channel-id", "data-channelid", "channel-id"
            ]
        ) {
            return "/channel/\(channelID)/cliplink/\(id)"
        }
        return "/v/\(id)"
    }

    static func mediaURL(from url: URL) -> URL? {
        guard var components = URLComponents(
            url: url,
            resolvingAgainstBaseURL: false
        ) else {
            return nil
        }
        if components.path == "/m" {
            components.path = "/"
        } else if components.path.hasPrefix("/m/") {
            components.path = String(components.path.dropFirst(2))
        }
        guard let normalizedURL = components.url,
              let clean = cleanedURL(normalizedURL) else {
            return nil
        }
        let parts = clean.path
            .split(separator: "/", omittingEmptySubsequences: true)
            .map(String.init)
        let lower = parts.map { $0.lowercased() }
        if let marker = lower.firstIndex(of: "cliplink"),
           marker + 1 < parts.count {
            return clean
        }
        if lower.first == "v", parts.count >= 2 {
            return clean
        }
        return nil
    }

    func extract(from context: SearchResultResolverContext) -> [SearchResultLink] {
        var results: [SearchResultLink] = []
        var indexByID: [String: Int] = [:]

        for anchor in context.anchors {
            guard results.count < context.limit,
                  let absolute = context.resolvedURL(for: anchor),
                  let target = Self.mediaURL(from: absolute),
                  let id = KakaoTVResolver.clipID(from: target) else {
                continue
            }

            let title = context.title(
                for: anchor,
                fallback: "KakaoTV \(id)"
            )
            SearchResultResolverSupport.appendUniqueResult(
                title: title,
                url: target,
                id: id,
                sitePrefix: "kakaotv",
                results: &results,
                indexByID: &indexByID,
                metadata: metadata(
                    id: id,
                    title: title,
                    contributorMetadata: context.contributorMetadata(
                        for: anchor
                    )
                )
            )
        }

        return results
    }

    private func metadata(
        id: String,
        title: String,
        contributorMetadata: [String: String]
    ) -> [String: String] {
        var metadata = [
            "id": id,
            "clip_id": id,
            "video_id": id,
            "media_id": id,
            "category": "kakaotv",
            "type": "video",
            "media_type": "video",
            "title": title,
            "search_title": title
        ]
        metadata.merge(contributorMetadata) { current, _ in current }
        return DownloadMetadata.clean(metadata)
    }

    private static func dataAttributeClipID(
        in attributes: [String: String]
    ) -> String? {
        let keys = [
            "data-clip-id", "data-clipid", "data-cliplink-id",
            "data-cliplinkid", "data-video-id", "data-videoid",
            "clip-id", "video-id"
        ]
        for key in keys {
            if let value = attributes[key]?.trimmed,
               isValidID(value) {
                return value
            }
        }
        if let id = attributes["data-id"]?.trimmed,
           isValidID(id),
           typeHint(
               in: attributes,
               containsAnyOf: ["kakao", "clip", "video"]
           ) {
            return id
        }
        return nil
    }

    private static func dataAttributeLooksLikeClipCard(
        _ attributes: [String: String]
    ) -> Bool {
        let markerKeys = [
            "data-clip-id", "data-clipid", "data-cliplink-id",
            "data-cliplinkid", "data-video-id", "data-videoid",
            "clip-id", "video-id"
        ]
        if markerKeys.contains(where: {
            attributes[$0]?.trimmed.isEmpty == false
        }) {
            return true
        }
        return typeHint(
            in: attributes,
            containsAnyOf: ["kakao", "clip", "video"]
        )
    }

    private static func firstValidPathSlug(
        in attributes: [String: String],
        keys: [String]
    ) -> String? {
        for key in keys {
            if let value = attributes[key]?.trimmed,
               isValidPathSlug(value) {
                return value
            }
        }
        return nil
    }

    private static func isValidID(_ value: String) -> Bool {
        value.range(
            of: #"^[0-9A-Za-z_-]+$"#,
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

    private static func typeHint(
        in attributes: [String: String],
        containsAnyOf needles: [String]
    ) -> Bool {
        let keys = [
            "data-type", "data-kind", "data-content-type",
            "data-renderer", "class", "role"
        ]
        let values = keys.compactMap { attributes[$0]?.lowercased() }
        return values.contains { value in
            needles.contains { value.contains($0) }
        }
    }

    private static func cleanedURL(_ url: URL) -> URL? {
        guard var components = URLComponents(
            url: url,
            resolvingAgainstBaseURL: false
        ) else {
            return nil
        }
        components.queryItems = nil
        components.fragment = nil
        return components.url
    }
}

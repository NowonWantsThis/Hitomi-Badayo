import Foundation

struct ChzzkSearchResultResolver: SearchResultResolving {
    func supports(_ baseURL: URL) -> Bool {
        guard let host = baseURL.host?.lowercased() else { return false }
        return Self.isSupportedHost(host)
    }

    static func isSupportedHost(_ host: String) -> Bool {
        host == "chzzk.naver.com" ||
            host == "m.chzzk.naver.com" ||
            host == "chzzk.naver.test" ||
            host == "m.chzzk.naver.test"
    }

    static func dataAttributeLinkValue(
        in attributes: [String: String],
        baseURL: URL?
    ) -> String? {
        guard let host = baseURL?.host?.lowercased(),
              isSupportedHost(host) else {
            return nil
        }
        if let id = dataAttributeClipID(in: attributes),
           dataAttributeLooksLikeClipCard(attributes) {
            return "/clips/\(id)"
        }
        if let id = dataAttributeVODID(in: attributes),
           dataAttributeLooksLikeVODCard(attributes) {
            return "/video/\(id)"
        }
        if let id = dataAttributeLiveID(in: attributes),
           dataAttributeLooksLikeLiveCard(attributes) {
            return "/live/\(id)"
        }
        return nil
    }

    func extract(from context: SearchResultResolverContext) -> [SearchResultLink] {
        var results: [SearchResultLink] = []
        var indexByID: [String: Int] = [:]

        for anchor in context.anchors {
            guard results.count < context.limit,
                  let absolute = context.resolvedURL(for: anchor),
                  let target = ChzzkResolver.canonicalURL(for: absolute) ??
                    ChzzkResolver.canonicalLiveURL(for: absolute) else {
                continue
            }

            let id: String
            if let clipID = ChzzkResolver.clipID(from: absolute) {
                id = "clip-\(clipID)"
            } else if let vodID = ChzzkResolver.vodID(from: absolute) {
                id = "video-\(vodID)"
            } else if let liveID = ChzzkResolver.liveID(from: absolute) {
                id = "live-\(liveID)"
            } else {
                continue
            }

            let title = context.title(
                for: anchor,
                fallback: "Chzzk \(id)"
            )
            SearchResultResolverSupport.appendUniqueResult(
                title: title,
                url: target,
                id: id,
                sitePrefix: "chzzk",
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
            "category": "chzzk",
            "title": title,
            "search_title": title
        ]
        if id.hasPrefix("clip-") {
            let value = String(id.dropFirst("clip-".count))
            metadata["clip_id"] = value
            metadata["media_id"] = value
            metadata["type"] = "clip"
            metadata["media_type"] = "video"
        } else if id.hasPrefix("video-") {
            let value = String(id.dropFirst("video-".count))
            metadata["video_id"] = value
            metadata["media_id"] = value
            metadata["type"] = "video"
            metadata["media_type"] = "video"
        } else if id.hasPrefix("live-") {
            let value = String(id.dropFirst("live-".count))
            metadata["live_id"] = value
            metadata["media_id"] = value
            metadata["type"] = "live"
            metadata["media_type"] = "live"
        }
        metadata.merge(contributorMetadata) { current, _ in current }
        return DownloadMetadata.clean(metadata)
    }

    private static func dataAttributeClipID(
        in attributes: [String: String]
    ) -> String? {
        let keys = [
            "data-clip-id", "data-clipid", "data-clip-uid",
            "data-clipuid", "clip-id"
        ]
        if let value = firstAttributeValue(
            in: attributes,
            keys: keys,
            matching: isValidClipID
        ) {
            return value
        }
        if let id = attributes["data-id"]?.trimmed,
           isValidClipID(id),
           typeHint(in: attributes, containsAnyOf: ["clip"]) {
            return id
        }
        return nil
    }

    private static func dataAttributeVODID(
        in attributes: [String: String]
    ) -> String? {
        let keys = [
            "data-vod-id", "data-vodid", "data-video-id",
            "data-videoid", "vod-id", "video-id"
        ]
        if let value = firstAttributeValue(
            in: attributes,
            keys: keys,
            matching: isValidVideoID
        ) {
            return value
        }
        if let id = attributes["data-id"]?.trimmed,
           isValidVideoID(id),
           typeHint(in: attributes, containsAnyOf: ["video", "vod"]) {
            return id
        }
        return nil
    }

    private static func dataAttributeLiveID(
        in attributes: [String: String]
    ) -> String? {
        let keys = ["data-live-id", "data-liveid", "live-id"]
        if let value = firstAttributeValue(
            in: attributes,
            keys: keys,
            matching: isValidLiveID
        ) {
            return value
        }
        if let channelID = firstAttributeValue(
            in: attributes,
            keys: [
                "data-channel-id", "data-channelid", "channel-id"
            ],
            matching: isValidLiveID
        ),
           typeHint(in: attributes, containsAnyOf: ["live"]) {
            return channelID
        }
        if let id = attributes["data-id"]?.trimmed,
           isValidLiveID(id),
           typeHint(in: attributes, containsAnyOf: ["live"]) {
            return id
        }
        return nil
    }

    private static func dataAttributeLooksLikeClipCard(
        _ attributes: [String: String]
    ) -> Bool {
        let keys = [
            "data-clip-id", "data-clipid", "data-clip-uid",
            "data-clipuid", "clip-id"
        ]
        if keys.contains(where: {
            attributes[$0]?.trimmed.isEmpty == false
        }) {
            return true
        }
        return typeHint(in: attributes, containsAnyOf: ["clip"])
    }

    private static func dataAttributeLooksLikeVODCard(
        _ attributes: [String: String]
    ) -> Bool {
        let keys = [
            "data-vod-id", "data-vodid", "data-video-id",
            "data-videoid", "vod-id", "video-id"
        ]
        if keys.contains(where: {
            attributes[$0]?.trimmed.isEmpty == false
        }) {
            return true
        }
        return typeHint(in: attributes, containsAnyOf: ["video", "vod"])
    }

    private static func dataAttributeLooksLikeLiveCard(
        _ attributes: [String: String]
    ) -> Bool {
        let keys = ["data-live-id", "data-liveid", "live-id"]
        if keys.contains(where: {
            attributes[$0]?.trimmed.isEmpty == false
        }) {
            return true
        }
        return typeHint(in: attributes, containsAnyOf: ["live"])
    }

    private static func firstAttributeValue(
        in attributes: [String: String],
        keys: [String],
        matching predicate: (String) -> Bool
    ) -> String? {
        for key in keys {
            if let value = attributes[key]?.trimmed,
               predicate(value) {
                return value
            }
        }
        return nil
    }

    private static func isValidClipID(_ value: String) -> Bool {
        value.range(
            of: #"^[A-Za-z0-9_-]{4,}$"#,
            options: .regularExpression
        ) != nil
    }

    private static func isValidVideoID(_ value: String) -> Bool {
        value.range(
            of: #"^[A-Za-z0-9_-]{2,}$"#,
            options: .regularExpression
        ) != nil
    }

    private static func isValidLiveID(_ value: String) -> Bool {
        guard isValidVideoID(value) else { return false }
        let reserved = [
            "clip", "clips", "video", "videos", "vod", "live",
            "search", "category", "following", "lounge", "settings",
            "notice"
        ]
        return !reserved.contains(value.lowercased())
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
}

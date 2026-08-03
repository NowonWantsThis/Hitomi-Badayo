import Foundation

struct SOOPSearchResultResolver: SearchResultResolving {
    func supports(_ baseURL: URL) -> Bool {
        guard let host = baseURL.host?.lowercased() else { return false }
        return Self.isSupportedHost(host)
    }

    static func isSupportedHost(_ host: String) -> Bool {
        host == "afreecatv.com" ||
            host.hasSuffix(".afreecatv.com") ||
            host == "sooplive.com" ||
            host.hasSuffix(".sooplive.com") ||
            host == "sooplive.co.kr" ||
            host.hasSuffix(".sooplive.co.kr") ||
            host == "afreecatv.test" ||
            host.hasSuffix(".afreecatv.test") ||
            host == "sooplive.test" ||
            host.hasSuffix(".sooplive.test")
    }

    static func dataAttributeLinkValue(
        in attributes: [String: String],
        baseURL: URL?
    ) -> String? {
        guard let host = baseURL?.host?.lowercased(),
              isSupportedHost(host) else {
            return nil
        }
        if let id = dataAttributeLiveID(in: attributes),
           dataAttributeLooksLikeLiveCard(attributes) {
            return liveDataAttributeURL(id: id, baseHost: host)
        }
        if let id = dataAttributeCatchID(in: attributes),
           dataAttributeLooksLikeCatchCard(attributes) {
            return "/catch/\(id)"
        }
        if let id = dataAttributeVideoID(in: attributes),
           dataAttributeLooksLikeVideoCard(attributes) {
            return "/player/\(id)"
        }
        return nil
    }

    func extract(from context: SearchResultResolverContext) -> [SearchResultLink] {
        var results: [SearchResultLink] = []
        var indexByID: [String: Int] = [:]

        for anchor in context.anchors {
            guard results.count < context.limit,
                  let absolute = context.resolvedURL(for: anchor) else {
                continue
            }

            let id: String
            let target: URL
            if let videoID = SOOPVODResolver.videoID(from: absolute),
               let videoURL = SOOPVODResolver.canonicalURL(for: absolute) {
                id = videoID
                target = videoURL
            } else if let liveID = SOOPVODResolver.liveID(from: absolute) {
                id = "live-\(liveID)"
                target = SOOPVODResolver.canonicalLiveURL(
                    liveID: liveID,
                    sourceURL: absolute
                )
            } else {
                continue
            }

            let title = context.title(for: anchor, fallback: "SOOP \(id)")
            SearchResultResolverSupport.appendUniqueResult(
                title: title,
                url: target,
                id: id,
                sitePrefix: "soop",
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
            "category": "soop",
            "title": title,
            "search_title": title
        ]
        if id.hasPrefix("live-") {
            let value = String(id.dropFirst("live-".count))
            metadata["live_id"] = value
            metadata["media_id"] = value
            metadata["type"] = "live"
            metadata["media_type"] = "live"
        } else {
            metadata["video_id"] = id
            metadata["media_id"] = id
            metadata["type"] = "video"
            metadata["media_type"] = "video"
        }
        metadata.merge(contributorMetadata) { current, _ in current }
        return DownloadMetadata.clean(metadata)
    }

    private static func dataAttributeVideoID(
        in attributes: [String: String]
    ) -> String? {
        let keys = [
            "data-vod-id", "data-vodid", "data-video-id",
            "data-videoid", "data-title-no", "data-titleno",
            "data-broad-no", "data-broadno", "vod-id", "video-id"
        ]
        if let value = firstAttributeValue(
            in: attributes,
            keys: keys,
            matching: isNumericID
        ) {
            return value
        }
        if let id = attributes["data-id"]?.trimmed,
           isNumericID(id),
           typeHint(
               in: attributes,
               containsAnyOf: ["video", "vod", "player"]
           ) {
            return id
        }
        return nil
    }

    private static func dataAttributeCatchID(
        in attributes: [String: String]
    ) -> String? {
        let keys = ["data-catch-id", "data-catchid", "catch-id"]
        if let value = firstAttributeValue(
            in: attributes,
            keys: keys,
            matching: isNumericID
        ) {
            return value
        }
        if let id = attributes["data-id"]?.trimmed,
           isNumericID(id),
           typeHint(in: attributes, containsAnyOf: ["catch"]) {
            return id
        }
        return nil
    }

    private static func dataAttributeLiveID(
        in attributes: [String: String]
    ) -> String? {
        let keys = [
            "data-live-id", "data-liveid", "data-bj-id",
            "data-bjid", "live-id"
        ]
        if let value = firstAttributeValue(
            in: attributes,
            keys: keys,
            matching: isLiveID
        ) {
            return value
        }
        if let id = attributes["data-id"]?.trimmed,
           isLiveID(id),
           typeHint(in: attributes, containsAnyOf: ["live"]) {
            return id
        }
        return nil
    }

    private static func dataAttributeLooksLikeVideoCard(
        _ attributes: [String: String]
    ) -> Bool {
        let keys = [
            "data-vod-id", "data-vodid", "data-video-id",
            "data-videoid", "data-title-no", "data-titleno",
            "data-broad-no", "data-broadno", "vod-id", "video-id"
        ]
        if keys.contains(where: {
            attributes[$0]?.trimmed.isEmpty == false
        }) {
            return true
        }
        return typeHint(
            in: attributes,
            containsAnyOf: ["video", "vod", "player"]
        )
    }

    private static func dataAttributeLooksLikeCatchCard(
        _ attributes: [String: String]
    ) -> Bool {
        let keys = ["data-catch-id", "data-catchid", "catch-id"]
        if keys.contains(where: {
            attributes[$0]?.trimmed.isEmpty == false
        }) {
            return true
        }
        return typeHint(in: attributes, containsAnyOf: ["catch"])
    }

    private static func dataAttributeLooksLikeLiveCard(
        _ attributes: [String: String]
    ) -> Bool {
        let keys = [
            "data-live-id", "data-liveid", "data-bj-id",
            "data-bjid", "live-id"
        ]
        if keys.contains(where: {
            attributes[$0]?.trimmed.isEmpty == false
        }) {
            return true
        }
        return typeHint(in: attributes, containsAnyOf: ["live"])
    }

    private static func liveDataAttributeURL(
        id: String,
        baseHost: String
    ) -> String {
        let host = baseHost.hasSuffix(".test")
            ? "play.sooplive.test"
            : "play.sooplive.com"
        return "https://\(host)/\(id)"
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

    private static func isNumericID(_ value: String) -> Bool {
        value.range(
            of: #"^[0-9]{4,}$"#,
            options: .regularExpression
        ) != nil
    }

    private static func isLiveID(_ value: String) -> Bool {
        value.range(
            of: #"^[A-Za-z0-9_]{2,32}$"#,
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
}

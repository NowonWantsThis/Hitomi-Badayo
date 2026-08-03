import Foundation

struct BilibiliSearchResultResolver: SearchResultResolving {
    func supports(_ baseURL: URL) -> Bool {
        guard let host = baseURL.host?.lowercased() else { return false }
        return Self.isSupportedHost(host)
    }

    static func isSupportedHost(_ host: String) -> Bool {
        host == "bilibili.com" ||
            host == "www.bilibili.com" ||
            host == "m.bilibili.com" ||
            host == "bangumi.bilibili.com" ||
            host == "bilibili.test" ||
            host == "www.bilibili.test" ||
            host.hasSuffix(".bilibili.com") ||
            host.hasSuffix(".bilibili.test")
    }

    static func dataAttributeLinkValue(
        in attributes: [String: String],
        baseURL: URL?
    ) -> String? {
        guard let host = baseURL?.host?.lowercased(),
              isSupportedHost(host),
              let id = dataAttributeVideoID(in: attributes),
              dataAttributeLooksLikeVideoCard(attributes) else {
            return nil
        }
        return "/video/\(id)"
    }

    func extract(from context: SearchResultResolverContext) -> [SearchResultLink] {
        var results: [SearchResultLink] = []
        var indexByID: [String: Int] = [:]

        for anchor in context.anchors {
            guard results.count < context.limit,
                  let absolute = context.resolvedURL(for: anchor),
                  let id = BilibiliResolver.videoID(from: absolute),
                  let target = BilibiliResolver.canonicalURL(
                      for: absolute
                  ) else {
                continue
            }

            let title = context.title(
                for: anchor,
                fallback: "Bilibili \(id)"
            )
            SearchResultResolverSupport.appendUniqueResult(
                title: title,
                url: target,
                id: id,
                sitePrefix: "bilibili",
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
            "video_id": id,
            "media_id": id,
            "category": "bilibili",
            "type": "video",
            "media_type": "video",
            "title": title,
            "search_title": title
        ]
        if id.uppercased().hasPrefix("BV") {
            metadata["bvid"] = id
        } else if id.range(
            of: #"^[0-9]+$"#,
            options: .regularExpression
        ) != nil {
            metadata["aid"] = id
        }
        metadata.merge(contributorMetadata) { current, _ in current }
        return DownloadMetadata.clean(metadata)
    }

    private static func dataAttributeVideoID(
        in attributes: [String: String]
    ) -> String? {
        let bvidKeys = [
            "data-bvid", "data-bv-id", "data-bvid-id", "bvid"
        ]
        for key in bvidKeys {
            if let value = attributes[key]?.trimmed,
               let id = normalizedDataVideoID(value) {
                return id
            }
        }
        let aidKeys = [
            "data-aid", "data-av-id", "data-avid", "aid", "av-id"
        ]
        for key in aidKeys {
            if let value = attributes[key]?.trimmed,
               let id = normalizedDataVideoID(value) {
                return id
            }
        }
        let videoKeys = [
            "data-video-id", "data-videoid", "video-id"
        ]
        for key in videoKeys {
            if let value = attributes[key]?.trimmed,
               let id = normalizedDataVideoID(value) {
                return id
            }
        }
        if let id = attributes["data-id"]?.trimmed,
           let normalized = normalizedDataVideoID(id),
           typeHint(
               in: attributes,
               containsAnyOf: ["bilibili", "bili", "video"]
           ) {
            return normalized
        }
        return nil
    }

    private static func normalizedDataVideoID(_ value: String) -> String? {
        let clean = value.trimmed
        if clean.range(
            of: #"^BV[0-9A-Za-z]+$"#,
            options: [.caseInsensitive, .regularExpression]
        ) != nil {
            return clean
        }
        if clean.range(
            of: #"^av[0-9]+$"#,
            options: [.caseInsensitive, .regularExpression]
        ) != nil {
            return clean
        }
        if clean.range(
            of: #"^[0-9]{4,}$"#,
            options: .regularExpression
        ) != nil {
            return "av\(clean)"
        }
        if clean.range(
            of: #"^[0-9A-Za-z_-]{6,}$"#,
            options: .regularExpression
        ) != nil {
            return clean
        }
        return nil
    }

    private static func dataAttributeLooksLikeVideoCard(
        _ attributes: [String: String]
    ) -> Bool {
        let keys = [
            "data-bvid", "data-bv-id", "data-bvid-id", "bvid",
            "data-aid", "data-av-id", "data-avid", "aid", "av-id",
            "data-video-id", "data-videoid", "video-id"
        ]
        if keys.contains(where: {
            attributes[$0]?.trimmed.isEmpty == false
        }) {
            return true
        }
        return typeHint(
            in: attributes,
            containsAnyOf: ["bilibili", "bili", "video"]
        )
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

import Foundation

struct NaverTVSearchResultResolver: SearchResultResolving {
    func supports(_ baseURL: URL) -> Bool {
        guard let host = baseURL.host?.lowercased() else { return false }
        return Self.isSupportedHost(host)
    }

    static func isSupportedHost(_ host: String) -> Bool {
        host == "tv.naver.com" ||
            host == "m.tv.naver.com" ||
            host == "tv.naver.test" ||
            host == "m.tv.naver.test"
    }

    static func dataAttributeLinkValue(
        in attributes: [String: String],
        baseURL: URL
    ) -> String? {
        guard let host = baseURL.host?.lowercased(),
              isSupportedHost(host),
              let clipID = dataAttributeClipID(in: attributes),
              dataAttributeLooksLikeClipCard(attributes) else {
            return nil
        }
        return "/v/\(clipID)"
    }

    func extract(from context: SearchResultResolverContext) -> [SearchResultLink] {
        var results: [SearchResultLink] = []
        var indexByClip: [String: Int] = [:]

        for anchor in context.anchors {
            guard results.count < context.limit,
                  let absolute = context.resolvedURL(for: anchor),
                  let clipID = NaverTVResolver.clipID(from: absolute),
                  let target = NaverTVResolver.canonicalURL(
                      for: absolute
                  ) else {
                continue
            }

            let title = context.title(
                for: anchor,
                fallback: "Naver TV \(clipID)"
            )
            SearchResultResolverSupport.appendUniqueResult(
                title: title,
                url: target,
                id: clipID,
                sitePrefix: "navertv",
                results: &results,
                indexByID: &indexByClip,
                metadata: metadata(
                    clipID: clipID,
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
        clipID: String,
        title: String,
        contributorMetadata: [String: String]
    ) -> [String: String] {
        var metadata = contributorMetadata
        metadata.merge([
            "id": clipID,
            "post_id": clipID,
            "clip_id": clipID,
            "video_id": clipID,
            "media_id": clipID,
            "gallery_id": clipID,
            "category": "video",
            "type": "video",
            "media_type": "video",
            "title": title,
            "search_title": title
        ]) { current, _ in current }
        return DownloadMetadata.clean(metadata)
    }

    private static func dataAttributeClipID(
        in attributes: [String: String]
    ) -> String? {
        let clipKeys = [
            "data-clip-id", "data-clipid", "data-clip-no", "data-clipno",
            "data-video-id", "data-videoid", "clip-id", "clipno", "video-id"
        ]
        if let clipID = firstAttributeValue(
            in: attributes,
            keys: clipKeys,
            matching: isPositiveNumericID
        ) {
            return clipID
        }
        guard typeHint(
            in: attributes,
            containsAnyOf: ["clip", "video", "navertv"]
        ) else {
            return nil
        }
        return firstAttributeValue(
            in: attributes,
            keys: ["data-id", "id"],
            matching: isPositiveNumericID
        )
    }

    private static func dataAttributeLooksLikeClipCard(
        _ attributes: [String: String]
    ) -> Bool {
        let markerKeys = [
            "data-clip-id", "data-clipid", "data-clip-no", "data-clipno",
            "data-video-id", "data-videoid"
        ]
        if markerKeys.contains(where: {
            attributes[$0]?.trimmed.isEmpty == false
        }) {
            return true
        }
        return typeHint(
            in: attributes,
            containsAnyOf: ["clip", "video", "navertv"]
        )
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
        let values = keys.compactMap { attributes[$0]?.lowercased() }
        return values.contains { value in
            needles.contains { value.contains($0) }
        }
    }

    private static func isPositiveNumericID(_ value: String) -> Bool {
        guard value.range(
            of: #"^[0-9]+$"#,
            options: .regularExpression
        ) != nil, let number = Int(value) else {
            return false
        }
        return number > 0
    }
}

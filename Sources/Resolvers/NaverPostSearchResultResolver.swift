import Foundation

struct NaverPostSearchResultResolver: SearchResultResolving {
    func supports(_ baseURL: URL) -> Bool {
        guard let host = baseURL.host?.lowercased() else { return false }
        return Self.isSupportedHost(host)
    }

    static func isSupportedHost(_ host: String) -> Bool {
        host == "post.naver.com" ||
            host == "m.post.naver.com" ||
            host == "post.naver.test" ||
            host == "m.post.naver.test"
    }

    static func dataAttributeLinkValue(
        in attributes: [String: String],
        baseURL: URL
    ) -> String? {
        guard let host = baseURL.host?.lowercased(),
              isSupportedHost(host) else {
            return nil
        }

        if let post = dataAttributePost(in: attributes),
           dataAttributeLooksLikePostCard(attributes) {
            var items = [URLQueryItem(
                name: "volumeNo",
                value: post.volumeNo
            )]
            if let memberNo = post.memberNo {
                items.append(URLQueryItem(
                    name: "memberNo",
                    value: memberNo
                ))
            }
            return relativeURL(
                path: "/viewer/postView.naver",
                queryItems: items
            )
        }

        if let collection = dataAttributeCollection(in: attributes),
           dataAttributeLooksLikeCollectionCard(attributes) {
            var items = [URLQueryItem(
                name: "memberNo",
                value: collection.memberNo
            )]
            if let seriesNo = collection.seriesNo {
                items.append(URLQueryItem(
                    name: "seriesNo",
                    value: seriesNo
                ))
                return relativeURL(
                    path: "/my/series/detail.nhn",
                    queryItems: items
                )
            }
            return relativeURL(
                path: "/my.nhn",
                queryItems: items
            )
        }

        return nil
    }

    func extract(from context: SearchResultResolverContext) -> [SearchResultLink] {
        var results: [SearchResultLink] = []
        var indexByKey: [String: Int] = [:]

        for anchor in context.anchors {
            guard results.count < context.limit,
                  let absolute = context.resolvedURL(for: anchor),
                  let target = canonicalURL(from: absolute) else {
                continue
            }

            let title = context.title(for: anchor, fallbackURL: target)
            SearchResultResolverSupport.appendUniqueResult(
                title: title,
                url: target,
                id: resultKey(for: target),
                sitePrefix: "naverpost",
                results: &results,
                indexByID: &indexByKey,
                metadata: metadata(
                    target: target,
                    title: title,
                    contributorMetadata: context.contributorMetadata(
                        for: anchor,
                        fallbackName: nil,
                        fallbackUsername: nil,
                        fallbackUserID: queryValue(
                            "memberNo",
                            in: target
                        )
                    )
                )
            )
        }

        return results
    }

    private func canonicalURL(from url: URL) -> URL? {
        guard let host = url.host?.lowercased(),
              Self.isSupportedHost(host),
              NaverPostResolver.isViewerURL(url) ||
                NaverPostResolver.isCollectionURL(url),
              var components = URLComponents(
                  url: url,
                  resolvingAgainstBaseURL: false
              ) else {
            return nil
        }
        components.host = host.hasSuffix(".test")
            ? "post.naver.test"
            : "post.naver.com"
        components.fragment = nil
        return components.url
    }

    private func resultKey(for url: URL) -> String {
        let items = URLComponents(
            url: url,
            resolvingAgainstBaseURL: false
        )?.queryItems ?? []
        let volume = queryValue("volumeNo", in: items)
        let member = queryValue("memberNo", in: items)
        let series = queryValue("seriesNo", in: items)
        if let volume {
            return "volume:\(volume)"
        }
        if let member, let series {
            return "series:\(member):\(series)"
        }
        if let member {
            return "member:\(member)"
        }
        return url.absoluteString.lowercased()
    }

    private func metadata(
        target: URL,
        title: String,
        contributorMetadata: [String: String]
    ) -> [String: String] {
        let items = URLComponents(
            url: target,
            resolvingAgainstBaseURL: false
        )?.queryItems ?? []
        let volume = queryValue("volumeNo", in: items)
        let member = queryValue("memberNo", in: items)
        let series = queryValue("seriesNo", in: items)
        var metadata = contributorMetadata
        metadata.merge([
            "category": "naver_post",
            "type": volume == nil ? "collection" : "post",
            "title": title,
            "search_title": title
        ]) { current, _ in current }
        if let volume, !volume.isEmpty {
            metadata["id"] = volume
            metadata["post_id"] = volume
            metadata["volume_no"] = volume
            metadata["media_id"] = volume
            metadata["gallery_id"] = volume
        }
        if let member, !member.isEmpty {
            metadata["member_no"] = member
            metadata["uploader_id"] = member
            metadata["user_id"] = member
            metadata["channel_id"] = member
        }
        if let series, !series.isEmpty {
            metadata["series_id"] = series
            metadata["gallery_id"] = metadata["gallery_id"] ?? series
        }
        if metadata["id"] == nil {
            metadata["id"] = member ?? series ?? ""
        }
        return DownloadMetadata.clean(metadata)
    }

    private static func dataAttributePost(
        in attributes: [String: String]
    ) -> (volumeNo: String, memberNo: String?)? {
        let volumeKeys = [
            "data-volume-no", "data-volumeno", "data-post-id", "data-postid",
            "data-article-id", "data-articleid", "volume-no", "volumeno"
        ]
        let volumeNo = firstAttributeValue(
            in: attributes,
            keys: volumeKeys,
            matching: isPositiveNumericID
        ) ?? (typeHint(
            in: attributes,
            containsAnyOf: ["post", "viewer", "volume", "article"]
        ) ? firstAttributeValue(
            in: attributes,
            keys: ["data-id", "id"],
            matching: isPositiveNumericID
        ) : nil)
        guard let volumeNo else { return nil }
        return (volumeNo, dataAttributeMemberNo(in: attributes))
    }

    private static func dataAttributeCollection(
        in attributes: [String: String]
    ) -> (memberNo: String, seriesNo: String?)? {
        guard let memberNo = dataAttributeMemberNo(in: attributes) else {
            return nil
        }
        let seriesNo = firstAttributeValue(
            in: attributes,
            keys: [
                "data-series-no", "data-seriesno", "data-series-id",
                "data-seriesid", "series-no", "seriesno"
            ],
            matching: isPositiveNumericID
        )
        return (memberNo, seriesNo)
    }

    private static func dataAttributeMemberNo(
        in attributes: [String: String]
    ) -> String? {
        firstAttributeValue(
            in: attributes,
            keys: [
                "data-member-no", "data-memberno", "data-member-id",
                "data-memberid", "data-user-id", "data-userid",
                "data-channel-id", "data-channelid", "member-no", "memberno"
            ],
            matching: isPositiveNumericID
        )
    }

    private static func dataAttributeLooksLikePostCard(
        _ attributes: [String: String]
    ) -> Bool {
        let markerKeys = [
            "data-volume-no", "data-volumeno", "data-post-id", "data-postid"
        ]
        if markerKeys.contains(where: {
            attributes[$0]?.trimmed.isEmpty == false
        }) {
            return true
        }
        return typeHint(
            in: attributes,
            containsAnyOf: ["post", "viewer", "volume", "article"]
        )
    }

    private static func dataAttributeLooksLikeCollectionCard(
        _ attributes: [String: String]
    ) -> Bool {
        let markerKeys = [
            "data-series-no", "data-seriesno", "data-series-id", "data-seriesid"
        ]
        if markerKeys.contains(where: {
            attributes[$0]?.trimmed.isEmpty == false
        }) {
            return true
        }
        return typeHint(
            in: attributes,
            containsAnyOf: ["collection", "series", "profile", "author"]
        )
    }

    private static func relativeURL(
        path: String,
        queryItems: [URLQueryItem]
    ) -> String? {
        var components = URLComponents()
        components.path = path
        components.queryItems = queryItems
        return components.string
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

    private func queryValue(_ name: String, in url: URL) -> String? {
        let items = URLComponents(
            url: url,
            resolvingAgainstBaseURL: false
        )?.queryItems ?? []
        return queryValue(name, in: items)
    }

    private func queryValue(
        _ name: String,
        in items: [URLQueryItem]
    ) -> String? {
        items.first { $0.name == name }?.value
    }
}

import Foundation

struct NijieSearchResultResolver: SearchResultResolving {
    func supports(_ baseURL: URL) -> Bool {
        guard let host = baseURL.host?.lowercased() else { return false }
        return Self.isSupportedHost(host)
    }

    static func isSupportedHost(_ host: String) -> Bool {
        host == "nijie.info" ||
            host == "www.nijie.info" ||
            host == "nijie.test" ||
            host == "www.nijie.test"
    }

    static func dataAttributeLinkValue(
        in attributes: [String: String],
        baseURL: URL?
    ) -> String? {
        guard let baseURL,
              let host = baseURL.host?.lowercased(),
              isSupportedHost(host) else {
            return nil
        }

        if let illustrationID = dataAttributeIllustrationID(
            in: attributes
        ),
           dataAttributeLooksLikeIllustrationCard(attributes) {
            return NijieResolver.viewURL(
                illustrationID: illustrationID,
                sourceURL: baseURL
            ).absoluteString
        }

        if let memberID = dataAttributeMemberID(in: attributes),
           dataAttributeLooksLikeMemberCard(attributes) {
            return NijieResolver.memberIllustURL(
                memberID: memberID,
                page: 1,
                sourceURL: baseURL
            ).absoluteString
        }

        return nil
    }

    func extract(from context: SearchResultResolverContext) -> [SearchResultLink] {
        var results: [SearchResultLink] = []
        var indexByResultID: [String: Int] = [:]

        for anchor in context.anchors {
            guard results.count < context.limit,
                  let absolute = context.resolvedURL(for: anchor),
                  let host = absolute.host?.lowercased(),
                  Self.isSupportedHost(host) else {
                continue
            }

            if let illustrationID = NijieResolver.illustrationID(from: absolute) {
                let title = context.title(
                    for: anchor,
                    fallback: "Nijie \(illustrationID)"
                )
                SearchResultResolverSupport.appendUniqueResult(
                    title: title,
                    url: NijieResolver.viewURL(
                        illustrationID: illustrationID,
                        sourceURL: absolute
                    ),
                    id: "illust:\(illustrationID)",
                    sitePrefix: "nijie",
                    results: &results,
                    indexByID: &indexByResultID,
                    metadata: illustrationMetadata(
                        illustrationID: illustrationID,
                        title: title,
                        contributorMetadata: context.contributorMetadata(for: anchor)
                    )
                )
            } else if let memberID = NijieResolver.memberID(from: absolute) {
                let title = context.title(for: anchor, fallback: "Nijie \(memberID)")
                SearchResultResolverSupport.appendUniqueResult(
                    title: title,
                    url: NijieResolver.memberIllustURL(
                        memberID: memberID,
                        page: 1,
                        sourceURL: absolute
                    ),
                    id: "member:\(memberID)",
                    sitePrefix: "nijie",
                    results: &results,
                    indexByID: &indexByResultID,
                    metadata: memberMetadata(
                        memberID: memberID,
                        title: title,
                        contributorMetadata: context.contributorMetadata(
                            for: anchor,
                            fallbackName: nil,
                            fallbackUsername: memberID,
                            fallbackUserID: memberID
                        )
                    )
                )
            }
        }

        return results
    }

    private func illustrationMetadata(
        illustrationID: String,
        title: String,
        contributorMetadata: [String: String]
    ) -> [String: String] {
        var metadata = contributorMetadata
        metadata.merge([
            "id": illustrationID,
            "post_id": illustrationID,
            "illust_id": illustrationID,
            "illustration_id": illustrationID,
            "gallery_id": illustrationID,
            "media_id": illustrationID,
            "category": "nijie",
            "type": "illustration",
            "title": title,
            "search_title": title
        ]) { current, _ in current }
        return DownloadMetadata.clean(metadata)
    }

    private func memberMetadata(
        memberID: String,
        title: String,
        contributorMetadata: [String: String]
    ) -> [String: String] {
        var metadata = contributorMetadata
        metadata.merge([
            "id": memberID,
            "member_id": memberID,
            "user_id": memberID,
            "uploader_id": memberID,
            "gallery_id": memberID,
            "category": "nijie",
            "type": "member",
            "title": title,
            "search_title": title
        ]) { current, _ in current }
        return DownloadMetadata.clean(metadata)
    }

    private static func dataAttributeIllustrationID(
        in attributes: [String: String]
    ) -> String? {
        let keys = [
            "data-illust-id", "data-illustid", "data-illustration-id",
            "data-illustrationid", "data-post-id", "data-postid",
            "illust-id"
        ]
        if let value = firstAttributeValue(
            in: attributes,
            keys: keys,
            matching: isPositiveNumericID
        ) {
            return value
        }
        guard typeHint(
            in: attributes,
            containsAnyOf: ["illust", "illustration", "post", "work"]
        ) else {
            return nil
        }
        return firstAttributeValue(
            in: attributes,
            keys: ["data-id", "id"],
            matching: isPositiveNumericID
        )
    }

    private static func dataAttributeMemberID(
        in attributes: [String: String]
    ) -> String? {
        let keys = [
            "data-member-id", "data-memberid", "data-user-id",
            "data-userid", "member-id"
        ]
        if let value = firstAttributeValue(
            in: attributes,
            keys: keys,
            matching: isPositiveNumericID
        ) {
            return value
        }
        guard typeHint(
            in: attributes,
            containsAnyOf: ["member", "artist", "user", "profile"]
        ) else {
            return nil
        }
        return firstAttributeValue(
            in: attributes,
            keys: ["data-id", "id"],
            matching: isPositiveNumericID
        )
    }

    private static func dataAttributeLooksLikeIllustrationCard(
        _ attributes: [String: String]
    ) -> Bool {
        let keys = [
            "data-illust-id", "data-illustid", "data-illustration-id",
            "data-illustrationid", "data-post-id", "data-postid",
            "illust-id"
        ]
        if keys.contains(where: {
            attributes[$0]?.trimmed.isEmpty == false
        }) {
            return true
        }
        return typeHint(
            in: attributes,
            containsAnyOf: ["illust", "illustration", "post", "work"]
        )
    }

    private static func dataAttributeLooksLikeMemberCard(
        _ attributes: [String: String]
    ) -> Bool {
        let keys = [
            "data-member-id", "data-memberid", "data-user-id",
            "data-userid", "member-id"
        ]
        if keys.contains(where: {
            attributes[$0]?.trimmed.isEmpty == false
        }) {
            return true
        }
        return typeHint(
            in: attributes,
            containsAnyOf: ["member", "artist", "user", "profile"]
        )
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

    private static func isPositiveNumericID(_ value: String) -> Bool {
        value.range(
            of: #"^[0-9]+$"#,
            options: .regularExpression
        ) != nil
    }
}

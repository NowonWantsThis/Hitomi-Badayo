import Foundation

struct BCYSearchResultResolver: SearchResultResolving {
    func supports(_ baseURL: URL) -> Bool {
        guard let host = baseURL.host?.lowercased() else { return false }
        return Self.isSupportedHost(host)
    }

    static func isSupportedHost(_ host: String) -> Bool {
        host == "bcy.net" ||
            host == "www.bcy.net" ||
            host == "bcy.net.test" ||
            host == "www.bcy.net.test"
    }

    static func dataAttributeLinkValue(
        in attributes: [String: String],
        baseURL: URL?
    ) -> String? {
        guard let host = baseURL?.host?.lowercased(),
              isSupportedHost(host) else {
            return nil
        }
        if let itemID = dataAttributeItemID(in: attributes),
           dataAttributeLooksLikeItemCard(attributes) {
            return "/item/detail/\(itemID)"
        }
        if let userID = dataAttributeUserID(in: attributes),
           dataAttributeLooksLikeUserCard(attributes) {
            return "/u/\(userID)"
        }
        return nil
    }

    func extract(from context: SearchResultResolverContext) -> [SearchResultLink] {
        var results: [SearchResultLink] = []
        var indexByContent: [String: Int] = [:]

        for anchor in context.anchors {
            guard results.count < context.limit,
                  let absolute = context.resolvedURL(for: anchor) else {
                continue
            }

            if let itemURL = BCYResolver.canonicalItemURL(from: absolute),
               let itemID = BCYResolver.itemID(from: itemURL) {
                let title = context.title(
                    for: anchor,
                    fallback: "BCY \(itemID)"
                )
                SearchResultResolverSupport.appendUniqueResult(
                    title: title,
                    url: itemURL,
                    id: "item:\(itemID)",
                    sitePrefix: "bcy",
                    results: &results,
                    indexByID: &indexByContent,
                    metadata: metadata(
                        id: itemID,
                        kind: "item",
                        title: title,
                        anchor: anchor,
                        target: itemURL,
                        context: context
                    )
                )
                continue
            }

            if let userID = BCYResolver.userID(from: absolute),
               let target = Self.cleanedURL(
                   absolute,
                   path: "/u/\(userID)"
               ) {
                let title = context.title(
                    for: anchor,
                    fallback: userID
                )
                SearchResultResolverSupport.appendUniqueResult(
                    title: title,
                    url: target,
                    id: "user:\(userID)",
                    sitePrefix: "bcy",
                    results: &results,
                    indexByID: &indexByContent,
                    metadata: metadata(
                        id: userID,
                        kind: "user",
                        title: title,
                        anchor: anchor,
                        target: target,
                        context: context
                    )
                )
            }
        }

        return results
    }

    private func metadata(
        id: String,
        kind: String,
        title: String,
        anchor: AnchorEntry,
        target: URL,
        context: SearchResultResolverContext
    ) -> [String: String] {
        var metadata = [
            "id": id,
            "category": "bcy",
            "type": kind,
            "title": title,
            "search_title": title
        ]
        if kind == "item" {
            metadata["item_id"] = id
            metadata["media_id"] = id
            metadata["gallery_id"] = id
        } else {
            metadata["user_id"] = id
            metadata["gallery_id"] = id
        }

        let attributes = context.semanticAttributes(for: anchor)
        let profileInfo = userInfo(
            from: anchor.contextHTML,
            baseURL: target,
            context: context
        )
        let displayName = Self.firstSemanticAttribute(
            attributes,
            keys: [
                "data-artist-name", "data-artist", "artist",
                "data-author-name", "data-author", "author",
                "data-uploader-name", "data-uploader", "uploader",
                "data-user-name"
            ]
        ) ?? (kind == "user" ? title : profileInfo?.name)
        let userID = Self.firstSemanticAttribute(
            attributes,
            keys: ["data-user-id", "data-uid", "uid", "user-id"]
        ) ?? (kind == "user" ? id : profileInfo?.id)
        if let displayName {
            metadata["artist"] = displayName
            metadata["author"] = displayName
            metadata["creator"] = displayName
            metadata["uploader"] = displayName
            metadata["username"] = displayName
        }
        if let userID {
            metadata["user"] = userID
            metadata["user_id"] = userID
            metadata["uploader_id"] = userID
        }
        return DownloadMetadata.clean(metadata)
    }

    private func userInfo(
        from html: String,
        baseURL: URL,
        context: SearchResultResolverContext
    ) -> (id: String, name: String?)? {
        for entry in context.nestedAnchors(in: html) {
            guard let url = context.resolvedURL(
                for: entry,
                relativeTo: baseURL
            ),
                  let id = BCYResolver.userID(from: url) else {
                continue
            }
            let name = context.title(for: entry, fallback: "").trimmed
            return (id, name.isEmpty ? nil : name)
        }
        return nil
    }

    private static func dataAttributeItemID(
        in attributes: [String: String]
    ) -> String? {
        let keys = [
            "data-item-id", "data-itemid", "data-post-id",
            "data-work-id", "item-id"
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
               containsAnyOf: ["item", "post", "work"]
           ) {
            return id
        }
        return nil
    }

    private static func dataAttributeUserID(
        in attributes: [String: String]
    ) -> String? {
        let keys = [
            "data-uid", "data-user-id", "data-userid", "uid", "user-id"
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
               containsAnyOf: ["user", "author", "artist"]
           ) {
            return id
        }
        return nil
    }

    private static func dataAttributeLooksLikeItemCard(
        _ attributes: [String: String]
    ) -> Bool {
        let markerKeys = [
            "data-item-id", "data-itemid", "data-post-id",
            "data-work-id", "item-id"
        ]
        if markerKeys.contains(
            where: { attributes[$0]?.trimmed.isEmpty == false }
        ) {
            return true
        }
        return typeHint(
            in: attributes,
            containsAnyOf: ["item", "post", "work"]
        )
    }

    private static func dataAttributeLooksLikeUserCard(
        _ attributes: [String: String]
    ) -> Bool {
        let markerKeys = [
            "data-uid", "data-user-id", "data-userid", "uid", "user-id"
        ]
        if markerKeys.contains(
            where: { attributes[$0]?.trimmed.isEmpty == false }
        ) {
            return true
        }
        return typeHint(
            in: attributes,
            containsAnyOf: ["user", "author", "artist"]
        )
    }

    private static func firstSemanticAttribute(
        _ attributes: [String: String],
        keys: [String]
    ) -> String? {
        for key in keys {
            guard let value = attributes.first(
                where: { $0.key.lowercased() == key }
            )?.value.trimmed,
                  !value.isEmpty else {
                continue
            }
            return value
        }
        return nil
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
        let values = keys.compactMap { attributes[$0]?.lowercased() }
        return values.contains { value in
            needles.contains { value.contains($0) }
        }
    }

    private static func isValidPathSlug(_ value: String) -> Bool {
        !value.isEmpty &&
            value.range(
                of: #"^[A-Za-z0-9][A-Za-z0-9_-]*$"#,
                options: .regularExpression
            ) != nil
    }

    private static func cleanedURL(
        _ url: URL,
        path: String
    ) -> URL? {
        guard var components = URLComponents(
            url: url,
            resolvingAgainstBaseURL: false
        ) else {
            return nil
        }
        components.path = path
        components.queryItems = nil
        components.fragment = nil
        return components.url
    }
}

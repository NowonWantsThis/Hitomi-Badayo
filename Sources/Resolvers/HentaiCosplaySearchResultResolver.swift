import Foundation

struct HentaiCosplaySearchResultResolver: SearchResultResolving {
    private typealias Content = (kind: String, slug: String)

    func supports(_ baseURL: URL) -> Bool {
        guard let host = baseURL.host?.lowercased() else { return false }
        return Self.isSupportedHost(host)
    }

    static func isSupportedHost(_ host: String) -> Bool {
        supportedDomains.contains { host == $0 || host.hasSuffix("." + $0) }
    }

    static func dataAttributeLinkValue(
        in attributes: [String: String],
        baseURL: URL?
    ) -> String? {
        guard let baseURL,
              let host = baseURL.host?.lowercased(),
              isSupportedHost(host),
              let content = dataAttributeContent(in: attributes),
              dataAttributeLooksLikeContentCard(
                  attributes,
                  kind: content.kind
              ) else {
            return nil
        }
        return "/\(content.kind)/\(content.slug)/"
    }

    func extract(from context: SearchResultResolverContext) -> [SearchResultLink] {
        var results: [SearchResultLink] = []
        var indexByContentID: [String: Int] = [:]

        for anchor in context.anchors {
            guard results.count < context.limit,
                  let absolute = context.resolvedURL(for: anchor),
                  let canonicalURL = HentaiCosplayResolver.canonicalURL(for: absolute),
                  let host = canonicalURL.host?.lowercased(),
                  Self.isSupportedHost(host),
                  let content = content(from: canonicalURL),
                  let target = targetURL(for: content, sourceURL: canonicalURL) else {
                continue
            }

            let title = context.title(for: anchor, fallback: content.slug)
            SearchResultResolverSupport.appendUniqueResult(
                title: title,
                url: target,
                id: "\(content.kind):\(content.slug)",
                sitePrefix: "hentaicosplay",
                results: &results,
                indexByID: &indexByContentID,
                metadata: metadata(
                    content: content,
                    title: title,
                    contributorMetadata: context.contributorMetadata(for: anchor)
                )
            )
        }

        return results
    }

    private func content(from url: URL) -> Content? {
        guard let host = url.host?.lowercased(), Self.isSupportedHost(host) else { return nil }
        let loweredPath = url.path.lowercased()
        let parts = url.path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        let isPageOnly = parts.count == 2 &&
            parts[0].lowercased() == "page" &&
            parts[1].allSatisfy(\.isNumber)
        guard !loweredPath.contains("/attachment/"), !isPageOnly else {
            return nil
        }

        for kind in ["story", "image", "video"] {
            guard let index = parts.firstIndex(where: { $0.lowercased() == kind }),
                  index + 1 < parts.count else {
                continue
            }
            let slug = (parts[index + 1] as NSString).deletingPathExtension.trimmed
            guard isValidSlug(slug) else { return nil }
            return (kind, slug)
        }
        return nil
    }

    private func targetURL(for content: Content, sourceURL: URL) -> URL? {
        guard var components = URLComponents(url: sourceURL, resolvingAgainstBaseURL: false) else {
            return nil
        }
        components.path = "/\(content.kind)/\(content.slug)/"
        components.queryItems = nil
        components.fragment = nil
        return components.url
    }

    private func metadata(
        content: Content,
        title: String,
        contributorMetadata: [String: String]
    ) -> [String: String] {
        var metadata = contributorMetadata
        metadata.merge([
            "id": content.slug,
            "content_id": content.slug,
            "slug": content.slug,
            "gallery_id": content.slug,
            "media_id": content.slug,
            "category": "hentai_cosplay",
            "type": content.kind,
            "media_type": content.kind == "video" ? "video" : "image",
            "title": title,
            "search_title": title
        ]) { current, _ in current }
        return DownloadMetadata.clean(metadata)
    }

    private func isValidSlug(_ value: String) -> Bool {
        !value.isEmpty &&
            value.range(
                of: #"^[A-Za-z0-9][A-Za-z0-9_-]*$"#,
                options: .regularExpression
            ) != nil
    }

    private static func dataAttributeContent(
        in attributes: [String: String]
    ) -> Content? {
        for kind in ["story", "image", "video"] {
            let keys = [
                "data-\(kind)-slug", "data-\(kind)-id",
                "\(kind)-slug", "\(kind)-id"
            ]
            if let slug = firstAttributeValue(
                in: attributes,
                keys: keys,
                matching: isValidPathSlug
            ) {
                return (kind, slug)
            }
        }

        guard let kind = dataAttributeKind(in: attributes) else {
            return nil
        }
        let keys = [
            "data-content-id", "data-contentid", "data-slug",
            "data-id", "content-id", "slug"
        ]
        guard let slug = firstAttributeValue(
            in: attributes,
            keys: keys,
            matching: isValidPathSlug
        ) else {
            return nil
        }
        return (kind, slug)
    }

    private static func dataAttributeKind(
        in attributes: [String: String]
    ) -> String? {
        let values = [
            "data-type", "data-kind", "data-content-type",
            "class", "role"
        ].compactMap {
            attributes[$0]?.lowercased()
        }
        for kind in ["story", "image", "video"] {
            if values.contains(where: { $0.contains(kind) }) {
                return kind
            }
        }
        return nil
    }

    private static func dataAttributeLooksLikeContentCard(
        _ attributes: [String: String],
        kind: String
    ) -> Bool {
        let keys = [
            "data-\(kind)-slug", "data-\(kind)-id",
            "data-content-id", "data-contentid", "data-slug",
            "content-id"
        ]
        if keys.contains(where: {
            attributes[$0]?.trimmed.isEmpty == false
        }) {
            return true
        }
        return typeHint(
            in: attributes,
            containsAnyOf: [kind, "content", "post"]
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

    private static func isValidPathSlug(_ value: String) -> Bool {
        !value.isEmpty &&
            value.range(
                of: #"^[A-Za-z0-9][A-Za-z0-9_-]*$"#,
                options: .regularExpression
            ) != nil
    }

    private static let supportedDomains = [
        "hentai-cosplays.com",
        "porn-images-xxx.com",
        "hentai-img.com",
        "porn-video-xxx.com",
        "hentai-cosplays.test",
        "porn-images-xxx.test",
        "hentai-img.test",
        "porn-video-xxx.test"
    ]
}

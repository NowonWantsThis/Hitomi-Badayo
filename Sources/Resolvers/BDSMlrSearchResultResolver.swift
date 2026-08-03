import Foundation

struct BDSMlrSearchResultResolver: SearchResultResolving {
    func supports(_ baseURL: URL) -> Bool {
        guard let host = baseURL.host?.lowercased() else { return false }
        return Self.isSupportedHost(host)
    }

    static func isSupportedHost(_ host: String) -> Bool {
        host == "bdsmlr.com" ||
            host == "www.bdsmlr.com" ||
            host.hasSuffix(".bdsmlr.com") ||
            host == "bdsmlr.test" ||
            host == "www.bdsmlr.test" ||
            host.hasSuffix(".bdsmlr.test")
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
        if dataAttributeLooksLikePostCard(attributes),
           let post = dataAttributePost(in: attributes, baseURL: baseURL) {
            return postURL(
                blog: post.blog,
                postID: post.postID,
                sourceURL: baseURL
            )?.absoluteString
        }
        if dataAttributeLooksLikeBlogCard(attributes),
           let blog = dataAttributeBlogName(in: attributes) {
            return BDSMlrResolver.canonicalBlogURL(
                blogName: blog,
                sourceURL: baseURL
            ).absoluteString
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

            let key = resultKey(for: target)
            let title = context.title(for: anchor, fallbackURL: target)
            SearchResultResolverSupport.appendUniqueResult(
                title: title,
                url: target,
                id: key,
                sitePrefix: "bdsmlr",
                results: &results,
                indexByID: &indexByKey,
                metadata: metadata(
                    target: target,
                    title: title,
                    context: context,
                    anchor: anchor
                )
            )
        }

        return results
    }

    private func canonicalURL(from url: URL) -> URL? {
        guard let host = url.host?.lowercased(), Self.isSupportedHost(host) else {
            return nil
        }
        if let postID = BDSMlrResolver.postID(from: url),
           let blog = BDSMlrResolver.blogName(from: url) {
            return Self.postURL(
                blog: blog,
                postID: postID,
                sourceURL: url
            )
        }

        if let blog = BDSMlrResolver.blogName(from: url) {
            return BDSMlrResolver.canonicalBlogURL(
                blogName: blog,
                sourceURL: url
            )
        }
        return nil
    }

    private func resultKey(for url: URL) -> String {
        if let postID = BDSMlrResolver.postID(from: url) {
            return "post:\(postID)"
        }
        return "blog:\(url.host?.lowercased() ?? url.absoluteString.lowercased())"
    }

    private func metadata(
        target: URL,
        title: String,
        context: SearchResultResolverContext,
        anchor: AnchorEntry
    ) -> [String: String] {
        let blog = BDSMlrResolver.blogName(from: target) ??
            target.host?.split(separator: ".").first.map(String.init) ??
            ""
        var metadata = context.contributorMetadata(
            for: anchor,
            fallbackName: nil,
            fallbackUsername: blog,
            fallbackUserID: blog
        )
        metadata.merge([
            "blog": blog,
            "blog_id": blog,
            "username": blog,
            "user": blog,
            "uploader": metadata["uploader"] ?? blog,
            "uploader_id": blog,
            "channel_id": blog,
            "category": "bdsmlr",
            "title": title,
            "search_title": title
        ]) { current, _ in current }
        if let postID = BDSMlrResolver.postID(from: target) {
            metadata["id"] = postID
            metadata["post_id"] = postID
            metadata["gallery_id"] = postID
            metadata["media_id"] = postID
            metadata["type"] = "post"
        } else {
            metadata["id"] = blog
            metadata["gallery_id"] = blog
            metadata["type"] = "blog"
        }
        return DownloadMetadata.clean(metadata)
    }

    private static func dataAttributePost(
        in attributes: [String: String],
        baseURL: URL
    ) -> (blog: String, postID: String)? {
        let postID = firstAttributeValue(
            in: attributes,
            keys: ["data-post-id", "data-postid", "post-id", "data-id"],
            matching: isNumericID
        )
        guard let postID,
              let blog = dataAttributeBlogName(in: attributes) ??
                BDSMlrResolver.blogName(from: baseURL) else {
            return nil
        }
        return (blog, postID)
    }

    private static func dataAttributeBlogName(
        in attributes: [String: String]
    ) -> String? {
        firstAttributeValue(
            in: attributes,
            keys: [
                "data-blog", "data-blog-id", "data-blog-name",
                "data-username", "data-user", "blog", "username", "user"
            ],
            matching: isValidPathSlug
        )
    }

    private static func dataAttributeLooksLikePostCard(
        _ attributes: [String: String]
    ) -> Bool {
        let markerKeys = ["data-post-id", "data-postid", "post-id"]
        if markerKeys.contains(where: {
            attributes[$0]?.trimmed.isEmpty == false
        }) {
            return true
        }
        return typeHint(in: attributes, containsAnyOf: ["post"])
    }

    private static func dataAttributeLooksLikeBlogCard(
        _ attributes: [String: String]
    ) -> Bool {
        let markerKeys = ["data-blog", "data-blog-id", "data-blog-name"]
        if markerKeys.contains(where: {
            attributes[$0]?.trimmed.isEmpty == false
        }) {
            return true
        }
        return typeHint(
            in: attributes,
            containsAnyOf: ["blog", "profile", "user"]
        )
    }

    private static func postURL(
        blog: String,
        postID: String,
        sourceURL: URL
    ) -> URL? {
        var components = URLComponents()
        components.scheme = sourceURL.scheme ?? "https"
        let domain = sourceURL.host?.lowercased().hasSuffix(".test") == true
            ? "bdsmlr.test"
            : "bdsmlr.com"
        components.host = "\(blog).\(domain)"
        components.path = "/post/\(postID)"
        return components.url
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

    private static func isNumericID(_ value: String) -> Bool {
        value.range(
            of: #"^[0-9]+$"#,
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
}

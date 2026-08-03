import Foundation

struct NaverBlogSearchResultResolver: SearchResultResolving {
    func supports(_ baseURL: URL) -> Bool {
        guard let host = baseURL.host?.lowercased() else { return false }
        return Self.isSupportedHost(host)
    }

    static func isSupportedHost(_ host: String) -> Bool {
        host == "blog.naver.com" ||
            host == "m.blog.naver.com" ||
            host == "blog.naver.test" ||
            host == "m.blog.naver.test" ||
            host.hasSuffix(".blog.me") ||
            host.hasSuffix(".blog.test")
    }

    static func dataAttributeLinkValue(
        in attributes: [String: String],
        baseURL: URL
    ) -> String? {
        guard let host = baseURL.host?.lowercased(),
              isSupportedHost(host),
              dataAttributeLooksLikePostCard(attributes),
              let post = dataAttributePost(
                  in: attributes,
                  baseURL: baseURL
              ) else {
            return nil
        }
        if host.hasSuffix(".blog.me") || host.hasSuffix(".blog.test") {
            return "/\(post.postID)"
        }

        var components = URLComponents()
        components.path = "/PostView.nhn"
        components.queryItems = [
            URLQueryItem(name: "blogId", value: post.blogID),
            URLQueryItem(name: "logNo", value: post.postID)
        ]
        return components.string
    }

    func extract(from context: SearchResultResolverContext) -> [SearchResultLink] {
        var results: [SearchResultLink] = []
        var indexByPost: [String: Int] = [:]

        for anchor in context.anchors {
            guard results.count < context.limit,
                  let absolute = context.resolvedURL(for: anchor),
                  let post = NaverBlogResolver.postID(from: absolute) else {
                continue
            }

            let title = context.title(
                for: anchor,
                fallback: "Naver Blog \(post.postID)"
            )
            SearchResultResolverSupport.appendUniqueResult(
                title: title,
                url: NaverBlogResolver.mobilePostURL(
                    for: post,
                    sourceURL: absolute
                ),
                id: "\(post.username):\(post.postID)",
                sitePrefix: "naverblog",
                results: &results,
                indexByID: &indexByPost,
                metadata: metadata(
                    post: post,
                    title: title,
                    contributorMetadata: context.contributorMetadata(
                        for: anchor,
                        fallbackName: nil,
                        fallbackUsername: post.username,
                        fallbackUserID: post.username
                    )
                )
            )
        }

        return results
    }

    private func metadata(
        post: NaverBlogID,
        title: String,
        contributorMetadata: [String: String]
    ) -> [String: String] {
        var metadata = contributorMetadata
        metadata.merge([
            "id": post.postID,
            "post_id": post.postID,
            "gallery_id": post.postID,
            "media_id": post.postID,
            "blog_id": post.username,
            "username": post.username,
            "user": post.username,
            "uploader": post.username,
            "uploader_id": post.username,
            "channel_id": post.username,
            "category": "blog",
            "type": "post",
            "title": title,
            "search_title": title
        ]) { current, _ in current }
        return DownloadMetadata.clean(metadata)
    }

    private static func dataAttributePost(
        in attributes: [String: String],
        baseURL: URL
    ) -> (blogID: String, postID: String)? {
        let postKeys = [
            "data-log-no", "data-logno", "data-post-id", "data-postid",
            "data-article-id", "data-articleid", "logno", "log-no", "post-id"
        ]
        let postID = firstAttributeValue(
            in: attributes,
            keys: postKeys,
            matching: isPositiveNumericID
        ) ?? (typeHint(
            in: attributes,
            containsAnyOf: ["post", "article", "blog"]
        ) ? firstAttributeValue(
            in: attributes,
            keys: ["data-id", "id"],
            matching: isPositiveNumericID
        ) : nil)
        guard let postID else { return nil }

        let blogKeys = [
            "data-blog-id", "data-blogid", "data-blog", "data-author-id",
            "data-author", "data-user-id", "data-user", "data-username",
            "blogid", "blog-id", "blog", "username"
        ]
        let blogID = firstAttributeValue(
            in: attributes,
            keys: blogKeys,
            matching: isPathSlug
        ) ?? blogName(from: baseURL)
        guard let blogID else { return nil }
        return (blogID, postID)
    }

    private static func dataAttributeLooksLikePostCard(
        _ attributes: [String: String]
    ) -> Bool {
        let markerKeys = [
            "data-log-no", "data-logno", "data-post-id", "data-postid",
            "data-article-id", "data-articleid"
        ]
        if markerKeys.contains(where: {
            attributes[$0]?.trimmed.isEmpty == false
        }) {
            return true
        }
        return typeHint(
            in: attributes,
            containsAnyOf: ["post", "article", "blog"]
        )
    }

    private static func blogName(from url: URL) -> String? {
        guard let host = url.host?.lowercased(),
              host.hasSuffix(".blog.me") || host.hasSuffix(".blog.test"),
              let username = host.split(separator: ".").first.map(String.init),
              isPathSlug(username) else {
            return nil
        }
        return username
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

    private static func isPathSlug(_ value: String) -> Bool {
        !value.isEmpty &&
            value.count <= 80 &&
            value.range(
                of: #"^[A-Za-z0-9][A-Za-z0-9_-]*$"#,
                options: .regularExpression
            ) != nil
    }
}

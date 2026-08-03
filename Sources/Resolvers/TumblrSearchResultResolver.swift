import Foundation

struct TumblrSearchResultResolver: SearchResultResolving {
    func supports(_ baseURL: URL) -> Bool {
        guard let host = baseURL.host?.lowercased() else { return false }
        return Self.isSupportedHost(host)
    }

    static func isSupportedHost(_ host: String) -> Bool {
        host == "tumblr.com" ||
            host == "www.tumblr.com" ||
            host == "tumblr.test" ||
            host == "www.tumblr.test" ||
            host.hasSuffix(".tumblr.com") ||
            host.hasSuffix(".tumblr.test")
    }

    static func dataAttributeLinkValue(
        in attributes: [String: String],
        baseURL: URL?
    ) -> String? {
        guard let host = baseURL?.host?.lowercased(),
              isSupportedHost(host),
              let blog = dataAttributeBlogName(in: attributes),
              dataAttributeLooksLikeBlogOrPostCard(attributes) else {
            return nil
        }
        if let postID = dataAttributePostID(in: attributes) {
            return "/\(blog)/\(postID)/post"
        }
        return "/\(blog)"
    }

    func extract(from context: SearchResultResolverContext) -> [SearchResultLink] {
        var results: [SearchResultLink] = []
        var indexByBlog: [String: Int] = [:]

        for anchor in context.anchors {
            guard results.count < context.limit,
                  let absolute = context.resolvedURL(for: anchor),
                  let blog = Self.blogName(from: absolute),
                  let target = Self.blogURL(
                      blog: blog,
                      sourceURL: absolute
                  ) else {
                continue
            }

            let title = context.title(
                for: anchor,
                fallback: "Tumblr \(blog)"
            )
            SearchResultResolverSupport.appendUniqueResult(
                title: title,
                url: target,
                id: blog,
                sitePrefix: "tumblr",
                results: &results,
                indexByID: &indexByBlog,
                metadata: metadata(
                    blog: blog,
                    title: title,
                    contributorMetadata: context.contributorMetadata(
                        for: anchor,
                        fallbackName: nil,
                        fallbackUsername: blog,
                        fallbackUserID: blog
                    ),
                    originalURL: absolute
                )
            )
        }

        return results
    }

    private func metadata(
        blog: String,
        title: String,
        contributorMetadata: [String: String],
        originalURL: URL
    ) -> [String: String] {
        var metadata = [
            "id": blog,
            "blog_id": blog,
            "blog": blog,
            "username": blog,
            "user": blog,
            "uploader": blog,
            "uploader_id": blog,
            "channel_id": blog,
            "category": "tumblr",
            "type": "blog",
            "title": title,
            "search_title": title
        ]
        if let postID = Self.postID(from: originalURL) {
            metadata["id"] = postID
            metadata["post_id"] = postID
            metadata["media_id"] = postID
            metadata["type"] = "post"
        }
        metadata.merge(contributorMetadata) { current, _ in current }
        return DownloadMetadata.clean(metadata)
    }

    private static func postID(from url: URL) -> String? {
        if let items = URLComponents(
            url: url,
            resolvingAgainstBaseURL: false
        )?.queryItems {
            for name in ["redirect_to", "url"] {
                guard let nested = items.first(where: {
                    $0.name.lowercased() == name
                })?.value,
                    let nestedURL = redirectURL(
                        from: nested,
                        sourceURL: url
                    ),
                    nestedURL.absoluteString != url.absoluteString,
                    let nestedID = postID(from: nestedURL) else {
                    continue
                }
                return nestedID
            }
        }

        let parts = url.path
            .split(separator: "/", omittingEmptySubsequences: true)
            .map { String($0).removingPercentEncoding ?? String($0) }
        if let postIndex = parts.firstIndex(where: {
            $0.lowercased() == "post"
        }), postIndex + 1 < parts.count {
            let value = parts[postIndex + 1].trimmed
            return value.allSatisfy(\.isNumber) ? value : nil
        }
        guard parts.count >= 2,
              parts[1].allSatisfy(\.isNumber) else {
            return nil
        }
        return parts[1]
    }

    private static func blogName(from url: URL) -> String? {
        if let items = URLComponents(
            url: url,
            resolvingAgainstBaseURL: false
        )?.queryItems {
            for name in ["redirect_to", "url"] {
                guard let nested = items.first(where: {
                    $0.name.lowercased() == name
                })?.value,
                    let nestedURL = redirectURL(
                        from: nested,
                        sourceURL: url
                    ),
                    nestedURL.absoluteString != url.absoluteString,
                    let nestedName = blogName(from: nestedURL) else {
                    continue
                }
                return nestedName
            }
        }

        guard let host = url.host?.lowercased(),
              isSupportedHost(host) else {
            return nil
        }
        let parts = url.path
            .split(separator: "/", omittingEmptySubsequences: true)
            .map(String.init)

        if let index = parts.firstIndex(where: {
            $0.lowercased() == "blog"
        }), index + 2 < parts.count,
           parts[index + 1].lowercased() == "view" {
            return cleanBlogName(parts[index + 2])
        }

        if let index = parts.firstIndex(where: {
            $0.lowercased() == "dashboard"
        }), index + 2 < parts.count,
           parts[index + 1].lowercased() == "blog" {
            return cleanBlogName(parts[index + 2])
        }

        if let index = parts.firstIndex(where: {
            $0.lowercased() == "login_required"
        }), index + 1 < parts.count {
            return cleanBlogName(parts[index + 1])
        }

        if ["tumblr.com", "www.tumblr.com", "tumblr.test",
            "www.tumblr.test"].contains(host) {
            guard let first = parts.first else { return nil }
            let reserved: Set<String> = [
                "about", "blog", "dashboard", "explore", "login",
                "privacy", "register", "search", "settings", "tagged",
                "terms"
            ]
            return reserved.contains(first.lowercased())
                ? nil
                : cleanBlogName(first)
        }

        guard host.hasSuffix(".tumblr.com") ||
                host.hasSuffix(".tumblr.test"),
              let subdomain = host.split(separator: ".").first.map(
                  String.init
              ),
              !["assets", "static", "www"].contains(
                  subdomain.lowercased()
              ) else {
            return nil
        }
        return cleanBlogName(subdomain)
    }

    private static func redirectURL(from raw: String, sourceURL: URL) -> URL? {
        let value = raw.trimmed
        guard !value.isEmpty else { return nil }
        if value.hasPrefix("http://") || value.hasPrefix("https://") {
            return URL(string: value)
        }
        if value.hasPrefix("//") {
            return URL(string: "\(sourceURL.scheme ?? "https"):\(value)")
        }
        let host = sourceURL.host?.lowercased().hasSuffix(".test") == true
            ? "tumblr.test"
            : "tumblr.com"
        return URL(
            string: value,
            relativeTo: URL(string: "https://\(host)")!
        )?.absoluteURL
    }

    private static func blogURL(blog: String, sourceURL: URL) -> URL? {
        var components = URLComponents()
        components.scheme = sourceURL.scheme ?? "https"
        components.host = sourceURL.host?.lowercased().hasSuffix(".test") ==
            true ? "www.tumblr.test" : "www.tumblr.com"
        components.path = "/\(blog)"
        return components.url
    }

    private static func dataAttributeBlogName(
        in attributes: [String: String]
    ) -> String? {
        firstAttributeValue(
            in: attributes,
            keys: [
                "data-blog-name", "data-blog", "data-tumblelog",
                "data-username", "data-user", "blog"
            ],
            matching: isValidBlogName
        )
    }

    private static func dataAttributePostID(
        in attributes: [String: String]
    ) -> String? {
        firstAttributeValue(
            in: attributes,
            keys: [
                "data-post-id", "data-postid", "data-id", "post-id"
            ],
            matching: isPostID
        )
    }

    private static func dataAttributeLooksLikeBlogOrPostCard(
        _ attributes: [String: String]
    ) -> Bool {
        let markerKeys = [
            "data-blog-name", "data-blog", "data-tumblelog",
            "data-post-id", "data-postid", "post-id"
        ]
        if markerKeys.contains(where: {
            attributes[$0]?.trimmed.isEmpty == false
        }) {
            return true
        }
        return typeHint(
            in: attributes,
            containsAnyOf: ["tumblr", "blog", "post"]
        )
    }

    private static func cleanBlogName(_ raw: String) -> String? {
        let blog = raw.removingPercentEncoding?.trimmed ?? raw.trimmed
        guard blog.range(
            of: #"^[A-Za-z0-9][A-Za-z0-9_-]*$"#,
            options: .regularExpression
        ) != nil else {
            return nil
        }
        return blog.lowercased()
    }

    private static func isValidBlogName(_ value: String) -> Bool {
        value.range(
            of: #"^[A-Za-z0-9][A-Za-z0-9_-]{0,63}$"#,
            options: .regularExpression
        ) != nil
    }

    private static func isPostID(_ value: String) -> Bool {
        value.range(
            of: #"^[0-9]+$"#,
            options: .regularExpression
        ) != nil
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
}

import Foundation

struct MyReadingMangaSearchResultResolver: SearchResultResolving {
    func supports(_ baseURL: URL) -> Bool {
        guard let host = baseURL.host?.lowercased() else { return false }
        return Self.isSupportedHost(host)
    }

    static func isSupportedHost(_ host: String) -> Bool {
        host == "myreadingmanga.info" ||
            host == "www.myreadingmanga.info" ||
            host == "myreadingmanga.test" ||
            host == "www.myreadingmanga.test"
    }

    static func dataAttributeLinkValue(
        in attributes: [String: String],
        baseURL: URL?
    ) -> String? {
        guard let host = baseURL?.host?.lowercased(),
              isSupportedHost(host) else {
            return nil
        }
        return dataAttributePostPath(in: attributes)
    }

    static func dataAttributePostPath(in attributes: [String: String]) -> String? {
        let explicitKeys = [
            "data-post-slug", "data-postslug", "data-post-id",
            "data-postid", "data-entry-slug", "post-slug"
        ]
        if let slug = firstAttributeValue(
            in: attributes,
            keys: explicitKeys,
            matching: isValidPostSlug
        ) {
            return "/\(slug)/"
        }
        guard typeHint(
            in: attributes,
            containsAnyOf: ["post", "article", "entry", "work"]
        ) else {
            return nil
        }
        if let slug = firstAttributeValue(
            in: attributes,
            keys: ["data-slug", "data-id", "slug", "id"],
            matching: isValidPostSlug
        ) {
            return "/\(slug)/"
        }
        return nil
    }

    func extract(from context: SearchResultResolverContext) -> [SearchResultLink] {
        var results: [SearchResultLink] = []
        var indexByPath: [String: Int] = [:]

        for anchor in context.anchors {
            guard results.count < context.limit,
                  let absolute = context.resolvedURL(for: anchor),
                  let targetPath = postPath(from: absolute),
                  let target = cleanedURL(absolute, path: targetPath) else {
                continue
            }

            let title = context.title(for: anchor, fallbackURL: target)
            SearchResultResolverSupport.appendUniqueResult(
                title: title,
                url: target,
                id: targetPath.lowercased(),
                sitePrefix: "myreadingmanga",
                results: &results,
                indexByID: &indexByPath,
                metadata: metadata(
                    path: targetPath,
                    title: title,
                    contributorMetadata: context.contributorMetadata(for: anchor)
                )
            )
        }

        return results
    }

    private func postPath(from url: URL) -> String? {
        guard let host = url.host?.lowercased(), Self.isSupportedHost(host) else {
            return nil
        }
        var parts = url.path
            .split(separator: "/", omittingEmptySubsequences: true)
            .map(String.init)
        guard let first = parts.first?.lowercased() else { return nil }

        let reserved: Set<String> = [
            "author", "category", "comments", "feed", "page", "tag",
            "wp-admin", "wp-content", "wp-includes", "wp-json"
        ]
        guard !reserved.contains(first) else { return nil }
        if first == "search" || isMediaFileExtension(url.pathExtension) {
            return nil
        }

        if parts.count >= 2,
           parts[parts.count - 2].lowercased() == "page",
           parts.last?.allSatisfy(\.isNumber) == true {
            parts.removeLast(2)
        }
        guard !parts.isEmpty else { return nil }
        return "/" + parts.joined(separator: "/") + "/"
    }

    private func cleanedURL(_ url: URL, path: String) -> URL? {
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

    private func metadata(
        path: String,
        title: String,
        contributorMetadata: [String: String]
    ) -> [String: String] {
        let slug = path
            .split(separator: "/", omittingEmptySubsequences: true)
            .first
            .map(String.init) ??
            path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        var metadata = contributorMetadata
        metadata.merge([
            "id": slug,
            "post_id": slug,
            "gallery_id": slug,
            "media_id": slug,
            "slug": slug,
            "category": "myreadingmanga",
            "type": "post",
            "title": title,
            "search_title": title
        ]) { current, _ in current }
        return DownloadMetadata.clean(metadata)
    }

    private func isMediaFileExtension(_ value: String) -> Bool {
        [
            "jpg", "jpeg", "png", "gif", "webp", "avif",
            "mp4", "webm", "mov", "m3u8", "zip", "cbz", "pdf"
        ].contains(value.lowercased())
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

    private static func isValidPostSlug(_ value: String) -> Bool {
        let reserved: Set<String> = [
            "author", "category", "comments", "feed", "page", "tag",
            "search", "wp-admin", "wp-content", "wp-includes", "wp-json"
        ]
        return !value.isEmpty &&
            value.range(
                of: #"^[A-Za-z0-9][A-Za-z0-9_-]*$"#,
                options: .regularExpression
            ) != nil &&
            !reserved.contains(value.lowercased())
    }
}

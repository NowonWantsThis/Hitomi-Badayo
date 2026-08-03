import Foundation

struct BooruSearchResultResolver: SearchResultResolving {
    func supports(_ baseURL: URL) -> Bool {
        BooruProvider.provider(for: baseURL) != nil
    }

    static func dataAttributeLinkValue(
        in attributes: [String: String],
        baseURL: URL?
    ) -> String? {
        guard let baseURL,
              let provider = BooruProvider.provider(for: baseURL),
              dataAttributeLooksLikePostCard(attributes),
              let id = dataAttributePostID(in: attributes) else {
            return nil
        }

        switch provider {
        case .danbooru:
            return "/posts/\(id)"
        case .yandere:
            return "/post/show/\(id)"
        case .gelbooru, .rule34:
            return "/index.php?page=post&s=view&id=\(id)"
        }
    }

    func extract(from context: SearchResultResolverContext) -> [SearchResultLink] {
        var results: [SearchResultLink] = []
        var indexByPostKey: [String: Int] = [:]

        for anchor in context.anchors {
            guard results.count < context.limit,
                  let absolute = context.resolvedURL(for: anchor),
                  let post = Self.post(from: absolute),
                  let target = Self.postURL(
                      post: post,
                      sourceURL: absolute
                  ) else {
                continue
            }

            let sitePrefix = post.provider.rawValue.lowercased()
            let key = "\(sitePrefix)-\(post.id)"
            let title = context.title(
                for: anchor,
                fallback: "\(post.provider.rawValue) \(post.id)"
            )
            if let existingIndex = indexByPostKey[key] {
                if Self.isWeakTitle(
                    results[existingIndex].title,
                    id: post.id,
                    sitePrefix: sitePrefix
                ),
                   !Self.isWeakTitle(
                       title,
                       id: post.id,
                       sitePrefix: sitePrefix
                   ) {
                    results[existingIndex].title = title
                }
                continue
            }

            indexByPostKey[key] = results.count
            results.append(SearchResultLink(
                title: title,
                url: target.absoluteString,
                siteIdentifier: sitePrefix,
                metadata: searchResultMetadata(
                    post: post,
                    target: target,
                    anchor: anchor,
                    context: context
                )
            ))
        }

        return results
    }

    private func searchResultMetadata(
        post: (provider: BooruProvider, id: String),
        target: URL,
        anchor: AnchorEntry,
        context: SearchResultResolverContext
    ) -> [String: String] {
        let sitePrefix = post.provider.rawValue.lowercased()
        var metadata = DownloadMetadata.clean([
            "site": sitePrefix,
            "result_id": post.id,
            "source_url": target.absoluteString,
            "page_url": target.absoluteString,
            "search_site": sitePrefix,
            "search_result_id": post.id,
            "search_url": target.absoluteString
        ])
        metadata["provider"] = post.provider.rawValue
        metadata["id"] = post.id
        metadata["post_id"] = post.id
        metadata["media_id"] = post.id
        metadata["gallery_id"] = post.id
        metadata["category"] = "booru"
        metadata["type"] = "post"

        let attributes = resultAttributes(
            postID: post.id,
            anchor: anchor,
            context: context
        )
        if let tags = Self.metadataValue(
            in: attributes,
            keys: [
                "data-tags", "data-tag-string",
                "data-tag-string-general", "tags", "tag-string"
            ]
        ) {
            let cleaned = Self.tagList(tags)
            metadata["tag"] = cleaned
            metadata["tags"] = cleaned
        }
        if let rating = Self.metadataValue(
            in: attributes,
            keys: ["data-rating", "rating"]
        ) {
            metadata["rating"] = Self.ratingValue(rating)
        }
        if let score = Self.metadataValue(
            in: attributes,
            keys: ["data-score", "score"]
        ) {
            metadata["score"] = score
        }
        if let uploader = Self.metadataValue(
            in: attributes,
            keys: [
                "data-uploader-name", "data-uploader", "data-owner",
                "data-author", "data-creator", "uploader", "owner",
                "author", "creator"
            ]
        ) {
            metadata["artist"] = uploader
            metadata["author"] = uploader
            metadata["creator"] = uploader
            metadata["uploader"] = uploader
        }
        if let userID = Self.metadataValue(
            in: attributes,
            keys: [
                "data-uploader-id", "data-user-id",
                "uploader-id", "user-id"
            ]
        ) {
            metadata["uploader_id"] = userID
            metadata["user_id"] = userID
        }
        if let date = Self.dateValue(Self.metadataValue(
            in: attributes,
            keys: [
                "data-created-at", "data-created", "data-date",
                "created-at", "created", "date"
            ]
        )) {
            metadata["date"] = date
            metadata["created"] = date
        }
        if let format = Self.metadataValue(
            in: attributes,
            keys: [
                "data-file-ext", "data-ext", "file-ext", "ext", "format"
            ]
        ) {
            metadata["format"] = format.lowercased()
            metadata["file_format"] = format.lowercased()
        }
        let width = Self.metadataValue(
            in: attributes,
            keys: ["data-width", "width", "image-width"]
        )
        let height = Self.metadataValue(
            in: attributes,
            keys: ["data-height", "height", "image-height"]
        )
        if let width {
            metadata["width"] = width
        }
        if let height {
            metadata["height"] = height
        }
        if let width, let height {
            metadata["resolution"] = "\(width)x\(height)"
        }

        return DownloadMetadata.clean(metadata)
    }

    private func resultAttributes(
        postID: String,
        anchor: AnchorEntry,
        context: SearchResultResolverContext
    ) -> [String: String] {
        var attributes = context.attributesIncludingEmbeddedImage(for: anchor)
        for candidate in Self.contextTags(
            forPostID: postID,
            html: anchor.contextHTML
        ) {
            let values = context.attributes(inTag: candidate)
            guard !values.isEmpty else { continue }
            attributes.merge(values) { current, new in
                current.isEmpty ? new : current
            }
        }
        return attributes
    }

    private static func contextTags(
        forPostID postID: String,
        html: String
    ) -> [String] {
        let escapedID = NSRegularExpression.escapedPattern(for: postID)
        let patterns = [
            #"(<[^>]*(?:data-id|data-post-id|data-post-id-value|post-id)\s*=\s*["']"# +
                escapedID + #"["'][^>]*>)"#,
            #"(<[^>]*\bid\s*=\s*["']p"# +
                escapedID + #"["'][^>]*>)"#
        ]
        return patterns.flatMap { pattern in
            matches(in: html, pattern: pattern)
        }
    }

    private static func metadataValue(
        in attributes: [String: String],
        keys: [String]
    ) -> String? {
        for key in keys {
            if let value = attributes.first(
                where: { $0.key.lowercased() == key }
            )?.value.trimmed,
               !value.isEmpty {
                return value
            }
        }
        return nil
    }

    private static func tagList(_ raw: String) -> String {
        let decoded = decodeHTML(raw)
        return decoded
            .components(
                separatedBy: CharacterSet(charactersIn: ",;|+ \n\t\r")
            )
            .map { $0.trimmed }
            .filter { !$0.isEmpty }
            .map { $0.replacingOccurrences(of: "_", with: " ") }
            .joined(separator: ", ")
    }

    private static func ratingValue(_ raw: String) -> String {
        switch raw.trimmed.lowercased() {
        case "s":
            return "safe"
        case "q":
            return "questionable"
        case "e":
            return "explicit"
        case "g":
            return "general"
        default:
            return raw.trimmed
        }
    }

    private static func dateValue(_ raw: String?) -> String? {
        guard let raw = raw?.trimmed, !raw.isEmpty else { return nil }
        if let match = firstCapture(
            in: raw,
            pattern: #"([0-9]{4}-[0-9]{2}-[0-9]{2})"#
        ) {
            return match
        }
        return raw
    }

    private static func post(
        from url: URL
    ) -> (provider: BooruProvider, id: String)? {
        guard let provider = BooruProvider.provider(for: url) else {
            return nil
        }
        let path = url.path
        let components = URLComponents(
            url: url,
            resolvingAgainstBaseURL: false
        )
        let queryItems = components?.queryItems ?? []

        switch provider {
        case .danbooru:
            let id = firstCapture(
                in: path,
                pattern: #"/posts/([0-9]+)"#
            ) ?? queryValue("id", in: queryItems)
            return id.map { (provider, $0) }
        case .yandere:
            let id = firstCapture(
                in: path,
                pattern: #"/post/show/([0-9]+)"#
            ) ?? queryValue("id", in: queryItems)
            return id.map { (provider, $0) }
        case .gelbooru, .rule34:
            guard queryValue(
                "page",
                in: queryItems
            )?.lowercased() == "post",
                  queryValue(
                      "s",
                      in: queryItems
                  )?.lowercased() == "view",
                  let id = queryValue("id", in: queryItems),
                  !id.isEmpty else {
                return nil
            }
            return (provider, id)
        }
    }

    private static func postURL(
        post: (provider: BooruProvider, id: String),
        sourceURL: URL
    ) -> URL? {
        var components = URLComponents()
        components.scheme = sourceURL.scheme ?? "https"
        components.host = sourceURL.host

        switch post.provider {
        case .danbooru:
            components.path = "/posts/\(post.id)"
        case .yandere:
            components.path = "/post/show/\(post.id)"
        case .gelbooru, .rule34:
            components.path = "/index.php"
            components.queryItems = [
                URLQueryItem(name: "page", value: "post"),
                URLQueryItem(name: "s", value: "view"),
                URLQueryItem(name: "id", value: post.id)
            ]
        }

        return components.url
    }

    private static func dataAttributePostID(
        in attributes: [String: String]
    ) -> String? {
        for key in [
            "data-id", "data-post-id", "data-post-id-value", "post-id"
        ] {
            if let value = attributes[key]?.trimmed,
               value.range(
                   of: #"^[0-9]+$"#,
                   options: .regularExpression
               ) != nil {
                return value
            }
        }
        if let value = attributes["id"]?.trimmed,
           let id = firstCapture(
               in: value,
               pattern: #"^p([0-9]+)$"#
           ) {
            return id
        }
        return nil
    }

    private static func dataAttributeLooksLikePostCard(
        _ attributes: [String: String]
    ) -> Bool {
        let markerKeys = [
            "data-tags", "data-tag-string", "data-tag-string-general",
            "data-rating", "data-score", "data-file-ext",
            "data-width", "data-height"
        ]
        if markerKeys.contains(
            where: { attributes[$0]?.trimmed.isEmpty == false }
        ) {
            return true
        }
        let hint = [
            attributes["class"] ?? "",
            attributes["data-type"] ?? "",
            attributes["data-kind"] ?? "",
            attributes["data-renderer"] ?? ""
        ].joined(separator: " ").lowercased()
        return ["post", "thumb", "preview", "image"].contains {
            hint.contains($0)
        }
    }

    private static func isWeakTitle(
        _ title: String,
        id: String,
        sitePrefix: String
    ) -> Bool {
        let value = title.trimmed.lowercased()
        return value.isEmpty ||
            value == "download" ||
            value == id ||
            value == "\(id).html" ||
            value == "\(sitePrefix) \(id)" ||
            value.contains("/\(id)")
    }

    private static func queryValue(
        _ name: String,
        in items: [URLQueryItem]
    ) -> String? {
        items.first {
            $0.name.lowercased() == name.lowercased()
        }?.value
    }

    private static func firstCapture(
        in text: String,
        pattern: String
    ) -> String? {
        guard let regex = try? NSRegularExpression(
            pattern: pattern,
            options: [.caseInsensitive]
        ) else {
            return nil
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              match.numberOfRanges > 1,
              let capture = Range(match.range(at: 1), in: text) else {
            return nil
        }
        return String(text[capture])
    }

    private static func matches(
        in text: String,
        pattern: String
    ) -> [String] {
        guard let regex = try? NSRegularExpression(
            pattern: pattern,
            options: [.caseInsensitive]
        ) else {
            return []
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.matches(in: text, range: range).compactMap { match in
            guard match.numberOfRanges > 1,
                  let capture = Range(
                      match.range(at: 1),
                      in: text
                  ) else {
                return nil
            }
            return String(text[capture])
        }
    }

    private static func decodeHTML(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
    }
}

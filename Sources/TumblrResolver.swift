import Foundation

final class TumblrResolver {
    private static let ignoredContentTypes: Set<String> = ["text", "link", "audio", "poll"]

    func canResolve(_ url: URL) -> Bool {
        Self.blogName(from: url) != nil
    }

    func resolve(
        _ url: URL,
        headers: HTTPRequestOptions = HTTPRequestOptions(),
        assetLimit: Int? = nil
    ) async throws -> ResolvedDownload {
        guard let blogName = Self.blogName(from: url) else {
            throw NativeDownloadError.invalidURL(url.absoluteString)
        }

        let finiteAssetLimit = assetLimit.flatMap { $0 > 0 ? $0 : nil }
        var pageURL = Self.postsAPIURL(blogName: blogName, sourceURL: url)
        var useDefaultQuery = true
        var posts: [[String: Any]] = []
        var blogTitle: String?
        var seenPostIDs = Set<String>()
        var seenPageURLs = Set<String>()
        var seenAssetURLs = Set<String>()
        var assetCount = 0

        while true {
            try Task.checkCancellation()
            let requestURL = useDefaultQuery ? Self.postsAPIURLWithDefaultQuery(pageURL) : pageURL
            guard seenPageURLs.insert(requestURL.absoluteString).inserted else { break }

            let data = try await Self.apiData(from: pageURL, sourceURL: url, headers: headers, defaultQuery: useDefaultQuery)
            let response = try Self.responseObject(fromAPIData: data)
            if blogTitle == nil {
                blogTitle = Self.blogTitle(fromResponse: response)
            }

            let pagePosts = (response["posts"] as? [[String: Any]] ?? [])
                .filter { Self.stringValue($0["object_type"]) != "backfill_ad" }
            for post in pagePosts {
                try Task.checkCancellation()
                guard let id = Self.stringValue(post["id"]), !seenPostIDs.contains(id) else { continue }
                seenPostIDs.insert(id)
                posts.append(post)
                for remote in Self.mediaURLs(fromPost: post, sourceURL: url) {
                    if seenAssetURLs.insert(URLIdentity.normalize(remote.absoluteString)).inserted {
                        assetCount += 1
                    }
                }
                if let finiteAssetLimit, assetCount >= finiteAssetLimit { break }
            }

            guard finiteAssetLimit.map({ assetCount < $0 }) ?? true,
                  let next = Self.nextPageURL(fromResponse: response, sourceURL: url) else {
                break
            }
            pageURL = next
            useDefaultQuery = false
        }

        return try Self.resolvedDownload(
            fromPosts: posts,
            blogName: blogName,
            blogTitle: blogTitle,
            sourceURL: url,
            maxAssets: finiteAssetLimit
        )
    }

    static func apiData(from url: URL, sourceURL: URL, headers: HTTPRequestOptions, defaultQuery: Bool) async throws -> Data {
        let requestURL = defaultQuery ? postsAPIURLWithDefaultQuery(url) : url
        return try await HTTPClient.shared.data(
            from: requestURL,
            referer: headers.referer ?? "https://www.tumblr.com",
            userAgent: headers.userAgent,
            additionalHeaders: tumblrHeaders()
        )
    }

    static func resolvedDownload(
        fromPosts posts: [[String: Any]],
        blogName: String,
        blogTitle: String?,
        sourceURL: URL,
        maxAssets: Int? = nil
    ) throws -> ResolvedDownload {
        var assets: [ResolvedAsset] = []
        var seen = Set<String>()

        for post in posts {
            let postID = stringValue(post["id"]) ?? "post"
            let referer = postReferer(post: post, blogName: blogName)
            for (postMediaIndex, remote) in mediaURLs(fromPost: post, sourceURL: sourceURL).enumerated() {
                let normalized = URLIdentity.normalize(remote.absoluteString)
                guard !seen.contains(normalized) else { continue }
                seen.insert(normalized)
                let index = assets.count + 1
                assets.append(ResolvedAsset(
                    remoteURL: remote,
                    filename: filename(for: remote, postID: postID, postMediaIndex: postMediaIndex),
                    metadata: assetMetadata(for: remote, postID: postID, blogName: blogName, blogTitle: blogTitle, referer: referer, index: index),
                    referer: referer
                ))
                if let maxAssets, assets.count >= maxAssets { break }
            }
            if let maxAssets, assets.count >= maxAssets { break }
        }

        guard !assets.isEmpty else {
            throw NativeDownloadError.noFiles
        }

        let title = "\(cleanTitle(blogTitle ?? blogName)) (tumblr_\(blogName))".sanitizedFilename(maxLength: 120)
        return ResolvedDownload(
            title: title,
            folderName: "Tumblr \(title)".sanitizedFilename(maxLength: 120),
            assets: assets,
            metadata: tumblrMetadata(blogName: blogName, blogTitle: blogTitle, assets: assets)
        )
    }

    static func responseObject(fromAPIData data: Data) throws -> [String: Any] {
        let object = try jsonObject(from: data)
        if let errors = object["errors"] as? [[String: Any]], !errors.isEmpty {
            let code = intValue(errors[0]["code"]) ?? -1
            if code == 0 {
                throw NativeDownloadError.unsupported("Tumblr blog was not found.")
            }
            let detail = stringValue(errors[0]["detail"]) ?? stringValue(errors[0]["title"]) ?? "Tumblr API error \(code)"
            throw NativeDownloadError.unsupported(detail)
        }
        return object["response"] as? [String: Any] ?? object
    }

    static func blogName(from url: URL) -> String? {
        let absolute = url.absoluteString
        let path = url.path
        guard let host = url.host?.lowercased(),
              host == "tumblr.com" || host == "www.tumblr.com" ||
                host == "tumblr.test" || host == "www.tumblr.test" ||
                host.hasSuffix(".tumblr.com") || host.hasSuffix(".tumblr.test") else {
            return nil
        }

        if path.contains("/dashboard/blog/"),
           let id = firstCapture(pattern: #"/dashboard/blog/([0-9A-Za-z_-]+)"#, in: path) {
            return id
        }

        if path.contains("/login_required/") {
            let parts = path.components(separatedBy: "/login_required/")
            if parts.count > 1,
               let id = parts[1].split(separator: "/").first.map(String.init),
               !id.isEmpty {
                return id
            }
        }

        if path.contains("/blog/view/"),
           let id = firstCapture(pattern: #"/blog/view/([^/#?]+)"#, in: path) {
            return cleanBlogName(id)
        }

        if let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems {
            for name in ["redirect_to", "url"] {
                guard let nested = items.first(where: { $0.name.lowercased() == name })?.value,
                      let nestedURL = tumblrRedirectURL(from: nested, sourceURL: url),
                      nestedURL.absoluteString != url.absoluteString,
                      let nestedName = blogName(from: nestedURL) else {
                    continue
                }
                return nestedName
            }
        }

        if host == "tumblr.com" || host == "www.tumblr.com" || host == "tumblr.test" || host == "www.tumblr.test" {
            let parts = path.split(separator: "/").map(String.init)
            guard let first = parts.first else { return nil }
            let reserved: Set<String> = ["post", "explore", "search", "dashboard", "login", "register", "privacy", "terms"]
            return reserved.contains(first.lowercased()) ? nil : cleanBlogName(first)
        }

        if host.hasSuffix(".tumblr.com") || host.hasSuffix(".tumblr.test") {
            guard let subdomain = host.split(separator: ".").first.map(String.init),
                  subdomain != "www" else {
                return nil
            }
            return cleanBlogName(subdomain)
        }

        return firstCapture(pattern: #"tumblr\.(?:com|test)/([^/#?]+)"#, in: absolute).map(cleanBlogName)
    }

    static func canonicalBlogURL(for url: URL) -> URL? {
        guard let blogName = canonicalBlogName(from: url),
              isValidBlogName(blogName) else {
            return nil
        }
        var components = URLComponents()
        components.scheme = url.scheme ?? "https"
        components.host = "\(blogName).\(url.host?.lowercased().hasSuffix(".test") == true ? "tumblr.test" : "tumblr.com")"
        return components.url
    }

    static func postsAPIURL(blogName: String, sourceURL: URL) -> URL {
        var components = URLComponents()
        components.scheme = sourceURL.scheme ?? "https"
        components.host = sourceURL.host?.lowercased().hasSuffix(".test") == true ? "www.tumblr.test" : "www.tumblr.com"
        components.path = "/api/v2/blog/\(blogName)/posts"
        return components.url!
    }

    static func postsAPIURLWithDefaultQuery(_ url: URL) -> URL {
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        var items = components.queryItems ?? []
        let defaults = [
            URLQueryItem(name: "fields[blogs]", value: "name,avatar,title,url,is_adult,?is_member,description_npf,uuid,can_be_followed,?followed,?advertiser_name,is_paywall_on,theme,subscription_plan,?primary,share_likes,share_following,can_subscribe,subscribed,ask,?can_submit,?is_blocked_from_primary,?tweet,?admin,can_message,?analytics_url,?top_tags,paywall_access"),
            URLQueryItem(name: "npf", value: "true"),
            URLQueryItem(name: "reblog_info", value: "false"),
            URLQueryItem(name: "include_pinned_posts", value: "false")
        ]
        for item in defaults where !items.contains(where: { $0.name == item.name }) {
            items.append(item)
        }
        components.queryItems = items
        return components.url!
    }

    static func mediaURLs(fromPost post: [String: Any], sourceURL: URL) -> [URL] {
        let content = contentBlocks(fromPost: post)
        var urls: [URL] = []
        var seen = Set<String>()
        for block in content {
            guard let type = stringValue(block["type"])?.lowercased(),
                  !ignoredContentTypes.contains(type),
                  ["image", "video"].contains(type),
                  let mediaValue = block["media"],
                  let raw = mediaURLString(from: mediaValue),
                  let remote = absoluteURL(raw, baseURL: sourceURL) else {
                continue
            }
            let normalized = URLIdentity.normalize(remote.absoluteString)
            guard !seen.contains(normalized) else { continue }
            seen.insert(normalized)
            urls.append(remote)
        }
        return urls
    }

    static func nextPageURL(fromResponse response: [String: Any], sourceURL: URL) -> URL? {
        let links = response["links"] as? [String: Any] ?? response["_links"] as? [String: Any]
        guard let next = links?["next"] as? [String: Any],
              let raw = stringValue(next["href"]) else {
            return nil
        }
        if raw.hasPrefix("http://") || raw.hasPrefix("https://") {
            return URL(string: raw)
        }
        var base = URLComponents()
        base.scheme = sourceURL.scheme ?? "https"
        base.host = sourceURL.host?.lowercased().hasSuffix(".test") == true ? "www.tumblr.test" : "www.tumblr.com"
        return URL(string: raw, relativeTo: base.url)?.absoluteURL
    }

    private static func contentBlocks(fromPost post: [String: Any]) -> [[String: Any]] {
        var blocks = post["content"] as? [[String: Any]] ?? []
        if let trails = post["trail"] as? [[String: Any]] {
            for trail in trails {
                blocks.append(contentsOf: trail["content"] as? [[String: Any]] ?? [])
            }
        }
        return blocks
    }

    private static func mediaURLString(from value: Any) -> String? {
        if let array = value as? [[String: Any]] {
            return array.first.flatMap { stringValue($0["url"]) }
        }
        if let dictionary = value as? [String: Any] {
            return stringValue(dictionary["url"])
        }
        return stringValue(value)
    }

    private static func blogTitle(fromResponse response: [String: Any]) -> String? {
        guard let blog = response["blog"] as? [String: Any] else { return nil }
        return stringValue(blog["title"]) ?? stringValue(blog["name"])
    }

    private static func postReferer(post: [String: Any], blogName: String) -> String {
        if let url = stringValue(post["post_url"]) ?? stringValue(post["url"]) {
            return url
        }
        let id = stringValue(post["id"]) ?? ""
        return "https://\(blogName).tumblr.com/post/\(id)"
    }

    private static func filename(for url: URL, postID: String, postMediaIndex: Int) -> String {
        let ext = url.pathExtension.trimmed.isEmpty ? "jpg" : url.pathExtension
        return "\(postID)_p\(postMediaIndex).\(ext)".sanitizedFilename(maxLength: 180)
    }

    private static func tumblrMetadata(blogName: String, blogTitle: String?, assets: [ResolvedAsset]) -> [String: String] {
        let displayName = cleanTitle(blogTitle ?? blogName)
        let imageCount = assets.filter { mediaType(for: $0.remoteURL) == "image" }.count
        let videoCount = assets.filter { mediaType(for: $0.remoteURL) == "video" }.count
        return DownloadMetadata.clean([
            "site": "Tumblr",
            "type": videoCount > 0 && imageCount == 0 ? "video" : "image",
            "media_type": videoCount > 0 && imageCount == 0 ? "video" : "image",
            "media_count": String(assets.count),
            "image_count": String(imageCount),
            "video_count": String(videoCount),
            "artist": displayName,
            "author": displayName,
            "creator": displayName,
            "user": blogName,
            "username": blogName,
            "uploader": displayName,
            "uploader_id": blogName,
            "channel": displayName,
            "channel_id": blogName
        ])
    }

    private static func assetMetadata(for url: URL, postID: String, blogName: String, blogTitle: String?, referer: String, index: Int) -> [String: String] {
        let displayName = cleanTitle(blogTitle ?? blogName)
        let format = mediaFormat(for: url)
        let mediaType = mediaType(for: url)
        return DownloadMetadata.clean([
            "site": "Tumblr",
            "type": mediaType,
            "media_type": mediaType,
            "artist": displayName,
            "author": displayName,
            "creator": displayName,
            "user": blogName,
            "username": blogName,
            "uploader": displayName,
            "uploader_id": blogName,
            "channel": displayName,
            "channel_id": blogName,
            "post_id": postID,
            "id": postID,
            "media_id": "\(postID)-\(index)",
            "page": String(index),
            "position": String(index),
            "format": format,
            "media_format": format,
            "image_url": mediaType == "image" ? url.absoluteString : "",
            "video_url": mediaType == "video" ? url.absoluteString : "",
            "media_url": url.absoluteString,
            "source_url": url.absoluteString,
            "page_url": referer
        ])
    }

    private static func mediaType(for url: URL) -> String {
        ["mp4", "webm", "mov", "m4v", "m3u8"].contains(mediaFormat(for: url)) ? "video" : "image"
    }

    private static func mediaFormat(for url: URL) -> String {
        let ext = url.pathExtension.trimmed.lowercased()
        return ext.isEmpty ? "jpg" : ext
    }

    private static func tumblrHeaders() -> [String: String] {
        [
            "Authorization": "Bearer aIcXSOoTtqrzR8L8YEIOmBeW94c3FmbSNSWAUbxsny9KKx5VFh",
            "Accept": "application/json, text/plain, */*"
        ]
    }

    private static func absoluteURL(_ raw: String, baseURL: URL) -> URL? {
        let value = raw.trimmed
        if value.hasPrefix("//") {
            return URL(string: "\(baseURL.scheme ?? "https"):\(value)")
        }
        return URL(string: value, relativeTo: baseURL)?.absoluteURL
    }

    private static func tumblrRedirectURL(from raw: String, sourceURL: URL) -> URL? {
        let value = raw.trimmed
        guard !value.isEmpty else { return nil }
        if value.hasPrefix("http://") || value.hasPrefix("https://") || value.hasPrefix("//") {
            return absoluteURL(value, baseURL: sourceURL)
        }
        let host = sourceURL.host?.lowercased().hasSuffix(".test") == true ? "tumblr.test" : "tumblr.com"
        return URL(string: value, relativeTo: URL(string: "https://\(host)")!)?.absoluteURL
    }

    private static func canonicalBlogName(from url: URL) -> String? {
        if let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems {
            for name in ["redirect_to", "url"] {
                guard let nested = items.first(where: { $0.name.lowercased() == name })?.value,
                      let nestedURL = tumblrRedirectURL(from: nested, sourceURL: url),
                      nestedURL.absoluteString != url.absoluteString,
                      let nestedName = canonicalBlogName(from: nestedURL) else {
                    continue
                }
                return nestedName
            }
        }

        guard let host = url.host?.lowercased(),
              host == "tumblr.com" ||
                host == "www.tumblr.com" ||
                host == "tumblr.test" ||
                host == "www.tumblr.test" ||
                host.hasSuffix(".tumblr.com") ||
                host.hasSuffix(".tumblr.test") else {
            return nil
        }

        let parts = url.path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        if let index = parts.firstIndex(where: { $0.lowercased() == "dashboard" }),
           index + 2 < parts.count,
           parts[index + 1].lowercased() == "blog" {
            return cleanBlogName(parts[index + 2])
        }
        if let index = parts.firstIndex(where: { $0.lowercased() == "login_required" }),
           index + 1 < parts.count {
            return cleanBlogName(parts[index + 1])
        }
        if let index = parts.firstIndex(where: { $0.lowercased() == "blog" }),
           index + 2 < parts.count,
           parts[index + 1].lowercased() == "view" {
            return cleanBlogName(parts[index + 2])
        }

        if host == "tumblr.com" || host == "www.tumblr.com" || host == "tumblr.test" || host == "www.tumblr.test" {
            guard let first = parts.first else { return nil }
            let reserved: Set<String> = [
                "about", "blog", "dashboard", "explore", "login", "privacy",
                "register", "search", "settings", "tagged", "terms"
            ]
            return reserved.contains(first.lowercased()) ? nil : cleanBlogName(first)
        }

        let hostParts = host.split(separator: ".").map(String.init)
        guard hostParts.count == 3,
              hostParts[1] == "tumblr",
              !["assets", "static", "www"].contains(hostParts[0].lowercased()) else {
            return nil
        }
        return cleanBlogName(hostParts[0])
    }

    private static func isValidBlogName(_ value: String) -> Bool {
        value.range(of: #"^[0-9A-Za-z][0-9A-Za-z_-]*$"#, options: .regularExpression) != nil
    }

    private static func cleanBlogName(_ raw: String) -> String {
        raw.removingPercentEncoding?.trimmed.trimmingCharacters(in: CharacterSet(charactersIn: "/")) ?? raw
    }

    private static func cleanTitle(_ raw: String) -> String {
        raw.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmed
            .sanitizedFilename(maxLength: 100)
    }

    private static func firstCapture(pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
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

    private static func jsonObject(from data: Data) throws -> [String: Any] {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw NativeDownloadError.invalidGalleryData
        }
        return object
    }

    private static func stringValue(_ value: Any?) -> String? {
        if let string = value as? String { return string }
        if let number = value as? NSNumber { return number.stringValue }
        return nil
    }

    private static func intValue(_ value: Any?) -> Int? {
        if let int = value as? Int { return int }
        if let number = value as? NSNumber { return number.intValue }
        if let string = value as? String { return Int(string) }
        return nil
    }
}

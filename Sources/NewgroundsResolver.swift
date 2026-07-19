import Foundation

final class NewgroundsResolver {
    func canResolve(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased(),
              Self.isNewgroundsHost(host),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            return false
        }

        return Self.isArtViewURL(url) || Self.artistUsername(from: url) != nil
    }

    func resolve(_ url: URL, headers: HTTPRequestOptions = HTTPRequestOptions()) async throws -> ResolvedDownload {
        let sourceURL = Self.canonicalArtistArtURL(for: url) ?? Self.canonicalArtViewURL(for: url) ?? url
        if let artist = Self.artistUsername(from: sourceURL) {
            return try await resolveArtistArt(username: artist, sourceURL: sourceURL, headers: headers)
        }

        let html = try await HTTPClient.shared.string(from: sourceURL, referer: headers.referer, userAgent: headers.userAgent)
        return try Self.resolvedDownload(fromHTML: html, pageURL: sourceURL)
    }

    private func resolveArtistArt(username: String, sourceURL: URL, headers: HTTPRequestOptions) async throws -> ResolvedDownload {
        let listURL = Self.artistArtURL(username: username, sourceURL: sourceURL)
        var firstHTML = ""
        var postURLs: [URL] = []
        var seenPosts = Set<String>()
        var page = 1

        while true {
            try Task.checkCancellation()
            let pageURL = Self.artistArtPageURL(baseURL: listURL, page: page)
            let html = try await HTTPClient.shared.string(
                from: pageURL,
                referer: page == 1 ? headers.referer ?? listURL.absoluteString : listURL.absoluteString,
                userAgent: headers.userAgent
            )
            if page == 1 {
                firstHTML = html
            }

            let pagePosts = Self.artPostURLs(fromHTML: html, baseURL: listURL)
            guard !pagePosts.isEmpty else { break }

            var added = 0
            for postURL in pagePosts {
                let normalized = URLIdentity.normalize(postURL.absoluteString)
                guard !seenPosts.contains(normalized) else { continue }
                seenPosts.insert(normalized)
                postURLs.append(postURL)
                added += 1
            }
            guard added > 0 else { break }
            guard page < Int.max else {
                throw NativeDownloadError.unsupported("Newgrounds pagination exceeded the supported integer range.")
            }
            page += 1
        }

        var downloads: [(url: URL, resolved: ResolvedDownload)] = []
        for postURL in postURLs {
            try Task.checkCancellation()
            let html = try await HTTPClient.shared.string(from: postURL, referer: listURL.absoluteString, userAgent: headers.userAgent)
            if Self.isLoginRequiredHTML(html) {
                throw NativeDownloadError.unsupported("Newgrounds login and age verification are required for this artwork.")
            }
            downloads.append((postURL, try Self.resolvedDownload(fromHTML: html, pageURL: postURL)))
        }

        guard !downloads.isEmpty else {
            throw NativeDownloadError.noFiles
        }

        let title = Self.artistListTitle(fromHTML: firstHTML, username: username)
        return try Self.resolvedCollectionDownload(title: title, username: username, sourceURL: listURL, postDownloads: downloads)
    }

    static func resolvedDownload(fromHTML html: String, pageURL: URL) throws -> ResolvedDownload {
        let title = title(from: html, pageURL: pageURL).sanitizedFilename(maxLength: 120)
        let artist = artistName(from: html, pageURL: pageURL)?.sanitizedFilename(maxLength: 80)
        let date = publishedDate(from: html)
        let artID = artSlug(from: pageURL) ?? title
        let urls = mediaURLs(from: html, pageURL: pageURL)
        guard !urls.isEmpty else {
            throw NativeDownloadError.noFiles
        }

        let assets = urls.enumerated().map { offset, remote in
            ResolvedAsset(
                remoteURL: remote,
                filename: filename(for: remote, title: title, date: date, index: offset + 1),
                metadata: assetMetadata(for: remote, title: title, artist: artist, artID: artID, pageURL: pageURL, date: date, index: offset + 1),
                referer: pageURL.absoluteString
            )
        }

        let folderTitle = [artist, title].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " - ")
        return ResolvedDownload(
            title: title,
            folderName: (folderTitle.isEmpty ? title : folderTitle).sanitizedFilename(maxLength: 120),
            assets: assets,
            metadata: newgroundsMetadata(
                title: title,
                artist: artist,
                type: "artwork",
                sourceURL: pageURL,
                mediaCount: assets.count,
                postCount: nil
            )
        )
    }

    private static func newgroundsMetadata(title: String, artist: String?, type: String, sourceURL: URL, mediaCount: Int, postCount: Int?) -> [String: String] {
        let identifier = type == "artwork" ? artSlug(from: sourceURL) ?? title : artist ?? ""
        return DownloadMetadata.clean([
            "site": "Newgrounds",
            "title": title,
            "series": title,
            "category": "image",
            "type": type,
            "media_type": type,
            "host": sourceURL.host ?? "",
            "id": identifier,
            "art_id": type == "artwork" ? identifier : "",
            "media_count": mediaCount > 0 ? String(mediaCount) : "",
            "image_count": mediaCount > 0 ? String(mediaCount) : "",
            "post_count": postCount.map(String.init) ?? "",
            "gallery_id": identifier,
            "slug": identifier,
            "url": sourceURL.absoluteString,
            "source_url": sourceURL.absoluteString,
            "page_url": sourceURL.absoluteString,
            "artist": artist ?? "",
            "author": artist ?? "",
            "creator": artist ?? "",
            "user": artist ?? "",
            "username": artist ?? "",
            "uploader": artist ?? "",
            "channel": artist ?? ""
        ])
    }

    private static func assetMetadata(for url: URL, title: String, artist: String?, artID: String, pageURL: URL, date: String?, index: Int) -> [String: String] {
        let format = mediaFormat(for: url)
        let mediaID = "\(artID)-\(index)"
        return DownloadMetadata.clean([
            "site": "Newgrounds",
            "title": title,
            "series": title,
            "type": "image",
            "media_type": "image",
            "category": "image",
            "id": artID,
            "art_id": artID,
            "gallery_id": artID,
            "media_id": mediaID,
            "page": String(index),
            "position": String(index),
            "slug": artID,
            "format": format,
            "media_format": format,
            "date": date ?? "",
            "published_date": date ?? "",
            "artist": artist ?? "",
            "author": artist ?? "",
            "creator": artist ?? "",
            "user": artist ?? "",
            "username": artist ?? "",
            "uploader": artist ?? "",
            "channel": artist ?? "",
            "image_url": url.absoluteString,
            "media_url": url.absoluteString,
            "source_url": url.absoluteString,
            "page_url": pageURL.absoluteString
        ])
    }

    private static func mediaFormat(for url: URL) -> String {
        let pathExtension = url.pathExtension.lowercased()
        if !pathExtension.isEmpty {
            return pathExtension
        }
        let lower = url.absoluteString.lowercased()
        for value in mediaExtensions where lower.contains(".\(value)") {
            return value
        }
        return ""
    }

    private static func artSlug(from url: URL) -> String? {
        let parts = url.path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        guard let viewIndex = parts.firstIndex(where: { $0.lowercased() == "view" }),
              viewIndex + 2 < parts.count else {
            return nil
        }
        let slug = parts[(viewIndex + 2)...].joined(separator: "/")
        return slug.trimmed.isEmpty ? nil : slug.sanitizedFilename(maxLength: 120)
    }

    static func resolvedCollectionDownload(title: String, username: String, sourceURL: URL, postDownloads: [(url: URL, resolved: ResolvedDownload)]) throws -> ResolvedDownload {
        var assets: [ResolvedAsset] = []
        var seenFiles = Set<String>()

        for (postIndex, item) in postDownloads.enumerated() {
            for asset in item.resolved.assets {
                var filename = asset.filename.sanitizedFilename(maxLength: 180)
                if seenFiles.contains(filename.lowercased()) {
                    let ext = (filename as NSString).pathExtension
                    let base = (filename as NSString).deletingPathExtension
                    filename = ext.isEmpty
                        ? "\(base)-\(assets.count + 1)"
                        : "\(base)-\(assets.count + 1).\(ext)"
                }
                seenFiles.insert(filename.lowercased())
                var metadata = asset.metadata
                metadata["post_index"] = String(postIndex + 1)
                metadata["page"] = String(assets.count + 1)
                metadata["position"] = String(assets.count + 1)
                assets.append(ResolvedAsset(
                    remoteURL: asset.remoteURL,
                    filename: filename,
                    metadata: metadata,
                    referer: asset.referer ?? item.url.absoluteString
                ))
            }
        }

        guard !assets.isEmpty else {
            throw NativeDownloadError.noFiles
        }

        let cleanTitle = cleanTitle(username).sanitizedFilename(maxLength: 120)
        return ResolvedDownload(
            title: cleanTitle,
            folderName: cleanTitle,
            assets: assets,
            metadata: newgroundsMetadata(
                title: cleanTitle,
                artist: username,
                type: "artist",
                sourceURL: sourceURL,
                mediaCount: assets.count,
                postCount: postDownloads.count
            )
        )
    }

    static func mediaURLs(from html: String, pageURL: URL) -> [URL] {
        let normalizedHTML = normalizeEscapes(decodeHTML(html))
        var candidates = fullImageCandidates(from: normalizedHTML)
        candidates.append(contentsOf: GenericPageResolver.extractMetadataAssets(from: html, baseURL: pageURL).map { $0.remoteURL.absoluteString })

        var urls: [URL] = []
        var seen = Set<String>()
        for candidate in candidates {
            guard let remote = absoluteURL(candidate, baseURL: pageURL),
                  isDownloadableMedia(remote) else {
                continue
            }

            let normalized = URLIdentity.normalize(remote.absoluteString)
            guard !seen.contains(normalized) else { continue }
            seen.insert(normalized)
            urls.append(remote)
        }
        return urls
    }

    static func isLoginRequiredHTML(_ html: String) -> Bool {
        let lower = decodeHTML(html).lowercased()
        return lower.contains("you must be logged in, and at least 18 years of age to view this content!") ||
            (lower.contains("must be logged in") && lower.contains("18 years of age"))
    }

    static func artPostURLs(fromHTML html: String, baseURL: URL) -> [URL] {
        let normalizedHTML = normalizeEscapes(decodeHTML(html))
        let patterns = [
            #"<a\b[^>]*\bhref\s*=\s*["']([^"']*/art/view/[^"']+)["']"#,
            #""(?:href|url)"\s*:\s*"([^"]*/art/view/[^"]+)""#,
            #"(https?://[^\s"'<>\\]+/art/view/[^\s"'<>\\]+)"#
        ]

        var urls: [URL] = []
        var seen = Set<String>()
        for pattern in patterns {
            for raw in captureGroupMatches(pattern: pattern, in: normalizedHTML) {
                guard let remote = normalizedArtPageURL(raw, baseURL: baseURL) else { continue }
                let normalized = URLIdentity.normalize(remote.absoluteString)
                guard !seen.contains(normalized) else { continue }
                seen.insert(normalized)
                urls.append(remote)
            }
        }
        return urls
    }

    static func artistUsername(from url: URL) -> String? {
        guard let host = url.host?.lowercased(),
              isNewgroundsHost(host) else {
            return nil
        }

        let parts = url.path.split(separator: "/", omittingEmptySubsequences: true)
            .map { String($0).removingPercentEncoding ?? String($0) }
        if parts.count >= 3,
           parts[0].lowercased() == "art",
           parts[1].lowercased() == "view",
           let username = normalizedArtistUsername(parts[2]) {
            return username
        }

        guard !isArtViewURL(url) else {
            return nil
        }

        guard host.hasSuffix(".newgrounds.com") || host.hasSuffix(".newgrounds.test"),
              let subdomain = host.split(separator: ".").first.map(String.init),
              let username = normalizedArtistUsername(subdomain) else {
            return nil
        }

        let path = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/")).lowercased()
        guard path.isEmpty || path == "art" else {
            return nil
        }
        return username
    }

    static func canonicalArtistArtURL(for url: URL) -> URL? {
        guard let host = url.host?.lowercased(),
              isNewgroundsHost(host) else {
            return nil
        }

        if (host.hasSuffix(".newgrounds.com") || host.hasSuffix(".newgrounds.test")),
           let subdomain = host.split(separator: ".").first.map(String.init),
           let username = normalizedArtistUsername(subdomain) {
            return artistArtURL(username: username, sourceURL: url)
        }

        let parts = url.path.split(separator: "/", omittingEmptySubsequences: true)
            .map { String($0).removingPercentEncoding ?? String($0) }
        if parts.count >= 3,
           parts[0].lowercased() == "art",
           parts[1].lowercased() == "view",
           let username = normalizedArtistUsername(parts[2]) {
            return artistArtURL(username: username, sourceURL: url)
        }

        return nil
    }

    static func canonicalArtViewURL(for url: URL) -> URL? {
        guard let host = url.host?.lowercased(),
              isNewgroundsHost(host),
              isArtViewURL(url),
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return nil
        }
        components.queryItems = nil
        components.fragment = nil
        return components.url
    }

    static func artistArtURL(username: String, sourceURL: URL) -> URL {
        var components = URLComponents()
        components.scheme = sourceURL.scheme ?? "https"
        let host = sourceURL.host?.lowercased() ?? ""
        components.host = "\(username).\(host.hasSuffix(".newgrounds.test") || host == "newgrounds.test" ? "newgrounds.test" : "newgrounds.com")"
        components.path = "/art"
        return components.url!
    }

    static func artistArtPageURL(baseURL: URL, page: Int) -> URL {
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "page", value: String(max(1, page))),
            URLQueryItem(name: "isAjaxRequest", value: "1")
        ]
        return components.url ?? baseURL
    }

    private static func fullImageCandidates(from html: String) -> [String] {
        var candidates: [String] = []
        let patterns = [
            #""full_image_text"\s*:\s*"<img\b[^>]*\bsrc\s*=\s*["']([^"']+)["']"#,
            #"<a\b[^>]*\bhref\s*=\s*["']([^"']+)["'][^>]*>\s*<img\b[^>]*\bclass\s*=\s*["'][^"']*image[^"']*["']"#,
            #"<img\b[^>]*\b(?:data-smartload-src|data-large-url|data-fullsize-src)\s*=\s*["']([^"']+)["']"#
        ]

        for pattern in patterns {
            candidates.append(contentsOf: captureGroupMatches(pattern: pattern, in: html))
        }
        return candidates
    }

    private static func artistListTitle(fromHTML html: String, username: String) -> String {
        let title = metaContent(from: html, names: ["og:title", "twitter:title"]) ??
            titleTag(from: html) ??
            "\(username) Art"
        return cleanTitle(title)
    }

    private static func title(from html: String, pageURL: URL) -> String {
        let normalizedHTML = normalizeEscapes(decodeHTML(html))
        let title = fullImageAlt(from: normalizedHTML) ??
            metaContent(from: html, names: ["og:title", "twitter:title"]) ??
            titleTag(from: html) ??
            pageURL.deletingPathExtension().lastPathComponent.replacingOccurrences(of: "-", with: " ")
        return cleanTitle(title)
    }

    private static func fullImageAlt(from html: String) -> String? {
        let patterns = [
            #""full_image_text"\s*:\s*"<img\b[^>]*\balt\s*=\s*["']([^"']+)["']"#,
            #"<img\b[^>]*\balt\s*=\s*["']([^"']+)["'][^>]*\b(?:data-smartload-src|data-large-url|data-fullsize-src)\s*="#
        ]

        for pattern in patterns {
            if let value = captureGroupMatches(pattern: pattern, in: html).first?.trimmed, !value.isEmpty {
                return value
            }
        }
        return nil
    }

    private static func artistName(from html: String, pageURL: URL) -> String? {
        if let author = metaContent(from: html, names: ["author", "article:author"])?.trimmed, !author.isEmpty {
            return author
        }

        let parts = pageURL.path.split(separator: "/").map(String.init)
        if parts.count >= 4, parts[0].lowercased() == "art", parts[1].lowercased() == "view" {
            return parts[2]
        }

        if let host = pageURL.host?.lowercased(),
           host.hasSuffix(".newgrounds.com"),
           let subdomain = host.split(separator: ".").first.map(String.init),
           !["www", "newgrounds"].contains(subdomain) {
            return subdomain
        }

        return nil
    }

    private static func publishedDate(from html: String) -> String? {
        guard let raw = metaContent(from: html, names: ["datepublished", "article:published_time", "pubdate"]) else {
            return nil
        }

        let normalized = raw.trimmed
        if normalized.count >= 10 {
            let prefix = String(normalized.prefix(10))
            if prefix.range(of: #"^[0-9]{4}-[0-9]{2}-[0-9]{2}$"#, options: .regularExpression) != nil {
                return prefix
            }
        }
        return normalized.isEmpty ? nil : normalized.sanitizedFilename(maxLength: 24)
    }

    private static func filename(for url: URL, title: String, date: String?, index: Int) -> String {
        let ext = url.pathExtension.trimmed.isEmpty ? "jpg" : url.pathExtension
        let prefix = date.map { "[\($0)] " } ?? ""
        let suffix = index == 1 ? "" : "-\(index)"
        return "\(prefix)\(title)\(suffix).\(ext)".sanitizedFilename(maxLength: 180)
    }

    private static func metaContent(from html: String, names: Set<String>) -> String? {
        guard let regex = try? NSRegularExpression(pattern: #"<meta\b([^>]*)>"#, options: [.caseInsensitive, .dotMatchesLineSeparators]) else {
            return nil
        }

        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        for match in regex.matches(in: html, range: range) {
            guard let attributesRange = Range(match.range(at: 1), in: html) else { continue }
            let values = attributeValues(from: String(html[attributesRange]))
            let key = (values["property"] ?? values["name"] ?? values["itemprop"])?.lowercased()
            guard let key, names.contains(key),
                  let content = values["content"]?.trimmed,
                  !content.isEmpty else {
                continue
            }
            return content
        }

        return nil
    }

    private static func titleTag(from html: String) -> String? {
        guard let regex = try? NSRegularExpression(
            pattern: #"<title\b[^>]*>(.*?)</title>"#,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        ) else {
            return nil
        }

        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        guard let match = regex.firstMatch(in: html, range: range),
              let titleRange = Range(match.range(at: 1), in: html) else {
            return nil
        }

        return stripTags(String(html[titleRange])).trimmed
    }

    private static func cleanTitle(_ raw: String) -> String {
        var title = decodeHTML(stripTags(raw))
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmed

        for suffix in [" on Newgrounds", " - Newgrounds.com", " Newgrounds"] {
            if title.lowercased().hasSuffix(suffix.lowercased()) {
                title.removeLast(suffix.count)
                title = title.trimmed
            }
        }
        return title.isEmpty ? "Newgrounds Art" : title
    }

    private static func captureGroupMatches(pattern: String, in text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else {
            return []
        }

        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.matches(in: text, range: range).compactMap { match in
            guard match.numberOfRanges > 1,
                  let capture = Range(match.range(at: 1), in: text) else {
                return nil
            }
            return String(text[capture])
        }
    }

    private static func attributeValues(from attributes: String) -> [String: String] {
        guard let regex = try? NSRegularExpression(
            pattern: #"\b([A-Za-z_:][-A-Za-z0-9_:.]*)\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s>"']+))"#,
            options: [.caseInsensitive]
        ) else {
            return [:]
        }

        let range = NSRange(attributes.startIndex..<attributes.endIndex, in: attributes)
        var values: [String: String] = [:]

        for match in regex.matches(in: attributes, range: range) {
            guard let nameRange = Range(match.range(at: 1), in: attributes) else { continue }
            let name = String(attributes[nameRange]).lowercased()

            for group in 2...4 {
                guard let valueRange = Range(match.range(at: group), in: attributes) else { continue }
                values[name] = decodeHTML(String(attributes[valueRange])).trimmed
                break
            }
        }
        return values
    }

    private static func absoluteURL(_ raw: String, baseURL: URL) -> URL? {
        let value = raw.trimmed.trimmingCharacters(in: CharacterSet(charactersIn: "\"'(),;"))
        guard !value.isEmpty else { return nil }

        if value.hasPrefix("//") {
            return URL(string: "\(baseURL.scheme ?? "https"):\(value)")
        }
        return URL(string: value, relativeTo: baseURL)?.absoluteURL
    }

    private static func isDownloadableMedia(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
            return false
        }
        return mediaExtensions.contains(url.pathExtension.lowercased())
    }

    private static func isArtViewURL(_ url: URL) -> Bool {
        url.path.lowercased().contains("/art/view/")
    }

    private static func normalizedArtistUsername(_ raw: String) -> String? {
        let username = raw.trimmed.trimmingCharacters(in: CharacterSet(charactersIn: "@/ "))
        guard !username.isEmpty,
              !["www", "newgrounds"].contains(username.lowercased()),
              username.range(of: #"^[A-Za-z0-9_-]+$"#, options: .regularExpression) != nil else {
            return nil
        }
        return username
    }

    private static func isNewgroundsHost(_ host: String) -> Bool {
        host == "newgrounds.com" ||
            host == "www.newgrounds.com" ||
            host.hasSuffix(".newgrounds.com") ||
            host == "newgrounds.test" ||
            host.hasSuffix(".newgrounds.test")
    }

    private static func normalizeEscapes(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\\/", with: "/")
            .replacingOccurrences(of: "\\\"", with: "\"")
            .replacingOccurrences(of: "\\u002F", with: "/", options: .caseInsensitive)
            .replacingOccurrences(of: "\\u003A", with: ":", options: .caseInsensitive)
            .replacingOccurrences(of: "\\u0026", with: "&", options: .caseInsensitive)
    }

    private static func normalizedArtPageURL(_ raw: String, baseURL: URL) -> URL? {
        guard let remote = absoluteURL(raw, baseURL: baseURL),
              isNewgroundsHost(remote.host?.lowercased() ?? ""),
              isArtViewURL(remote) else {
            return nil
        }
        var components = URLComponents(url: remote, resolvingAgainstBaseURL: false)
        components?.query = nil
        components?.fragment = nil
        return components?.url ?? remote
    }

    private static func stripTags(_ text: String) -> String {
        text.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
    }

    private static func decodeHTML(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&apos;", with: "'")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
    }

    private static let mediaExtensions: Set<String> = [
        "jpg", "jpeg", "png", "gif", "webp", "avif", "bmp",
        "mp4", "m4v", "mov", "webm"
    ]
}

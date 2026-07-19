import Foundation

struct FourChanThreadRequest {
    var apiURL: URL
    var board: String
    var threadID: String
}

final class FourChanResolver {
    func canResolve(_ url: URL) -> Bool {
        Self.threadInfo(from: Self.fragmentStrippedURL(url)) != nil
    }

    func resolve(_ url: URL, headers: HTTPRequestOptions = HTTPRequestOptions()) async throws -> ResolvedDownload {
        let sourceURL = Self.fragmentStrippedURL(url)
        let request = try apiRequest(for: sourceURL)
        do {
            let data = try await HTTPClient.shared.data(from: request.apiURL, referer: headers.referer ?? sourceURL.absoluteString, userAgent: headers.userAgent)
            return try Self.resolvedDownload(from: data, board: request.board, threadID: request.threadID, sourceURL: sourceURL)
        } catch {
            let pageURL = Self.threadPageURL(board: request.board, threadID: request.threadID, sourceURL: sourceURL)
            let html = try await HTTPClient.shared.string(from: pageURL, referer: headers.referer ?? sourceURL.absoluteString, userAgent: headers.userAgent)
            return try Self.resolvedDownload(fromHTML: html, pageURL: pageURL)
        }
    }

    func apiRequest(for url: URL) throws -> FourChanThreadRequest {
        let sourceURL = Self.fragmentStrippedURL(url)
        guard let info = Self.threadInfo(from: sourceURL) else {
            throw NativeDownloadError.invalidURL(url.absoluteString)
        }

        if Self.isAPIHost(sourceURL.host), sourceURL.path.hasSuffix(".json") {
            return FourChanThreadRequest(apiURL: sourceURL, board: info.board, threadID: info.threadID)
        }

        guard var components = URLComponents(url: sourceURL, resolvingAgainstBaseURL: false) else {
            throw NativeDownloadError.invalidURL(url.absoluteString)
        }
        components.host = Self.apiHost(for: sourceURL.host)
        components.path = "/\(info.board)/thread/\(info.threadID).json"
        components.queryItems = nil
        components.fragment = nil
        guard let apiURL = components.url else {
            throw NativeDownloadError.invalidURL(url.absoluteString)
        }
        return FourChanThreadRequest(apiURL: apiURL, board: info.board, threadID: info.threadID)
    }

    static func resolvedDownload(from data: Data, board: String, threadID: String, sourceURL: URL) throws -> ResolvedDownload {
        let cleanSourceURL = fragmentStrippedURL(sourceURL)
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let posts = object["posts"] as? [[String: Any]] else {
            throw NativeDownloadError.invalidGalleryData
        }

        let pageURL = threadPageURL(board: board, threadID: threadID, sourceURL: cleanSourceURL)
        let title = title(from: posts.first, board: board, threadID: threadID)
        var assets: [ResolvedAsset] = []
        var seen = Set<String>()

        for post in posts {
            guard let tim = stringValue(post["tim"]),
                  let ext = stringValue(post["ext"]),
                  !tim.isEmpty,
                  !ext.isEmpty,
                  let remote = mediaURL(board: board, tim: tim, ext: ext, sourceURL: cleanSourceURL) else {
                continue
            }

            let normalized = URLIdentity.normalize(remote.absoluteString)
            guard !seen.contains(normalized) else { continue }
            seen.insert(normalized)

            let filename = outputFilename(post: post, remoteURL: remote, index: assets.count + 1)
            assets.append(ResolvedAsset(
                remoteURL: remote,
                filename: filename,
                metadata: assetMetadata(
                    post: post,
                    remoteURL: remote,
                    board: board,
                    threadID: threadID,
                    title: title,
                    pageURL: pageURL,
                    index: assets.count + 1
                ),
                referer: pageURL.absoluteString
            ))
        }

        guard !assets.isEmpty else {
            throw NativeDownloadError.noFiles
        }

        return ResolvedDownload(
            title: title,
            folderName: title,
            assets: assets,
            metadata: threadMetadata(posts: posts, board: board, threadID: threadID, title: title, pageURL: pageURL, assets: assets)
        )
    }

    static func resolvedDownload(fromHTML html: String, pageURL: URL) throws -> ResolvedDownload {
        let cleanPageURL = fragmentStrippedURL(pageURL)
        guard let info = threadInfo(from: cleanPageURL) else {
            throw NativeDownloadError.invalidURL(pageURL.absoluteString)
        }

        let canonicalPageURL = threadPageURL(board: info.board, threadID: info.threadID, sourceURL: cleanPageURL)
        let title = title(fromHTML: html, board: info.board, threadID: info.threadID)
        let media = fileTextMediaURLs(fromHTML: html, baseURL: canonicalPageURL)
        guard !media.isEmpty else {
            throw NativeDownloadError.noFiles
        }

        let assets = media.enumerated().map { offset, remote in
            ResolvedAsset(
                remoteURL: remote,
                filename: htmlOutputFilename(for: remote, index: offset + 1),
                metadata: htmlAssetMetadata(
                    remoteURL: remote,
                    board: info.board,
                    threadID: info.threadID,
                    title: title,
                    pageURL: canonicalPageURL,
                    index: offset + 1
                ),
                referer: canonicalPageURL.absoluteString
            )
        }

        return ResolvedDownload(
            title: title,
            folderName: title,
            assets: assets,
            metadata: htmlThreadMetadata(board: info.board, threadID: info.threadID, title: title, pageURL: canonicalPageURL, assets: assets)
        )
    }

    static func canonicalURL(for url: URL) -> URL? {
        let sourceURL = fragmentStrippedURL(url)
        guard threadInfo(from: sourceURL) != nil else {
            return nil
        }
        return sourceURL
    }

    private static func threadInfo(from url: URL) -> (board: String, threadID: String)? {
        guard let host = url.host?.lowercased(),
              isThreadHost(host) || isAPIHost(host) else {
            return nil
        }

        let parts = url.path.split(separator: "/").map(String.init)
        guard parts.count >= 3,
              parts[1].lowercased() == "thread" else {
            return nil
        }

        let board = parts[0].trimmed
        let thread = (parts[2] as NSString).deletingPathExtension.trimmed
        guard !board.isEmpty, !thread.isEmpty, thread.allSatisfy(\.isNumber) else {
            return nil
        }
        return (board, thread)
    }

    private static func fragmentStrippedURL(_ url: URL) -> URL {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url
        }
        components.fragment = nil
        return components.url ?? url
    }

    private static func isThreadHost(_ host: String?) -> Bool {
        guard let host = host?.lowercased() else { return false }
        return host == "boards.4chan.org" ||
            host == "boards.4channel.org" ||
            host == "4chan.org" ||
            host == "www.4chan.org" ||
            host == "4channel.org" ||
            host == "www.4channel.org" ||
            host == "boards.4chan.test" ||
            host == "boards.4channel.test"
    }

    private static func isAPIHost(_ host: String?) -> Bool {
        guard let host = host?.lowercased() else { return false }
        return host == "a.4cdn.org" || host == "a.4cdn.test"
    }

    private static func apiHost(for host: String?) -> String {
        guard let host = host?.lowercased(), host.hasSuffix(".test") else {
            return "a.4cdn.org"
        }
        return "a.4cdn.test"
    }

    private static func mediaURL(board: String, tim: String, ext: String, sourceURL: URL) -> URL? {
        let host = (sourceURL.host?.lowercased().hasSuffix(".test") ?? false) ? "i.4cdn.test" : "i.4cdn.org"
        let normalizedExt = ext.hasPrefix(".") ? ext : ".\(ext)"
        return URL(string: "\(sourceURL.scheme ?? "https")://\(host)/\(board)/\(tim)\(normalizedExt)")
    }

    private static func threadPageURL(board: String, threadID: String, sourceURL: URL) -> URL {
        let cleanSourceURL = fragmentStrippedURL(sourceURL)
        guard let host = cleanSourceURL.host?.lowercased(),
              host == "a.4cdn.org" || host == "a.4cdn.test" else {
            return cleanSourceURL
        }

        let pageHost = host.hasSuffix(".test") ? "boards.4chan.test" : "boards.4chan.org"
        return URL(string: "\(cleanSourceURL.scheme ?? "https")://\(pageHost)/\(board)/thread/\(threadID)") ?? cleanSourceURL
    }

    private static func outputFilename(post: [String: Any], remoteURL: URL, index: Int) -> String {
        let ext = remoteURL.pathExtension.isEmpty ? "bin" : remoteURL.pathExtension
        return String(format: "%04d.%@", max(0, index - 1), ext).sanitizedFilename(maxLength: 180)
    }

    private static func htmlOutputFilename(for url: URL, index: Int) -> String {
        let ext = mediaFormat(for: url).isEmpty ? "bin" : mediaFormat(for: url)
        return String(format: "%04d.%@", max(0, index - 1), ext).sanitizedFilename(maxLength: 180)
    }

    private static func title(from firstPost: [String: Any]?, board: String, threadID: String) -> String {
        let raw = stringValue(firstPost?["sub"]) ??
            stringValue(firstPost?["semantic_url"]) ??
            stringValue(firstPost?["com"]) ??
            "Thread \(threadID)"
        return originalStyleTitle(subject: raw, board: board, threadID: threadID)
    }

    private static func title(fromHTML html: String, board: String, threadID: String) -> String {
        let raw = elementText(pattern: #"<span\b[^>]*\bclass\s*=\s*["'][^"']*subject[^"']*["'][^>]*>(.*?)</span>"#, in: html) ??
            elementText(pattern: #"<title\b[^>]*>(.*?)</title>"#, in: html) ??
            "Thread \(threadID)"
        return originalStyleTitle(subject: raw, board: board, threadID: threadID)
    }

    private static func originalStyleTitle(subject raw: String, board: String, threadID: String) -> String {
        let subject = decodeHTML(stripTags(raw))
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmed
        let fallback = "Thread \(threadID)"
        let cleanSubject = subject.isEmpty ? fallback : subject
        return "[\(board)] \(cleanSubject) (\(threadID))".sanitizedFilename(maxLength: 120)
    }

    private static func threadMetadata(posts: [[String: Any]], board: String, threadID: String, title: String, pageURL: URL, assets: [ResolvedAsset]) -> [String: String] {
        let firstPost = posts.first
        let poster = stringValue(firstPost?["name"]) ?? ""
        let posterID = stringValue(firstPost?["id"]) ?? ""
        let semantic = stringValue(firstPost?["semantic_url"]) ?? ""
        let imageCount = assets.filter { mediaType(for: $0.remoteURL) == "image" }.count
        let videoCount = assets.filter { mediaType(for: $0.remoteURL) == "video" }.count
        return DownloadMetadata.clean([
            "artist": poster,
            "author": poster,
            "creator": poster,
            "uploader": poster,
            "channel": board,
            "username": poster,
            "user_id": posterID,
            "category": board,
            "board": board,
            "board_id": board,
            "thread_id": threadID,
            "post_id": threadID,
            "series": title,
            "tag": semantic,
            "slug": semantic.isEmpty ? threadID : semantic,
            "site": "4chan",
            "title": title,
            "post_count": String(posts.count),
            "media_count": String(assets.count),
            "image_count": imageCount > 0 ? String(imageCount) : "",
            "video_count": videoCount > 0 ? String(videoCount) : "",
            "url": pageURL.absoluteString,
            "source_url": pageURL.absoluteString,
            "page_url": pageURL.absoluteString
        ])
    }

    private static func htmlThreadMetadata(board: String, threadID: String, title: String, pageURL: URL, assets: [ResolvedAsset]) -> [String: String] {
        let imageCount = assets.filter { mediaType(for: $0.remoteURL) == "image" }.count
        let videoCount = assets.filter { mediaType(for: $0.remoteURL) == "video" }.count
        return DownloadMetadata.clean([
            "channel": board,
            "category": board,
            "board": board,
            "board_id": board,
            "thread_id": threadID,
            "post_id": threadID,
            "series": title,
            "slug": threadID,
            "site": "4chan",
            "title": title,
            "media_count": String(assets.count),
            "image_count": imageCount > 0 ? String(imageCount) : "",
            "video_count": videoCount > 0 ? String(videoCount) : "",
            "url": pageURL.absoluteString,
            "source_url": pageURL.absoluteString,
            "page_url": pageURL.absoluteString
        ])
    }

    private static func assetMetadata(post: [String: Any], remoteURL: URL, board: String, threadID: String, title: String, pageURL: URL, index: Int) -> [String: String] {
        let poster = stringValue(post["name"]) ?? ""
        let posterID = stringValue(post["id"]) ?? ""
        let postID = stringValue(post["no"]) ?? ""
        let mediaID = stringValue(post["tim"]) ?? postID
        let semantic = stringValue(post["semantic_url"]) ?? ""
        let format = mediaFormat(for: remoteURL)
        let type = mediaType(for: remoteURL)
        return DownloadMetadata.clean([
            "site": "4chan",
            "title": title,
            "series": title,
            "type": type,
            "media_type": type,
            "category": board,
            "board": board,
            "board_id": board,
            "thread_id": threadID,
            "id": postID.isEmpty ? mediaID : postID,
            "post_id": postID,
            "media_id": mediaID,
            "page": String(index),
            "position": String(index),
            "slug": semantic.isEmpty ? (postID.isEmpty ? mediaID : postID) : semantic,
            "tag": semantic,
            "format": format,
            "media_format": format,
            "artist": poster,
            "author": poster,
            "creator": poster,
            "uploader": poster,
            "username": poster,
            "user_id": posterID,
            "channel": board,
            "image_url": type == "image" ? remoteURL.absoluteString : "",
            "video_url": type == "video" ? remoteURL.absoluteString : "",
            "media_url": remoteURL.absoluteString,
            "source_url": remoteURL.absoluteString,
            "page_url": pageURL.absoluteString
        ])
    }

    private static func htmlAssetMetadata(remoteURL: URL, board: String, threadID: String, title: String, pageURL: URL, index: Int) -> [String: String] {
        let mediaID = (remoteURL.deletingPathExtension().lastPathComponent.trimmed.isEmpty ? String(index) : remoteURL.deletingPathExtension().lastPathComponent)
        let format = mediaFormat(for: remoteURL)
        let type = mediaType(for: remoteURL)
        return DownloadMetadata.clean([
            "site": "4chan",
            "title": title,
            "series": title,
            "type": type,
            "media_type": type,
            "category": board,
            "board": board,
            "board_id": board,
            "thread_id": threadID,
            "id": mediaID,
            "media_id": mediaID,
            "page": String(index),
            "position": String(index),
            "slug": mediaID,
            "format": format,
            "media_format": format,
            "channel": board,
            "image_url": type == "image" ? remoteURL.absoluteString : "",
            "video_url": type == "video" ? remoteURL.absoluteString : "",
            "media_url": remoteURL.absoluteString,
            "source_url": remoteURL.absoluteString,
            "page_url": pageURL.absoluteString
        ])
    }

    private static func fileTextMediaURLs(fromHTML html: String, baseURL: URL) -> [URL] {
        var results: [URL] = []
        var seen = Set<String>()
        for block in captureGroupMatches(pattern: #"<div\b[^>]*\bclass\s*=\s*["'][^"']*fileText[^"']*["'][^>]*>(.*?)</div>"#, in: html) {
            for href in anchorHREFs(fromHTML: block) {
                guard let remote = absoluteURL(href, baseURL: baseURL),
                      !mediaFormat(for: remote).isEmpty else {
                    continue
                }
                let normalized = URLIdentity.normalize(remote.absoluteString)
                guard !seen.contains(normalized) else { continue }
                seen.insert(normalized)
                results.append(remote)
            }
        }
        return results
    }

    private static func anchorHREFs(fromHTML html: String) -> [String] {
        guard let regex = try? NSRegularExpression(
            pattern: #"<a\b([^>]*)>"#,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        ) else {
            return []
        }
        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        return regex.matches(in: html, range: range).compactMap { match in
            guard let attrsRange = Range(match.range(at: 1), in: html) else { return nil }
            return attributeValues(from: String(html[attrsRange]))["href"]
        }
    }

    private static func attributeValues(from raw: String) -> [String: String] {
        var values: [String: String] = [:]
        guard let regex = try? NSRegularExpression(
            pattern: #"([A-Za-z_:][-A-Za-z0-9_:.]*)\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s"'=<>`]+))"#,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        ) else {
            return values
        }
        let range = NSRange(raw.startIndex..<raw.endIndex, in: raw)
        for match in regex.matches(in: raw, range: range) {
            guard let keyRange = Range(match.range(at: 1), in: raw) else { continue }
            let key = String(raw[keyRange]).lowercased()
            let value: String
            if let range = Range(match.range(at: 2), in: raw) {
                value = String(raw[range])
            } else if let range = Range(match.range(at: 3), in: raw) {
                value = String(raw[range])
            } else if let range = Range(match.range(at: 4), in: raw) {
                value = String(raw[range])
            } else {
                value = ""
            }
            values[key] = decodeHTML(value)
        }
        return values
    }

    private static func absoluteURL(_ raw: String, baseURL: URL) -> URL? {
        var value = decodeHTML(raw).trimmed
        guard !value.isEmpty,
              !value.lowercased().hasPrefix("javascript:"),
              !value.lowercased().hasPrefix("mailto:") else {
            return nil
        }
        if value.hasPrefix("//") {
            value = "\(baseURL.scheme ?? "https"):\(value)"
        }
        guard let url = URL(string: value, relativeTo: baseURL)?.absoluteURL,
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            return nil
        }
        return url
    }

    private static func elementText(pattern: String, in html: String) -> String? {
        captureGroupMatches(pattern: pattern, in: html).first
    }

    private static func captureGroupMatches(pattern: String, in text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else {
            return []
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.matches(in: text, range: range).compactMap { match in
            guard match.numberOfRanges > 1,
                  let resultRange = Range(match.range(at: 1), in: text) else {
                return nil
            }
            return String(text[resultRange])
        }
    }

    private static func mediaFormat(for url: URL) -> String {
        let pathExtension = url.pathExtension.lowercased()
        if !pathExtension.isEmpty {
            return pathExtension
        }
        let lower = url.absoluteString.lowercased()
        if lower.contains(".webm") { return "webm" }
        if lower.contains(".mp4") { return "mp4" }
        if lower.contains(".gif") { return "gif" }
        if lower.contains(".png") { return "png" }
        if lower.contains(".jpg") || lower.contains(".jpeg") { return "jpg" }
        return ""
    }

    private static func mediaType(for url: URL) -> String {
        switch mediaFormat(for: url) {
        case "webm", "mp4", "m4v", "mov":
            return "video"
        default:
            return "image"
        }
    }

    private static func stripTags(_ text: String) -> String {
        text.replacingOccurrences(of: "<br\\s*/?>", with: " ", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
    }

    private static func decodeHTML(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&apos;", with: "'")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&#44;", with: ",")
    }

    private static func stringValue(_ value: Any?) -> String? {
        if let string = value as? String { return string }
        if let int = value as? Int { return String(int) }
        if let int64 = value as? Int64 { return String(int64) }
        if let number = value as? NSNumber { return number.stringValue }
        return nil
    }
}

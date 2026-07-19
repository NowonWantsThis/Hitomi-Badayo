import Foundation

final class GenericPageResolver {
    func canResolve(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
            return false
        }

        let ext = url.pathExtension.lowercased()
        if ext.isEmpty { return true }
        return ["html", "htm", "php", "asp", "aspx"].contains(ext)
    }

    func resolveIfPossible(_ url: URL, headers: HTTPRequestOptions = HTTPRequestOptions()) async throws -> ResolvedDownload? {
        guard canResolve(url) else { return nil }
        let html = try await HTTPClient.shared.string(from: url, referer: headers.referer, userAgent: headers.userAgent)
        return Self.resolvedDownload(fromHTML: html, pageURL: url)
    }

    static func resolvedDownload(fromHTML html: String, pageURL: URL) -> ResolvedDownload? {
        let assets = extractPageAssets(from: html, baseURL: pageURL)
        guard !assets.isEmpty else { return nil }

        let title = extractTitle(from: html) ?? title(from: pageURL)
        return ResolvedDownload(
            title: title,
            folderName: title.sanitizedFilename(maxLength: 120),
            assets: assets,
            metadata: pageMetadata(title: title, html: html, baseURL: pageURL, assets: assets)
        )
    }

    static func extractPageAssets(from html: String, baseURL: URL, limit: Int = 200) -> [ResolvedAsset] {
        var assets: [ResolvedAsset] = []
        var seen = Set<String>()
        let pageIdentity = URLIdentity.normalize(baseURL.absoluteString)

        for asset in extractMetadataAssets(from: html, baseURL: baseURL, limit: limit) + extractAssets(from: html, baseURL: baseURL, limit: limit) {
            guard assets.count < limit else { break }
            let normalized = URLIdentity.normalize(asset.remoteURL.absoluteString)
            guard normalized != pageIdentity, !seen.contains(normalized) else { continue }
            seen.insert(normalized)
            let index = assets.count + 1
            assets.append(ResolvedAsset(
                remoteURL: asset.remoteURL,
                filename: filename(for: asset.remoteURL, index: index),
                metadata: assetMetadata(for: asset.remoteURL, pageURL: baseURL, index: index),
                referer: asset.referer,
                userAgent: asset.userAgent,
                decryption: asset.decryption
            ))
        }

        return assets
    }

    static func extractMetadataAssets(from html: String, baseURL: URL, limit: Int = 100) -> [ResolvedAsset] {
        let candidates = metadataURLCandidates(from: html)
        var assets: [ResolvedAsset] = []
        var seen = Set<String>()

        for candidate in candidates {
            guard assets.count < limit,
                  let remote = resolve(candidate, baseURL: baseURL),
                  shouldDownloadMetadata(remote) else {
                continue
            }

            let normalized = URLIdentity.normalize(remote.absoluteString)
            guard normalized != URLIdentity.normalize(baseURL.absoluteString), !seen.contains(normalized) else {
                continue
            }

            seen.insert(normalized)
            let index = assets.count + 1
            assets.append(ResolvedAsset(
                remoteURL: remote,
                filename: filename(for: remote, index: index),
                metadata: assetMetadata(for: remote, pageURL: baseURL, index: index),
                referer: baseURL.absoluteString
            ))
        }

        return assets
    }

    static func extractAssets(from html: String, baseURL: URL, limit: Int = 200) -> [ResolvedAsset] {
        guard let tagRegex = try? NSRegularExpression(
            pattern: #"<(img|video|audio|source|picture|a|div|span|figure|section)\b([^>]*)>"#,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        ) else {
            return []
        }

        var assets: [ResolvedAsset] = []
        var seen = Set<String>()
        let range = NSRange(html.startIndex..<html.endIndex, in: html)

        for match in tagRegex.matches(in: html, range: range) {
            guard assets.count < limit,
                  let tagRange = Range(match.range(at: 1), in: html),
                  let attributesRange = Range(match.range(at: 2), in: html) else {
                continue
            }

            let tagName = String(html[tagRange]).lowercased()
            let attributes = String(html[attributesRange])
            let candidates = mediaCandidates(from: attributes, tagName: tagName)

            for candidate in candidates {
                guard assets.count < limit,
                      let remote = resolve(candidate, baseURL: baseURL),
                      shouldDownload(remote, tagName: tagName, rawCandidate: candidate) else {
                    continue
                }

                let normalized = URLIdentity.normalize(remote.absoluteString)
                guard normalized != URLIdentity.normalize(baseURL.absoluteString), !seen.contains(normalized) else {
                    continue
                }

                seen.insert(normalized)
                let index = assets.count + 1
                assets.append(ResolvedAsset(
                    remoteURL: remote,
                    filename: filename(for: remote, index: index),
                    metadata: assetMetadata(for: remote, pageURL: baseURL, index: index),
                    referer: baseURL.absoluteString
                ))
            }
        }

        return assets
    }

    private static func metadataURLCandidates(from html: String) -> [String] {
        var candidates: [String] = []
        candidates.append(contentsOf: metaURLCandidates(from: html))
        candidates.append(contentsOf: linkURLCandidates(from: html))
        candidates.append(contentsOf: jsonLDURLCandidates(from: html))
        return candidates
    }

    private static func metaURLCandidates(from html: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: #"<meta\b([^>]*)>"#, options: [.caseInsensitive, .dotMatchesLineSeparators]) else {
            return []
        }

        let names: Set<String> = [
            "og:image", "og:image:url", "og:image:secure_url",
            "og:video", "og:video:url", "og:video:secure_url",
            "og:audio", "og:audio:url", "og:audio:secure_url",
            "twitter:image", "twitter:image:src", "twitter:player:stream",
            "thumbnail", "thumbnailurl", "image"
        ]

        var candidates: [String] = []
        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        for match in regex.matches(in: html, range: range) {
            guard let attributesRange = Range(match.range(at: 1), in: html) else { continue }
            let values = attributeValues(from: String(html[attributesRange]))
            let name = (values["property"] ?? values["name"] ?? values["itemprop"])?.lowercased()
            guard let name, names.contains(name),
                  let content = values["content"]?.trimmed,
                  !content.isEmpty else {
                continue
            }
            candidates.append(content)
        }
        return candidates
    }

    private static func linkURLCandidates(from html: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: #"<link\b([^>]*)>"#, options: [.caseInsensitive, .dotMatchesLineSeparators]) else {
            return []
        }

        var candidates: [String] = []
        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        for match in regex.matches(in: html, range: range) {
            guard let attributesRange = Range(match.range(at: 1), in: html) else { continue }
            let values = attributeValues(from: String(html[attributesRange]))
            let rel = values["rel"]?.lowercased() ?? ""
            let asType = values["as"]?.lowercased() ?? ""
            let type = values["type"]?.lowercased() ?? ""
            let isMediaLink = rel.components(separatedBy: .whitespacesAndNewlines).contains("image_src") ||
                rel.components(separatedBy: .whitespacesAndNewlines).contains("preload") && ["image", "video", "audio"].contains(asType) ||
                type.hasPrefix("image/") || type.hasPrefix("video/") || type.hasPrefix("audio/")
            guard isMediaLink,
                  let href = values["href"]?.trimmed,
                  !href.isEmpty else {
                continue
            }
            candidates.append(href)
        }
        return candidates
    }

    private static func jsonLDURLCandidates(from html: String) -> [String] {
        guard let regex = try? NSRegularExpression(
            pattern: #"<script\b([^>]*)>(.*?)</script>"#,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        ) else {
            return []
        }

        var candidates: [String] = []
        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        for match in regex.matches(in: html, range: range) {
            guard let attributesRange = Range(match.range(at: 1), in: html),
                  let contentRange = Range(match.range(at: 2), in: html) else {
                continue
            }

            let values = attributeValues(from: String(html[attributesRange]))
            guard values["type"]?.lowercased().contains("ld+json") == true else {
                continue
            }

            let jsonText = decodeHTML(String(html[contentRange])).trimmed
            guard let data = jsonText.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) else {
                continue
            }
            collectJSONLDURLs(from: object, into: &candidates)
        }

        return candidates
    }

    private static func collectJSONLDURLs(from object: Any, into candidates: inout [String], forceMedia: Bool = false) {
        if let string = object as? String {
            if forceMedia || looksLikeMediaReference(string) {
                candidates.append(string)
            }
            return
        }

        if let array = object as? [Any] {
            for item in array {
                collectJSONLDURLs(from: item, into: &candidates, forceMedia: forceMedia)
            }
            return
        }

        guard let dictionary = object as? [String: Any] else {
            return
        }

        for (key, value) in dictionary {
            let lowerKey = key.lowercased()
            if ["contenturl", "thumbnailurl", "embedurl"].contains(lowerKey) {
                collectJSONLDURLs(from: value, into: &candidates, forceMedia: true)
            } else if ["image", "video", "audio", "thumbnail", "associatedmedia", "primaryimageofpage"].contains(lowerKey) {
                collectJSONLDURLs(from: value, into: &candidates, forceMedia: true)
            } else if lowerKey == "url" {
                if let string = value as? String, forceMedia || looksLikeMediaReference(string) {
                    candidates.append(string)
                } else if !(value is String) {
                    collectJSONLDURLs(from: value, into: &candidates, forceMedia: forceMedia || isMediaObject(dictionary))
                }
            } else if let nested = value as? [String: Any], isMediaObject(nested) {
                collectJSONLDURLs(from: nested, into: &candidates, forceMedia: true)
            } else if let array = value as? [Any] {
                for item in array {
                    if let nested = item as? [String: Any], isMediaObject(nested) {
                        collectJSONLDURLs(from: nested, into: &candidates, forceMedia: true)
                    }
                }
            }
        }
    }

    private static func mediaCandidates(from attributes: String, tagName: String) -> [String] {
        let values = attributeValues(from: attributes)
        var candidates: [String] = []

        let mediaAttributeNames: [String]
        if ["img", "video", "audio", "source", "picture"].contains(tagName) {
            mediaAttributeNames = [
                "src", "data-src", "data-original", "data-original-src", "data-lazy-src",
                "data-lazyload-src", "data-url", "data-image", "data-image-url",
                "data-full", "data-full-url", "data-hires", "data-highres",
                "data-full-src", "data-orig-file", "data-large-file",
                "data-file-url", "data-large-file-url", "data-download-url", "poster"
            ]
        } else {
            mediaAttributeNames = ["data-bg", "data-bg-src", "data-background", "data-background-image"]
        }

        for name in mediaAttributeNames {
            if let value = values[name] {
                candidates.append(value)
            }
        }

        if tagName == "a", let href = values["href"] {
            candidates.append(href)
        }

        if let srcset = values["srcset"],
           let best = bestSrcsetCandidate(srcset) {
            candidates.append(best)
        }

        for name in ["data-srcset", "data-lazy-srcset", "data-original-srcset"] {
            if let srcset = values[name],
               let best = bestSrcsetCandidate(srcset) {
                candidates.append(best)
            }
        }

        if let style = values["style"] {
            candidates.append(contentsOf: styleURLCandidates(from: style))
        }

        return candidates
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

    private static func bestSrcsetCandidate(_ srcset: String) -> String? {
        let entries = srcset.components(separatedBy: ",").compactMap { part -> (url: String, score: Int)? in
            let pieces = part.trimmed.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
            guard let url = pieces.first, !url.isEmpty else { return nil }
            let descriptor = pieces.dropFirst().first ?? ""
            if descriptor.hasSuffix("w") {
                return (url, Int(descriptor.dropLast()) ?? 0)
            }
            if descriptor.hasSuffix("x") {
                return (url, Int((Double(descriptor.dropLast()) ?? 1) * 10_000))
            }
            return (url, 0)
        }
        return entries.max { $0.score < $1.score }?.url
    }

    private static func styleURLCandidates(from style: String) -> [String] {
        guard let regex = try? NSRegularExpression(
            pattern: #"url\(\s*(?:"([^"]+)"|'([^']+)'|([^)]+?))\s*\)"#,
            options: [.caseInsensitive]
        ) else {
            return []
        }

        let range = NSRange(style.startIndex..<style.endIndex, in: style)
        return regex.matches(in: style, range: range).compactMap { match in
            for group in 1...3 {
                guard let valueRange = Range(match.range(at: group), in: style) else { continue }
                let candidate = String(style[valueRange]).trimmed
                return isMediaPath(candidate) ? candidate : nil
            }
            return nil
        }
    }

    private static func isMediaPath(_ value: String) -> Bool {
        let path = value.components(separatedBy: "?").first ?? value
        let ext = (path as NSString).pathExtension.lowercased()
        return metadataMediaExtensions.contains(ext)
    }

    private static func resolve(_ raw: String, baseURL: URL) -> URL? {
        let value = raw.trimmed
        guard !value.isEmpty,
              !value.hasPrefix("#"),
              !value.lowercased().hasPrefix("data:"),
              !value.lowercased().hasPrefix("blob:"),
              !value.lowercased().hasPrefix("javascript:"),
              !value.lowercased().hasPrefix("mailto:") else {
            return nil
        }
        return URL(string: value, relativeTo: baseURL)?.absoluteURL
    }

    private static func shouldDownload(_ url: URL, tagName: String, rawCandidate: String = "") -> Bool {
        guard let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" || scheme == "file" else {
            return false
        }

        if tagName != "a" {
            return true
        }

        return knownDownloadExtensions.contains(url.pathExtension.lowercased())
    }

    private static func shouldDownloadMetadata(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" || scheme == "file" else {
            return false
        }

        let ext = url.pathExtension.lowercased()
        if metadataMediaExtensions.contains(ext) {
            return true
        }
        if ["html", "htm", "php", "asp", "aspx"].contains(ext) {
            return false
        }
        return ext.isEmpty
    }

    private static func filename(for url: URL, index: Int) -> String {
        let rawName = url.lastPathComponent.removingPercentEncoding ?? url.lastPathComponent
        let cleanName = rawName.sanitizedFilename(maxLength: 160)
        if cleanName != "download", cleanName.contains(".") {
            return String(format: "%04d-%@", index, cleanName)
        }

        let ext = url.pathExtension.trimmed.isEmpty ? "bin" : url.pathExtension
        return String(format: "%04d-media.%@", index, ext)
    }

    private static func extractTitle(from html: String) -> String? {
        if let metaTitle = extractMetaTitle(from: html) {
            return metaTitle
        }

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

        let title = decodeHTML(stripTags(String(html[titleRange]))).sanitizedFilename(maxLength: 120)
        return title == "download" ? nil : title
    }

    private static func extractMetaTitle(from html: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: #"<meta\b([^>]*)>"#, options: [.caseInsensitive, .dotMatchesLineSeparators]) else {
            return nil
        }

        let names: Set<String> = ["og:title", "twitter:title", "title"]
        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        for match in regex.matches(in: html, range: range) {
            guard let attributesRange = Range(match.range(at: 1), in: html) else { continue }
            let values = attributeValues(from: String(html[attributesRange]))
            let name = (values["property"] ?? values["name"] ?? values["itemprop"])?.lowercased()
            guard let name, names.contains(name),
                  let content = values["content"]?.trimmed,
                  !content.isEmpty else {
                continue
            }
            let title = decodeHTML(stripTags(content)).sanitizedFilename(maxLength: 120)
            return title == "download" ? nil : title
        }

        return nil
    }

    static func pageMetadata(title: String, html: String, baseURL: URL, assets: [ResolvedAsset]) -> [String: String] {
        let host = baseURL.scheme?.lowercased() == "file" ? "local" : (baseURL.host ?? "")
        let slug = pageSlug(from: baseURL)
        let author = extractMetaContent(from: html, names: ["author", "article:author", "og:site_name"])
        let imageCount = assets.filter { mediaKind(for: $0.remoteURL) == "image" }.count
        let videoCount = assets.filter { mediaKind(for: $0.remoteURL) == "video" }.count
        let audioCount = assets.filter { mediaKind(for: $0.remoteURL) == "audio" }.count
        let archiveCount = assets.filter { mediaKind(for: $0.remoteURL) == "archive" }.count
        let documentCount = assets.filter { mediaKind(for: $0.remoteURL) == "document" }.count

        return DownloadMetadata.clean([
            "artist": author ?? "",
            "author": author ?? "",
            "creator": author ?? "",
            "uploader": author ?? "",
            "channel": host,
            "host": host,
            "site": host,
            "series": title,
            "category": "page",
            "type": "generic_page",
            "gallery_id": slug.isEmpty ? host : slug,
            "slug": slug,
            "media_count": String(assets.count),
            "image_count": String(imageCount),
            "video_count": String(videoCount),
            "audio_count": String(audioCount),
            "archive_count": String(archiveCount),
            "document_count": String(documentCount),
            "title": title,
            "url": baseURL.absoluteString,
            "source_url": baseURL.absoluteString,
            "page_url": baseURL.absoluteString
        ])
    }

    private static func assetMetadata(for url: URL, pageURL: URL, index: Int) -> [String: String] {
        let kind = mediaKind(for: url)
        let format = mediaFormat(for: url)
        return DownloadMetadata.clean([
            "type": kind,
            "media_type": kind,
            "page": String(index),
            "position": String(index),
            "format": format,
            "media_format": format,
            "media_url": url.absoluteString,
            "image_url": kind == "image" ? url.absoluteString : "",
            "video_url": kind == "video" ? url.absoluteString : "",
            "audio_url": kind == "audio" ? url.absoluteString : "",
            "source_url": url.absoluteString,
            "page_url": pageURL.absoluteString
        ])
    }

    private static func extractMetaContent(from html: String, names: Set<String>) -> String? {
        guard let regex = try? NSRegularExpression(pattern: #"<meta\b([^>]*)>"#, options: [.caseInsensitive, .dotMatchesLineSeparators]) else {
            return nil
        }

        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        for match in regex.matches(in: html, range: range) {
            guard let attributesRange = Range(match.range(at: 1), in: html) else { continue }
            let values = attributeValues(from: String(html[attributesRange]))
            let name = (values["property"] ?? values["name"] ?? values["itemprop"])?.lowercased()
            guard let name, names.contains(name),
                  let content = values["content"]?.trimmed,
                  !content.isEmpty else {
                continue
            }
            return decodeHTML(stripTags(content)).sanitizedFilename(maxLength: 120)
        }
        return nil
    }

    private static func mediaKind(for url: URL) -> String {
        let ext = url.pathExtension.lowercased()
        if ["jpg", "jpeg", "png", "gif", "webp", "avif", "bmp", "svg"].contains(ext) {
            return "image"
        }
        if ["mp4", "m4v", "mov", "webm", "mkv", "avi"].contains(ext) {
            return "video"
        }
        if ["mp3", "m4a", "aac", "flac", "wav", "ogg"].contains(ext) {
            return "audio"
        }
        if ["zip", "rar", "7z", "cbz", "cbr"].contains(ext) {
            return "archive"
        }
        if ext == "pdf" {
            return "document"
        }
        return "media"
    }

    private static func mediaFormat(for url: URL) -> String {
        let ext = url.pathExtension.lowercased()
        if !ext.isEmpty {
            return ext
        }
        let absolute = url.absoluteString.lowercased()
        for value in knownDownloadExtensions where absolute.contains(".\(value)") {
            return value
        }
        return ""
    }

    private static func pageSlug(from url: URL) -> String {
        let last = url.deletingPathExtension().lastPathComponent
        if !last.trimmed.isEmpty {
            return last.sanitizedFilename(maxLength: 120)
        }
        return (url.host ?? "").sanitizedFilename(maxLength: 120)
    }

    private static func looksLikeMediaReference(_ value: String) -> Bool {
        let trimmed = value.trimmed
        guard !trimmed.isEmpty,
              !trimmed.hasPrefix("#"),
              !trimmed.lowercased().hasPrefix("data:"),
              !trimmed.lowercased().hasPrefix("blob:"),
              !trimmed.lowercased().hasPrefix("javascript:") else {
            return false
        }

        let ext = URL(string: trimmed)?.pathExtension.lowercased() ?? (trimmed as NSString).pathExtension.lowercased()
        return metadataMediaExtensions.contains(ext)
    }

    private static func isMediaObject(_ dictionary: [String: Any]) -> Bool {
        let rawType = dictionary["@type"] ?? dictionary["type"]
        let values: [String]
        if let string = rawType as? String {
            values = [string]
        } else if let array = rawType as? [String] {
            values = array
        } else {
            values = []
        }

        return values.contains { value in
            let lowered = value.lowercased()
            return lowered.contains("imageobject") ||
                lowered.contains("videoobject") ||
                lowered.contains("audioobject") ||
                lowered.contains("mediaobject")
        }
    }

    private static func title(from url: URL) -> String {
        if let host = url.host {
            let last = url.deletingPathExtension().lastPathComponent
            return last.trimmed.isEmpty ? host : "\(host) \(last)"
        }
        return "Page Media"
    }

    private static func stripTags(_ text: String) -> String {
        text.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmed
    }

    private static func decodeHTML(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
    }

    private static let knownDownloadExtensions: Set<String> = [
        "jpg", "jpeg", "png", "gif", "webp", "avif", "bmp", "svg",
        "mp4", "m4v", "mov", "webm", "mkv", "avi",
        "mp3", "m4a", "aac", "flac", "wav", "ogg",
        "zip", "rar", "7z", "cbz", "cbr", "pdf"
    ]

    private static let metadataMediaExtensions: Set<String> = [
        "jpg", "jpeg", "png", "gif", "webp", "avif", "bmp", "svg",
        "mp4", "m4v", "mov", "webm", "mkv", "avi",
        "mp3", "m4a", "aac", "flac", "wav", "ogg"
    ]
}

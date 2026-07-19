import Foundation

struct DCInsideArticleID: Equatable {
    let gallery: String
    let article: String

    var token: String { "dc_\(gallery)_\(article)" }
}

final class DCInsideResolver {
    func canResolve(_ url: URL) -> Bool {
        Self.articleID(from: url) != nil
    }

    func resolve(
        _ url: URL,
        headers: HTTPRequestOptions = HTTPRequestOptions()
    ) async throws -> ResolvedDownload {
        let pageURL = Self.canonicalURL(for: url) ?? url
        guard let articleID = Self.articleID(from: pageURL) else {
            throw NativeDownloadError.invalidURL(url.absoluteString)
        }
        let page = try await readPage(pageURL, headers: headers)
        return try await Self.resolvedDownload(
            fromHTML: page.html,
            pageURL: pageURL,
            articleID: articleID,
            headers: headers
        )
    }

    static func canonicalURL(for url: URL) -> URL? {
        guard articleID(from: url) != nil,
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return nil
        }
        components.fragment = nil
        components.queryItems = components.queryItems?.filter { item in
            !(item.name.caseInsensitiveCompare("t") == .orderedSame && item.value?.lowercased() == "cv")
        }
        if components.queryItems?.isEmpty == true {
            components.queryItems = nil
        }
        return components.url
    }

    static func canonicalShortcutURL(from raw: String) -> URL? {
        var token = raw.trimmed
        guard token.lowercased().hasPrefix("dc_") else { return nil }
        token.removeFirst(3)
        guard !token.contains("://"),
              !token.contains("/"),
              let separator = token.lastIndex(of: "_") else {
            return nil
        }
        let gallery = String(token[..<separator])
        let article = String(token[token.index(after: separator)...])
        guard gallery.range(of: #"^[0-9A-Za-z_-]+$"#, options: .regularExpression) != nil,
              !gallery.isEmpty,
              article.allSatisfy(\.isNumber),
              !article.isEmpty else {
            return nil
        }
        var components = URLComponents()
        components.scheme = "http"
        components.host = "gall.dcinside.com"
        components.path = "/board/view/"
        components.queryItems = [
            URLQueryItem(name: "id", value: gallery),
            URLQueryItem(name: "no", value: article)
        ]
        return components.url
    }

    static func articleID(from url: URL) -> DCInsideArticleID? {
        guard let host = url.host?.lowercased(),
              isSupportedHost(host),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            return nil
        }
        if url.path.localizedCaseInsensitiveContains("/board/") {
            let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
            guard let gallery = items.first(where: { $0.name.caseInsensitiveCompare("id") == .orderedSame })?.value,
                  gallery.range(of: #"^[0-9A-Za-z_-]+$"#, options: .regularExpression) != nil,
                  let article = items.first(where: { $0.name.caseInsensitiveCompare("no") == .orderedSame })?.value,
                  !article.isEmpty,
                  article.allSatisfy(\.isNumber) else {
                return nil
            }
            return DCInsideArticleID(gallery: gallery, article: article)
        }

        let parts = url.path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        guard parts.count >= 2,
              !parts[0].isEmpty,
              let article = firstDigitRun(in: parts[1]) else {
            return nil
        }
        return DCInsideArticleID(gallery: parts[0], article: article)
    }

    static func resolvedDownload(
        fromHTML html: String,
        pageURL: URL,
        articleID: DCInsideArticleID? = nil,
        headers: HTTPRequestOptions = HTTPRequestOptions()
    ) async throws -> ResolvedDownload {
        guard let articleID = articleID ?? self.articleID(from: pageURL) else {
            throw NativeDownloadError.invalidURL(pageURL.absoluteString)
        }
        let subject = titleSubject(fromHTML: html)
        let articleAuthor = author(fromHTML: html) ?? ""
        let title = "\(subject) (\(articleID.token))".sanitizedFilename(maxLength: 120)
        let candidates = mediaCandidates(fromHTML: html, pageURL: pageURL)
        guard !candidates.isEmpty else {
            throw NativeDownloadError.noFiles
        }

        let articleMetadata = DownloadMetadata.clean([
            "site": "dcinside",
            "gallery": articleID.gallery,
            "series": articleID.gallery,
            "article_id": articleID.article,
            "post_id": articleID.article,
            "episode": articleID.article,
            "chapter": articleID.article,
            "title": subject,
            "artist": articleAuthor,
            "author": articleAuthor,
            "creator": articleAuthor,
            "uploader": articleAuthor,
            "username": articleAuthor,
            "language": "korean",
            "lang": "korean",
            "url": pageURL.absoluteString,
            "source_url": pageURL.absoluteString,
            "page_url": pageURL.absoluteString,
            "original_contract": "dc-hds"
        ])

        var assets: [ResolvedAsset] = []
        for candidate in candidates {
            let remote: URL
            if candidate.usesPopup {
                remote = try await popupImageURL(
                    candidate.url,
                    pageURL: pageURL,
                    headers: headers
                )
            } else {
                guard let value = absoluteURL(candidate.url, baseURL: pageURL) else { continue }
                remote = value
            }
            let ext = await outputExtension(for: remote, pageURL: pageURL, headers: headers)
            let index = assets.count
            let mediaType = mediaType(forExtension: ext)
            assets.append(ResolvedAsset(
                remoteURL: remote,
                filename: String(format: "%04d%@", index, ext),
                metadata: DownloadMetadata.clean(articleMetadata.merging([
                    "type": mediaType,
                    "media_type": mediaType,
                    "page": String(index + 1),
                    "position": String(index + 1),
                    "popup_resolved": candidate.usesPopup ? "true" : "false",
                ]) { _, assetValue in assetValue }),
                referer: pageURL.absoluteString,
                userAgent: headers.userAgent
            ))
        }
        guard !assets.isEmpty else {
            throw NativeDownloadError.noFiles
        }

        let mediaTypes = Set(assets.compactMap { $0.metadata["media_type"] })
        let aggregateMediaType = mediaTypes.count > 1 ? "mixed" : mediaTypes.first ?? "image"
        var downloadMetadata = articleMetadata
        downloadMetadata["id"] = articleID.token
        downloadMetadata["type"] = "dcinside"
        downloadMetadata["media_type"] = aggregateMediaType
        downloadMetadata["media_count"] = String(assets.count)
        downloadMetadata["thumbnail_url"] = assets.first?.remoteURL.absoluteString ?? ""

        return ResolvedDownload(
            title: title,
            folderName: title,
            assets: assets,
            metadata: DownloadMetadata.clean(downloadMetadata)
        )
    }

    static func redirectURL(fromShortHTML html: String, baseURL: URL) -> URL? {
        guard html.utf8.count < 2_000,
              html.localizedCaseInsensitiveContains("location.replace"),
              let regex = try? NSRegularExpression(
                pattern: #"location\.replace.*?[\"'](.*?)[\"']"#,
                options: [.caseInsensitive, .dotMatchesLineSeparators]
              ),
              let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..<html.endIndex, in: html)),
              let capture = Range(match.range(at: 1), in: html) else {
            return nil
        }
        return absoluteURL(decodeHTML(String(html[capture])), baseURL: baseURL)
    }

    static func titleSubject(fromHTML html: String) -> String {
        if let block = firstElementBlock(tag: "span", className: "title_subject", in: html) {
            return cleanedText(block.body, fallback: "DCInside")
        }
        return "DCInside"
    }

    static func author(fromHTML html: String) -> String? {
        for tag in ["div", "span", "td"] {
            guard let writer = firstElementBlock(tag: tag, className: "gall_writer", in: html) else {
                continue
            }
            let attributes = attributeValues(from: writer.openingTag)
            for key in ["data-nick", "data-name", "data-username"] {
                if let author = cleanedAuthorCandidate(attributes[key]) {
                    return author
                }
            }
            for nestedClass in ["nickname", "user_name", "nick", "name"] {
                for nestedTag in ["span", "strong", "div"] {
                    guard let nested = firstElementBlock(tag: nestedTag, className: nestedClass, in: writer.body) else {
                        continue
                    }
                    if let author = cleanedAuthorCandidate(nested.body) {
                        return author
                    }
                }
            }
        }
        return nil
    }

    private struct PageResult {
        let html: String
    }

    private struct MediaCandidate {
        let url: String
        let usesPopup: Bool
    }

    private struct ElementBlock {
        let openingTag: String
        let body: String
    }

    private func readPage(_ url: URL, headers: HTTPRequestOptions) async throws -> PageResult {
        let html = try await HTTPClient.shared.string(
            from: url,
            referer: headers.referer,
            userAgent: headers.userAgent
        )
        guard let redirected = Self.redirectURL(fromShortHTML: html, baseURL: url) else {
            return PageResult(html: html)
        }
        return PageResult(html: try await HTTPClient.shared.string(
            from: redirected,
            referer: headers.referer,
            userAgent: headers.userAgent
        ))
    }

    private static func popupImageURL(
        _ rawPopupURL: String,
        pageURL: URL,
        headers: HTTPRequestOptions
    ) async throws -> URL {
        guard let popupURL = absoluteURL(rawPopupURL, baseURL: pageURL) else {
            throw NativeDownloadError.invalidURL(rawPopupURL)
        }
        var lastError: Error = NativeDownloadError.noFiles
        for _ in 0..<2 {
            do {
                let html = try await HTTPClient.shared.string(
                    from: popupURL,
                    referer: pageURL.absoluteString,
                    userAgent: headers.userAgent
                )
                guard let image = firstTagAttributes(tag: "img", in: html)["src"],
                      let remote = absoluteURL(image, baseURL: popupURL) else {
                    throw NativeDownloadError.noFiles
                }
                return remote
            } catch {
                lastError = error
            }
        }
        throw lastError
    }

    private static func mediaCandidates(fromHTML html: String, pageURL: URL) -> [MediaCandidate] {
        guard let view = firstElementBlock(tag: "div", className: "writing_view_box", in: html),
              let regex = try? NSRegularExpression(
                pattern: #"<(img|video)\b([^>]*)>"#,
                options: [.caseInsensitive, .dotMatchesLineSeparators]
              ) else {
            return []
        }
        var output: [MediaCandidate] = []
        var seen = Set<String>()
        let range = NSRange(view.body.startIndex..<view.body.endIndex, in: view.body)
        for match in regex.matches(in: view.body, range: range) {
            guard let tagRange = Range(match.range(at: 1), in: view.body),
                  let attrsRange = Range(match.range(at: 2), in: view.body) else { continue }
            let tag = String(view.body[tagRange]).lowercased()
            let attrsText = String(view.body[attrsRange])
            let attrs = attributeValues(from: attrsText)
            let popup = firstCapture(
                pattern: #"imgPop\(['\"](.*?)['\"]"#,
                in: attrsText
            ).map(decodeHTML)
            let raw: String?
            let usesPopup: Bool
            if let popup {
                raw = popup
                usesPopup = true
            } else {
                var direct = attrs["data-src"] ?? attrs["src"]
                if direct == nil, tag == "video",
                   let openingRange = Range(match.range, in: view.body) {
                    let tail = String(view.body[openingRange.upperBound...])
                    let videoBody = tail.range(
                        of: #"</video\s*>"#,
                        options: [.regularExpression, .caseInsensitive]
                    ).map { String(tail[..<$0.lowerBound]) } ?? tail
                    direct = firstTagAttributes(tag: "source", in: videoBody)["src"]
                }
                raw = direct
                usesPopup = false
            }
            guard let raw = raw?.trimmed,
                  !raw.isEmpty,
                  !raw.localizedCaseInsensitiveContains("nstatic.dcinside"),
                  seen.insert(raw).inserted else {
                continue
            }
            output.append(MediaCandidate(url: raw, usesPopup: usesPopup))
        }
        return output
    }

    private static func outputExtension(
        for url: URL,
        pageURL: URL,
        headers: HTTPRequestOptions
    ) async -> String {
        let allowed = Set(["jpg", "jpeg", "bmp", "png", "gif", "webm", "webp"])
        let direct = url.pathExtension.lowercased()
        if allowed.contains(direct) {
            return ".\(direct)"
        }
        if let response = try? await HTTPClient.shared.head(
            from: url,
            referer: pageURL.absoluteString,
            userAgent: headers.userAgent
        ) {
            let redirectedExtension = response.url?.pathExtension.lowercased() ?? ""
            if allowed.contains(redirectedExtension) {
                return ".\(redirectedExtension)"
            }
            if let disposition = response.value(forHTTPHeaderField: "Content-Disposition"),
               let ext = contentDispositionExtension(disposition),
               allowed.contains(ext) {
                return ".\(ext)"
            }
            let contentType = response.value(forHTTPHeaderField: "Content-Type")?.lowercased() ?? ""
            let mappings = [
                "image/jpeg": ".jpg",
                "image/png": ".png",
                "image/gif": ".gif",
                "image/webp": ".webp",
                "image/bmp": ".bmp",
                "video/webm": ".webm"
            ]
            for (mime, ext) in mappings where contentType.contains(mime) {
                return ext
            }
        }
        return ".jpg"
    }

    static func contentDispositionExtension(_ raw: String) -> String? {
        let patterns = [
            #"filename\*\s*=\s*UTF-8''([^;]+)"#,
            #"filename\s*=\s*[\"']?([^;\"']+)"#
        ]
        for pattern in patterns {
            guard let value = firstCapture(pattern: pattern, in: raw) else { continue }
            let decoded = value.removingPercentEncoding ?? value
            let ext = URL(fileURLWithPath: decoded.trimmed).pathExtension.lowercased()
            if !ext.isEmpty {
                return ext
            }
        }
        return nil
    }

    private static func mediaType(forExtension ext: String) -> String {
        ext.lowercased() == ".webm" ? "video" : "image"
    }

    private static func firstDigitRun(in raw: String) -> String? {
        guard let range = raw.range(of: #"[0-9]+"#, options: .regularExpression) else { return nil }
        return String(raw[range])
    }

    private static func isSupportedHost(_ host: String) -> Bool {
        host == "gall.dcinside.com" || host.hasSuffix(".gall.dcinside.com") ||
            host == "gall.dcinside.test" || host.hasSuffix(".gall.dcinside.test")
    }

    private static func firstElementBlock(tag: String, className: String?, in html: String) -> ElementBlock? {
        guard let openingRegex = try? NSRegularExpression(
            pattern: #"<\#(tag)\b[^>]*>"#,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        ) else { return nil }
        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        for match in openingRegex.matches(in: html, range: range) {
            guard let openingRange = Range(match.range, in: html) else { continue }
            let opening = String(html[openingRange])
            if let className {
                let classes = (attributeValues(from: opening)["class"] ?? "")
                    .split(whereSeparator: { $0.isWhitespace })
                    .map { $0.lowercased() }
                guard classes.contains(className.lowercased()) else { continue }
            }
            let tail = String(html[openingRange.upperBound...])
            guard let tagRegex = try? NSRegularExpression(
                pattern: #"</?\#(tag)\b[^>]*>"#,
                options: [.caseInsensitive, .dotMatchesLineSeparators]
            ) else { return nil }
            var depth = 1
            let tailRange = NSRange(tail.startIndex..<tail.endIndex, in: tail)
            for tokenMatch in tagRegex.matches(in: tail, range: tailRange) {
                guard let tokenRange = Range(tokenMatch.range, in: tail) else { continue }
                let token = String(tail[tokenRange]).lowercased()
                depth += token.hasPrefix("</") ? -1 : (token.hasSuffix("/>") ? 0 : 1)
                if depth == 0 {
                    return ElementBlock(openingTag: opening, body: String(tail[..<tokenRange.lowerBound]))
                }
            }
        }
        return nil
    }

    private static func firstTagAttributes(tag: String, in html: String) -> [String: String] {
        guard let regex = try? NSRegularExpression(
            pattern: #"<\#(tag)\b([^>]*)>"#,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        ),
        let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..<html.endIndex, in: html)),
        let capture = Range(match.range(at: 1), in: html) else {
            return [:]
        }
        return attributeValues(from: String(html[capture]))
    }

    private static func attributeValues(from raw: String) -> [String: String] {
        guard let regex = try? NSRegularExpression(
            pattern: #"([A-Za-z_:][-A-Za-z0-9_:.]*)\s*=\s*(?:\"([^\"]*)\"|'([^']*)'|([^\s\"'=<>`]+))"#,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        ) else { return [:] }
        var values: [String: String] = [:]
        let range = NSRange(raw.startIndex..<raw.endIndex, in: raw)
        for match in regex.matches(in: raw, range: range) {
            guard let keyRange = Range(match.range(at: 1), in: raw) else { continue }
            let value = (2...4).compactMap { index -> String? in
                guard let valueRange = Range(match.range(at: index), in: raw) else { return nil }
                return String(raw[valueRange])
            }.first ?? ""
            values[String(raw[keyRange]).lowercased()] = decodeHTML(value)
        }
        return values
    }

    private static func firstCapture(pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(
            pattern: pattern,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        ),
        let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..<text.endIndex, in: text)),
        let capture = Range(match.range(at: 1), in: text) else {
            return nil
        }
        return String(text[capture])
    }

    private static func absoluteURL(_ raw: String, baseURL: URL) -> URL? {
        let value = decodeHTML(raw).trimmed
        guard !value.isEmpty else { return nil }
        return URL(string: value, relativeTo: baseURL)?.absoluteURL
    }

    private static func cleanedText(_ raw: String, fallback: String) -> String {
        let value = decodeHTML(raw)
            .replacingOccurrences(of: #"<br\s*/?>"#, with: " ", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: #"<[^>]+>"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmed
        return value.isEmpty ? fallback : value
    }

    private static func cleanedAuthorCandidate(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let value = cleanedText(raw, fallback: "")
        guard !value.isEmpty, value.count <= 120 else { return nil }
        let ignored = ["author", "writer", "user", "작성자"]
        return ignored.contains(value.lowercased()) ? nil : value
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
}

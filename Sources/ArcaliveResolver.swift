import Foundation

enum ArcaliveResolverError: LocalizedError {
    case authenticationRequired(URL)

    var errorDescription: String? {
        switch self {
        case .authenticationRequired:
            return "Arcalive login or browser verification is required."
        }
    }
}

struct ArcaliveArticleID: Equatable {
    let board: String
    let article: String

    var token: String { "\(board)_\(article)" }
}

final class ArcaliveResolver {
    func canResolve(_ url: URL) -> Bool {
        Self.articleID(from: url) != nil
    }

    func resolve(
        _ url: URL,
        headers: HTTPRequestOptions = HTTPRequestOptions()
    ) async throws -> ResolvedDownload {
        guard let articleID = Self.articleID(from: url) else {
            throw NativeDownloadError.invalidURL(url.absoluteString)
        }
        let pageURL = Self.fragmentStrippedURL(url)
        let (data, response) = try await HTTPClient.shared.dataResponse(
            from: pageURL,
            referer: headers.referer,
            userAgent: headers.userAgent,
            acceptedStatusCodes: [403, 451]
        )
        let html = Self.decodeResponse(data)
        if Self.requiresArticleLogin(fromHTML: html) {
            throw ArcaliveResolverError.authenticationRequired(Self.loginURL(for: pageURL, articleChallenge: false))
        }
        if Self.requiresArticleChallenge(fromHTML: html) || response.statusCode == 403 {
            throw ArcaliveResolverError.authenticationRequired(Self.loginURL(for: pageURL, articleChallenge: true))
        }
        if response.statusCode == 451 {
            throw ArcaliveResolverError.authenticationRequired(Self.loginURL(for: pageURL, articleChallenge: false))
        }
        guard 200..<300 ~= response.statusCode else {
            throw NativeDownloadError.httpStatus(response.statusCode, pageURL)
        }
        return try Self.resolvedDownload(
            fromHTML: html,
            pageURL: pageURL,
            articleID: articleID,
            userAgent: headers.userAgent
        )
    }

    static func articleID(from url: URL) -> ArcaliveArticleID? {
        guard let host = url.host?.lowercased(),
              isSupportedHost(host),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            return nil
        }
        let parts = url.path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        guard parts.count >= 3,
              parts[0].lowercased() == "b",
              !parts[1].trimmed.isEmpty,
              !parts[2].trimmed.isEmpty else {
            return nil
        }
        return ArcaliveArticleID(board: parts[1], article: parts[2])
    }

    static func resolvedDownload(
        fromHTML html: String,
        pageURL: URL,
        articleID: ArcaliveArticleID? = nil,
        userAgent: String? = nil
    ) throws -> ResolvedDownload {
        if requiresArticleLogin(fromHTML: html) {
            throw ArcaliveResolverError.authenticationRequired(loginURL(for: pageURL, articleChallenge: false))
        }
        if requiresArticleChallenge(fromHTML: html) {
            throw ArcaliveResolverError.authenticationRequired(loginURL(for: pageURL, articleChallenge: true))
        }
        guard let articleID = articleID ?? self.articleID(from: pageURL) else {
            throw NativeDownloadError.invalidURL(pageURL.absoluteString)
        }
        let articleTitle = title(fromHTML: html)
        let articleAuthor = author(fromHTML: html) ?? ""
        let finalTitle = "\(articleTitle) (\(articleID.token))".sanitizedFilename(maxLength: 120)
        let candidates = mediaCandidates(fromHTML: html, pageURL: pageURL)
        guard !candidates.isEmpty else {
            throw NativeDownloadError.noFiles
        }

        let articleMetadata = DownloadMetadata.clean([
            "site": "arcalive",
            "board": articleID.board,
            "series": articleID.board,
            "article_id": articleID.article,
            "post_id": articleID.article,
            "episode": articleID.article,
            "chapter": articleID.article,
            "title": articleTitle,
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
            "original_contract": "arcalive-251111"
        ])

        let assets = candidates.enumerated().map { index, candidate -> ResolvedAsset in
            let ext = outputExtension(for: candidate.primaryURL, fallbackURL: candidate.fallbackURL)
            let mediaType = candidate.kind == "video" ? "video" : "image"
            var alternatives: [URL] = []
            if let fallback = candidate.fallbackURL,
               fallback.absoluteString != candidate.primaryURL.absoluteString {
                alternatives.append(fallback)
            }
            for candidateURL in [candidate.fallbackURL, candidate.primaryURL].compactMap({ $0 }) {
                guard let withoutOriginal = removingOriginalTypeParameter(from: candidateURL),
                      withoutOriginal.absoluteString != candidate.primaryURL.absoluteString,
                      !alternatives.contains(where: { $0.absoluteString == withoutOriginal.absoluteString }) else {
                    continue
                }
                alternatives.append(withoutOriginal)
            }
            return ResolvedAsset(
                remoteURL: candidate.primaryURL,
                filename: "\(String(articleTitle.prefix(100)))_p\(index)\(ext)".sanitizedFilename(maxLength: 180),
                metadata: DownloadMetadata.clean(articleMetadata.merging([
                    "type": candidate.kind,
                    "media_type": mediaType,
                    "page": String(index + 1),
                    "position": String(index + 1),
                    "asset_concurrency_override": "2",
                ]) { _, assetValue in assetValue }),
                referer: pageURL.absoluteString,
                userAgent: userAgent,
                alternativeRemoteURLs: alternatives
            )
        }

        let mediaTypes = Set(assets.compactMap { $0.metadata["media_type"] })
        let aggregateMediaType = mediaTypes.count > 1 ? "mixed" : mediaTypes.first ?? "image"
        var downloadMetadata = articleMetadata
        downloadMetadata["id"] = articleID.token
        downloadMetadata["type"] = "arcalive"
        downloadMetadata["media_type"] = aggregateMediaType
        downloadMetadata["media_count"] = String(assets.count)
        downloadMetadata["thumbnail_url"] = assets.first?.remoteURL.absoluteString ?? ""

        return ResolvedDownload(
            title: finalTitle,
            folderName: finalTitle,
            assets: assets,
            metadata: DownloadMetadata.clean(downloadMetadata)
        )
    }

    static func title(fromHTML html: String) -> String {
        guard let row = firstElementBlock(tag: "div", className: "title-row", in: html),
              let title = firstElementBlock(tag: "div", className: "title", in: row.body) else {
            return "Arcalive"
        }
        let withoutBadges = removingElements(tag: "span", className: "badge", from: title.body)
        return cleanedText(withoutBadges, fallback: "Arcalive")
    }

    static func author(fromHTML html: String) -> String? {
        let scope = articleHeaderHTML(from: html)
        let containerClasses = ["user-info", "member-info", "article-writer", "writer"]
        let tags = ["a", "div", "span"]

        for className in containerClasses {
            for tag in tags {
                guard let block = firstElementBlock(tag: tag, className: className, in: scope) else {
                    continue
                }
                let attributes = attributeValues(from: block.openingTag)
                for key in ["data-nick", "data-display-name", "data-name"] {
                    if let author = cleanedAuthorCandidate(attributes[key]) {
                        return author
                    }
                }
                for nestedClass in ["user-name", "nickname", "nick", "name"] {
                    for nestedTag in ["span", "strong", "div"] {
                        guard let nested = firstElementBlock(tag: nestedTag, className: nestedClass, in: block.body) else {
                            continue
                        }
                        if let author = cleanedAuthorCandidate(nested.body) {
                            return author
                        }
                    }
                }
                for key in ["data-username", "data-user-name"] {
                    if let author = cleanedAuthorCandidate(attributes[key]) {
                        return author
                    }
                }
                let withoutBadges = removingElements(tag: "span", className: "badge", from: block.body)
                if let author = cleanedAuthorCandidate(withoutBadges) {
                    return author
                }
            }
        }
        return nil
    }

    static func requiresArticleChallenge(fromHTML html: String) -> Bool {
        firstElementBlock(tag: "div", className: "h-captcha", in: html) != nil
    }

    static func requiresArticleLogin(fromHTML html: String) -> Bool {
        if firstElementBlock(tag: "div", className: "text-muted", in: html) != nil {
            return true
        }
        guard let h1 = firstElementBlock(tag: "h1", className: nil, in: html) else {
            return false
        }
        return cleanedText(h1.body, fallback: "").localizedCaseInsensitiveContains("Error HTTP 451")
    }

    static func loginURL(for pageURL: URL, articleChallenge: Bool) -> URL {
        if articleChallenge {
            return pageURL
        }
        let host = pageURL.host?.lowercased().hasSuffix(".test") == true ? "arca.test" : "arca.live"
        return URL(string: "https://\(host)/u/login?goto=%2F")!
    }

    private struct MediaCandidate {
        let primaryURL: URL
        let fallbackURL: URL?
        let kind: String
    }

    private struct ElementBlock {
        let openingTag: String
        let body: String
        let full: String
    }

    private static func mediaCandidates(fromHTML html: String, pageURL: URL) -> [MediaCandidate] {
        guard let view = firstElementBlock(tag: "div", className: "article-content", in: html),
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
                  let attributesRange = Range(match.range(at: 2), in: view.body) else {
                continue
            }
            let kind = String(view.body[tagRange]).lowercased()
            let attributes = attributeValues(from: String(view.body[attributesRange]))
            let classes = Set((attributes["class"] ?? "").split(whereSeparator: { $0.isWhitespace }).map(String.init))
            guard !classes.contains("arca-emoticon") else { continue }

            let src = attributes["src"].flatMap { absoluteURL($0, baseURL: pageURL) }
            guard var primary = attributes["data-originalurl"].flatMap({ absoluteURL($0, baseURL: pageURL) }) ?? src else {
                continue
            }
            if primary.absoluteString.localizedCaseInsensitiveContains("namu.la") {
                primary = URL(string: primary.absoluteString + "&type=orig") ?? primary
            }
            guard seen.insert(primary.absoluteString).inserted else { continue }
            output.append(MediaCandidate(primaryURL: primary, fallbackURL: src, kind: kind))
        }
        return output
    }

    private static func outputExtension(for primaryURL: URL, fallbackURL: URL?) -> String {
        for url in [primaryURL, fallbackURL].compactMap({ $0 }) {
            let ext = url.pathExtension.lowercased()
            if ext.range(of: #"^[a-z0-9]{1,8}$"#, options: .regularExpression) != nil {
                return ".\(ext)"
            }
        }
        return ".jpg"
    }

    private static func removingOriginalTypeParameter(from url: URL) -> URL? {
        guard url.absoluteString.contains("&type=orig") else { return nil }
        return URL(string: url.absoluteString.replacingOccurrences(of: "&type=orig", with: ""))
    }

    private static func articleHeaderHTML(from html: String) -> String {
        let pattern = #"<div\b(?=[^>]*\bclass\s*=\s*[\"'][^\"']*\barticle-content\b[^\"']*[\"'])[^>]*>"#
        guard let range = html.range(of: pattern, options: [.regularExpression, .caseInsensitive]) else {
            return html
        }
        return String(html[..<range.lowerBound])
    }

    private static func cleanedAuthorCandidate(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let value = cleanedText(raw, fallback: "")
        guard !value.isEmpty, value.count <= 120 else { return nil }
        let ignored = ["author", "writer", "user", "작성자"]
        return ignored.contains(value.lowercased()) ? nil : value
    }

    private static func fragmentStrippedURL(_ url: URL) -> URL {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return url }
        components.fragment = nil
        return components.url ?? url
    }

    private static func isSupportedHost(_ host: String) -> Bool {
        host == "arca.live" || host.hasSuffix(".arca.live") ||
            host == "arca.test" || host.hasSuffix(".arca.test")
    }

    private static func firstElementBlock(tag: String, className: String?, in html: String) -> ElementBlock? {
        let openingPattern = #"<\#(tag)\b[^>]*>"#
        guard let openingRegex = try? NSRegularExpression(
            pattern: openingPattern,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        ) else { return nil }
        let fullRange = NSRange(html.startIndex..<html.endIndex, in: html)
        for openingMatch in openingRegex.matches(in: html, range: fullRange) {
            guard let openingRange = Range(openingMatch.range, in: html) else { continue }
            let opening = String(html[openingRange])
            if let className {
                let classes = (attributeValues(from: opening)["class"] ?? "")
                    .split(whereSeparator: { $0.isWhitespace })
                    .map { $0.lowercased() }
                guard classes.contains(className.lowercased()) else { continue }
            }
            if ["img", "meta", "source", "input", "br", "hr", "link"].contains(tag.lowercased()) {
                return ElementBlock(openingTag: opening, body: "", full: opening)
            }
            let tailStart = openingRange.upperBound
            let tail = String(html[tailStart...])
            guard let tagRegex = try? NSRegularExpression(
                pattern: #"</?\#(tag)\b[^>]*>"#,
                options: [.caseInsensitive, .dotMatchesLineSeparators]
            ) else { return nil }
            let tailRange = NSRange(tail.startIndex..<tail.endIndex, in: tail)
            var depth = 1
            for tagMatch in tagRegex.matches(in: tail, range: tailRange) {
                guard let localRange = Range(tagMatch.range, in: tail) else { continue }
                let token = String(tail[localRange])
                if token.hasPrefix("</") || token.hasPrefix("</".uppercased()) {
                    depth -= 1
                } else if !token.hasSuffix("/>") {
                    depth += 1
                }
                if depth == 0 {
                    let body = String(tail[..<localRange.lowerBound])
                    let full = opening + String(tail[..<localRange.upperBound])
                    return ElementBlock(openingTag: opening, body: body, full: full)
                }
            }
        }
        return nil
    }

    private static func removingElements(tag: String, className: String, from html: String) -> String {
        let pattern = #"<\#(tag)\b(?=[^>]*\bclass\s*=\s*[\"'][^\"']*\b\#(className)\b[^\"']*[\"'])[^>]*>.*?</\#(tag)\s*>"#
        return html.replacingOccurrences(
            of: pattern,
            with: " ",
            options: [.regularExpression, .caseInsensitive]
        )
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
            let key = String(raw[keyRange]).lowercased()
            let value = (2...4).compactMap { index -> String? in
                guard let valueRange = Range(match.range(at: index), in: raw) else { return nil }
                return String(raw[valueRange])
            }.first ?? ""
            values[key] = decodeHTML(value)
        }
        return values
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

    private static func decodeHTML(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&apos;", with: "'")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
    }

    private static func decodeResponse(_ data: Data) -> String {
        String(data: data, encoding: .utf8) ??
            String(data: data, encoding: .isoLatin1) ??
            String(decoding: data, as: UTF8.self)
    }
}

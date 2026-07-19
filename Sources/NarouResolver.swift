import Foundation

final class NarouResolver {
    func canResolve(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased(),
              Self.isSupportedHost(host),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            return false
        }
        return Self.ncode(from: url) != nil
    }

    func resolve(
        _ url: URL,
        headers: HTTPRequestOptions = HTTPRequestOptions(),
        assetLimit: Int? = nil
    ) async throws -> ResolvedDownload {
        let html = try await HTTPClient.shared.string(from: url, referer: headers.referer, userAgent: headers.userAgent)

        if Self.chapterNumber(from: url) != nil {
            return try Self.resolvedChapterDownload(fromHTML: html, pageURL: url)
        }

        guard let ncode = Self.ncode(from: url) else {
            throw NativeDownloadError.invalidURL(url.absoluteString)
        }

        let title = Self.seriesTitle(fromHTML: html, pageURL: url, ncode: ncode)
        let author = Self.authorName(fromHTML: html)
        let outputTitle = Self.seriesOutputTitle(title: title, author: author, ncode: ncode)
        let synopsis = Self.seriesSynopsis(fromHTML: html)
        let finiteAssetLimit = assetLimit.flatMap { $0 > 0 ? $0 : nil }
        var chapterURLs: [URL] = []
        var seenChapterURLs = Set<String>()
        var currentListURL = url
        var currentListHTML = html
        var seenListURLs = Set([URLIdentity.normalize(url.absoluteString)])
        var listPageCount = 1

        while true {
            try Task.checkCancellation()
            for chapterURL in Self.chapterURLs(fromHTML: currentListHTML, ncode: ncode, baseURL: currentListURL) {
                let identity = URLIdentity.normalize(chapterURL.absoluteString)
                guard seenChapterURLs.insert(identity).inserted else { continue }
                chapterURLs.append(chapterURL)
                if let finiteAssetLimit, chapterURLs.count >= finiteAssetLimit {
                    break
                }
            }

            if let finiteAssetLimit, chapterURLs.count >= finiteAssetLimit {
                break
            }
            guard let nextURL = Self.nextListPageURL(fromHTML: currentListHTML, baseURL: currentListURL, ncode: ncode) else {
                break
            }
            let nextIdentity = URLIdentity.normalize(nextURL.absoluteString)
            guard seenListURLs.insert(nextIdentity).inserted else { break }

            try Task.checkCancellation()
            currentListHTML = try await HTTPClient.shared.string(
                from: nextURL,
                referer: currentListURL.absoluteString,
                userAgent: headers.userAgent
            )
            currentListURL = nextURL
            listPageCount += 1
        }

        guard !chapterURLs.isEmpty else {
            return try Self.resolvedChapterDownload(fromHTML: html, pageURL: url, seriesTitle: title, index: 1)
        }

        let temporaryDirectory = try Self.makeTemporaryTextDirectory()
        var assets: [ResolvedAsset] = []
        do {
            for (offset, chapterURL) in chapterURLs.enumerated() {
                try Task.checkCancellation()
                let chapterHTML = try await HTTPClient.shared.string(from: chapterURL, referer: url.absoluteString, userAgent: headers.userAgent)
                let asset = try Self.chapterAsset(
                    fromHTML: chapterHTML,
                    pageURL: chapterURL,
                    seriesTitle: title,
                    index: offset + 1,
                    temporaryDirectory: temporaryDirectory
                )
                assets.append(asset)
            }
        } catch {
            try? FileManager.default.removeItem(at: temporaryDirectory)
            throw error
        }

        guard !assets.isEmpty else {
            throw NativeDownloadError.noFiles
        }

        let metadata = Self.narouMetadata(
            seriesTitle: title,
            ncode: ncode,
            author: author,
            episodeCount: assets.count,
            textCount: assets.count,
            listedEpisodeCount: chapterURLs.count,
            listPageCount: listPageCount
        )
        return ResolvedDownload(
            title: outputTitle,
            folderName: outputTitle,
            assets: assets,
            metadata: metadata,
            textMergePlan: Self.mergedTextPlan(
                title: title,
                author: author,
                synopsis: synopsis,
                outputTitle: outputTitle
            ),
            temporaryAssetDirectories: [temporaryDirectory]
        )
    }

    static func resolvedChapterDownload(fromHTML html: String, pageURL: URL, seriesTitle: String? = nil, index: Int? = nil) throws -> ResolvedDownload {
        let code = ncode(from: pageURL) ?? "novel"
        let title = seriesTitle ?? Self.seriesTitle(fromHTML: html, pageURL: pageURL, ncode: code)
        let asset = try chapterAsset(fromHTML: html, pageURL: pageURL, seriesTitle: title, index: index)
        let chapter = chapterTitle(fromHTML: html, pageURL: pageURL)

        let metadata = narouMetadata(
            seriesTitle: title,
            ncode: code,
            author: authorName(fromHTML: html),
            episodeCount: 1,
            textCount: 1
        )
        return ResolvedDownload(
            title: "\(title) - \(chapter)".sanitizedFilename(maxLength: 120),
            folderName: "Narou \(title)".sanitizedFilename(maxLength: 120),
            assets: [asset],
            metadata: metadata,
            temporaryAssetDirectories: [asset.remoteURL.deletingLastPathComponent()]
        )
    }

    static func chapterAsset(
        fromHTML html: String,
        pageURL: URL,
        seriesTitle: String,
        index: Int? = nil,
        temporaryDirectory: URL? = nil
    ) throws -> ResolvedAsset {
        let chapter = chapterTitle(fromHTML: html, pageURL: pageURL)
        let body = chapterBodyText(fromHTML: html)
        guard !body.trimmed.isEmpty else {
            throw NativeDownloadError.noFiles
        }

        let number = chapterNumber(from: pageURL) ?? index ?? 1
        let heading = index == nil ? chapter : String(format: "[%04d] %@", number, chapter)
        let content = chapterText(heading: heading, story: body)
        let filename = "\(heading).txt".sanitizedFilename(maxLength: 180)
        let localURL = try writeTemporaryTextFile(
            filename: filename,
            content: content,
            directory: temporaryDirectory
        )
        return ResolvedAsset(
            remoteURL: localURL,
            filename: filename,
            metadata: chapterMetadata(
                seriesTitle: seriesTitle,
                chapterTitle: chapter,
                ncode: ncode(from: pageURL) ?? "",
                author: authorName(fromHTML: html),
                pageURL: pageURL,
                localURL: localURL,
                number: number
            ),
            referer: pageURL.absoluteString
        )
    }

    static func chapterURLs(fromHTML html: String, ncode: String, baseURL: URL) -> [URL] {
        var results: [URL] = []
        var seen = Set<String>()

        for href in anchorHREFs(fromHTML: html) {
            guard let url = absoluteURL(href, baseURL: baseURL),
                  Self.ncode(from: url)?.lowercased() == ncode.lowercased(),
                  chapterNumber(from: url) != nil else {
                continue
            }

            let normalized = URLIdentity.normalize(url.absoluteString)
            guard !seen.contains(normalized) else { continue }
            seen.insert(normalized)
            results.append(url)
        }

        return results.sorted { lhs, rhs in
            (chapterNumber(from: lhs) ?? 0) < (chapterNumber(from: rhs) ?? 0)
        }
    }

    static func nextListPageURL(fromHTML html: String, baseURL: URL, ncode: String) -> URL? {
        guard let regex = try? NSRegularExpression(
            pattern: #"<a\b([^>]*)>"#,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        ) else {
            return nil
        }

        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        for match in regex.matches(in: html, range: range) {
            guard let attributesRange = Range(match.range(at: 1), in: html) else { continue }
            let attributes = attributeValues(from: String(html[attributesRange]))
            let classes = Set((attributes["class"] ?? "").split(whereSeparator: \.isWhitespace).map(String.init))
            let relations = Set((attributes["rel"] ?? "").lowercased().split(whereSeparator: \.isWhitespace).map(String.init))
            guard classes.contains("c-pager__item--next") || relations.contains("next"),
                  let href = attributes["href"],
                  let nextURL = absoluteURL(href, baseURL: baseURL),
                  let host = nextURL.host?.lowercased(),
                  isSupportedHost(host),
                  Self.ncode(from: nextURL)?.lowercased() == ncode.lowercased() else {
                continue
            }
            return nextURL
        }
        return nil
    }

    static func ncode(from url: URL) -> String? {
        let parts = pathParts(from: url)
        guard let first = parts.first?.lowercased(),
              first.range(of: #"^n[0-9]+[a-z]+$"#, options: .regularExpression) != nil else {
            return nil
        }
        return first
    }

    static func chapterNumber(from url: URL) -> Int? {
        let parts = pathParts(from: url)
        guard parts.count >= 2 else { return nil }
        return Int(parts[1])
    }

    static func canonicalURL(ncode rawNcode: String, chapter: Int? = nil, adult: Bool = false, sourceURL: URL? = nil) -> URL? {
        let cleaned = rawNcode.trimmed.trimmingCharacters(in: CharacterSet(charactersIn: "/")).lowercased()
        guard cleaned.range(of: #"^n[0-9]+[a-z]+$"#, options: .regularExpression) != nil else {
            return nil
        }
        let host = sourceURL?.host?.lowercased() ?? (adult ? "novel18.syosetu.com" : "ncode.syosetu.com")
        guard isSupportedHost(host) else { return nil }

        var components = URLComponents()
        components.scheme = "https"
        components.host = host
        if let chapter, chapter > 0 {
            components.path = "/\(cleaned)/\(chapter)/"
        } else {
            components.path = "/\(cleaned)/"
        }
        return components.url
    }

    static func canonicalURL(for url: URL) -> URL? {
        guard let host = url.host?.lowercased(),
              isSupportedHost(host),
              let ncode = ncode(from: url) else {
            return nil
        }
        return canonicalURL(ncode: ncode, chapter: chapterNumber(from: url), adult: host.contains("novel18."), sourceURL: url)
    }

    static func seriesTitle(fromHTML html: String, pageURL: URL, ncode: String) -> String {
        let title = elementText(pattern: #"<(?:p|div|h1)\b[^>]*\bclass\s*=\s*["'][^"']*(?:novel_title|p-novel__title)[^"']*["'][^>]*>(.*?)</(?:p|div|h1)>"#, in: html) ??
            metaContent(from: html, names: ["og:title", "twitter:title"]) ??
            titleTag(fromHTML: html) ??
            ncode
        return cleanTitle(title, fallback: ncode.uppercased())
    }

    static func chapterTitle(fromHTML html: String, pageURL: URL) -> String {
        let title = elementText(pattern: #"<(?:p|div|h1)\b[^>]*\bclass\s*=\s*["'][^"']*(?:novel_subtitle|p-novel__subtitle)[^"']*["'][^>]*>(.*?)</(?:p|div|h1)>"#, in: html) ??
            elementText(pattern: #"<h1\b[^>]*>(.*?)</h1>"#, in: html) ??
            pageURL.lastPathComponent
        return cleanTitle(title, fallback: "Chapter \(chapterNumber(from: pageURL) ?? 1)")
    }

    static func chapterBodyText(fromHTML html: String) -> String {
        chapterBodyFragments(fromHTML: html)
            .map(cleanChapterFragment)
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n════════════════════════════════\n\n")
    }

    static func chapterText(heading: String, story: String) -> String {
        """
        ────────────────────────────────

          ◆  \(heading)

        ────────────────────────────────


        \(story)
        """
    }

    static func seriesOutputTitle(title: String, author: String, ncode: String) -> String {
        let authorPrefix = author.isEmpty ? "" : "[\(author)] "
        return "\(authorPrefix)\(title) (\(ncode.lowercased()))".sanitizedFilename(maxLength: 120)
    }

    static func seriesSynopsis(fromHTML html: String) -> String {
        let fragment = firstCapture(patterns: [
            #"<div\b[^>]*\bid\s*=\s*["']novel_ex["'][^>]*>(.*?)</div>"#,
            #"<(?:div|section)\b[^>]*\bclass\s*=\s*["'][^"']*(?:p-novel__summary|novel_ex)[^"']*["'][^>]*>(.*?)</(?:div|section)>"#
        ], in: html) ?? ""
        return cleanChapterFragment(fragment)
    }

    static func mergedTextPlan(title: String, author: String, synopsis: String, outputTitle: String) -> ResolvedTextMergePlan {
        var header = "    \(title)\n\n"
        if !author.isEmpty {
            header += "    作者：\(author)\n\n\n"
        }
        if !synopsis.isEmpty {
            header += synopsis
        }
        return ResolvedTextMergePlan(
            outputFilename: "[merged] \(outputTitle).txt",
            header: header,
            separator: "\n\n\n\n"
        )
    }

    private static func removingRubyAnnotations(fromHTML html: String) -> String {
        html
            .replacingOccurrences(of: #"(?is)<rt\b[^>]*>.*?</rt>"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"(?is)<rp\b[^>]*>.*?</rp>"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"(?is)<rtc\b[^>]*>.*?</rtc>"#, with: "", options: .regularExpression)
    }

    private static func removingNarouInlineRuby(from text: String) -> String {
        text
            .replacingOccurrences(
                of: #"[|｜]([^《\n]{1,80})《[^》\n]{1,80}》"#,
                with: "$1",
                options: .regularExpression
            )
            .replacingOccurrences(
                of: #"([一-龯々〆ヵヶ]{1,40})《[ぁ-ゖァ-ヺー・=A-Za-z0-9 　\-]{1,80}》"#,
                with: "$1",
                options: .regularExpression
            )
    }

    private static func chapterBodyFragments(fromHTML html: String) -> [String] {
        var legacyBlocks: [String] = []
        for id in ["novel_p", "novel_honbun", "novel_a"] {
            if let block = firstCapture(
                patterns: [#"<div\b[^>]*\bid\s*=\s*["']\#(id)["'][^>]*>(.*?)</div>"#],
                in: html
            ) {
                legacyBlocks.append(block)
            }
        }
        if !legacyBlocks.isEmpty {
            return legacyBlocks
        }

        let modernBlocks = allCaptures(
            pattern: #"<(div|section)\b[^>]*\bclass\s*=\s*["'][^"']*(?:js-novel-text|p-novel__text)[^"']*["'][^>]*>(.*?)</\1>"#,
            in: html,
            group: 2
        )
        if !modernBlocks.isEmpty {
            return modernBlocks
        }

        if let legacy = firstCapture(patterns: [
            #"<div\b[^>]*\bclass\s*=\s*["'][^"']*(?:novel_view|p-novel__body)[^"']*["'][^>]*>(.*?)</div>"#,
            #"<section\b[^>]*\bclass\s*=\s*["'][^"']*p-novel__body[^"']*["'][^>]*>(.*?)</section>"#
        ], in: html) {
            return [legacy]
        }

        return []
    }

    static func authorName(fromHTML html: String) -> String {
        let author = elementText(pattern: #"<[^>]+\bclass\s*=\s*["'][^"']*(?:novel_writername|p-novel__author)[^"']*["'][^>]*>(.*?)</[^>]+>"#, in: html) ??
            metaContent(from: html, names: ["author", "article:author"]) ??
            ""
        return cleanAuthor(author)
    }

    private static func cleanChapterFragment(_ html: String) -> String {
        let withoutRuby = removingRubyAnnotations(fromHTML: html)
        let withBreaks = withoutRuby
            .replacingOccurrences(of: #"(?i)<br\s*/?>"#, with: "\n", options: .regularExpression)
            .replacingOccurrences(of: #"(?i)</p>"#, with: "\n", options: .regularExpression)
            .replacingOccurrences(of: #"(?i)</div>"#, with: "\n", options: .regularExpression)
        let stripped = removingNarouInlineRuby(from: decodeHTML(stripTags(withBreaks)))
        let lines = stripped
            .components(separatedBy: .newlines)
            .map { $0.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression).trimmed }

        var output: [String] = []
        var previousBlank = false
        for line in lines {
            if line.isEmpty {
                if !previousBlank && !output.isEmpty { output.append("") }
                previousBlank = true
            } else {
                output.append(line)
                previousBlank = false
            }
        }
        while output.last == "" { output.removeLast() }
        return output.joined(separator: "\n")
    }

    private static func makeTemporaryTextDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("HitomiBadayo-Narou-\(UUID().uuidString)", isDirectory: true)
        try AppPaths.ensureDirectory(directory)
        return directory
    }

    private static func writeTemporaryTextFile(filename: String, content: String, directory: URL? = nil) throws -> URL {
        let directory = try directory ?? makeTemporaryTextDirectory()
        let url = directory.appendingPathComponent(filename.sanitizedFilename(maxLength: 180))
        try content.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private static func anchorHREFs(fromHTML html: String) -> [String] {
        guard let regex = try? NSRegularExpression(
            pattern: #"<a\b[^>]*\bhref\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s>"']+))"#,
            options: [.caseInsensitive]
        ) else {
            return []
        }

        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        return regex.matches(in: html, range: range).compactMap { match in
            for group in 1...3 {
                guard let capture = Range(match.range(at: group), in: html) else { continue }
                return decodeHTML(String(html[capture])).trimmed
            }
            return nil
        }
    }

    private static func absoluteURL(_ raw: String, baseURL: URL) -> URL? {
        let value = raw.trimmed
        guard !value.isEmpty,
              !value.hasPrefix("#"),
              !value.lowercased().hasPrefix("javascript:"),
              !value.lowercased().hasPrefix("mailto:") else {
            return nil
        }
        return URL(string: value, relativeTo: baseURL)?.absoluteURL
    }

    private static func pathParts(from url: URL) -> [String] {
        url.path.split(separator: "/").map { String($0).removingPercentEncoding ?? String($0) }
    }

    private static func elementText(pattern: String, in html: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else {
            return nil
        }
        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        guard let match = regex.firstMatch(in: html, range: range),
              let capture = Range(match.range(at: 1), in: html) else {
            return nil
        }
        return decodeHTML(stripTags(String(html[capture]))).trimmed
    }

    private static func firstCapture(patterns: [String], in html: String) -> String? {
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else {
                continue
            }
            let range = NSRange(html.startIndex..<html.endIndex, in: html)
            guard let match = regex.firstMatch(in: html, range: range),
                  let capture = Range(match.range(at: 1), in: html) else {
                continue
            }
            return String(html[capture])
        }
        return nil
    }

    private static func allCaptures(pattern: String, in html: String, group: Int = 1) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else {
            return []
        }
        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        return regex.matches(in: html, range: range).compactMap { match in
            guard match.numberOfRanges > group,
                  let capture = Range(match.range(at: group), in: html) else {
                return nil
            }
            return String(html[capture])
        }
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

    private static func titleTag(fromHTML html: String) -> String? {
        elementText(pattern: #"<title\b[^>]*>(.*?)</title>"#, in: html)
    }

    private static func narouMetadata(
        seriesTitle: String,
        ncode: String,
        author: String,
        episodeCount: Int? = nil,
        textCount: Int? = nil,
        listedEpisodeCount: Int? = nil,
        listPageCount: Int? = nil
    ) -> [String: String] {
        DownloadMetadata.clean([
            "series": seriesTitle,
            "category": seriesTitle,
            "type": "text",
            "media_type": "text",
            "work_id": ncode,
            "ncode": ncode,
            "gallery_id": ncode,
            "episode_count": episodeCount.map(String.init) ?? "",
            "listed_episode_count": (listedEpisodeCount ?? episodeCount).map(String.init) ?? "",
            "resolved_episode_count": episodeCount.map(String.init) ?? "",
            "media_count": textCount.map(String.init) ?? "",
            "resolved_media_count": textCount.map(String.init) ?? "",
            "text_count": textCount.map(String.init) ?? "",
            "list_page_count": listPageCount.map(String.init) ?? "",
            "artist": author,
            "author": author,
            "creator": author,
            "uploader": author,
            "channel": author
        ])
    }

    private static func chapterMetadata(seriesTitle: String, chapterTitle: String, ncode: String, author: String, pageURL: URL, localURL: URL, number: Int) -> [String: String] {
        let chapterID = String(number)
        return DownloadMetadata.clean([
            "series": seriesTitle,
            "category": seriesTitle,
            "episode": chapterTitle,
            "chapter": chapterTitle,
            "type": "text",
            "media_type": "text",
            "work_id": ncode,
            "ncode": ncode,
            "episode_id": chapterID,
            "chapter_id": chapterID,
            "gallery_id": ncode,
            "id": chapterID,
            "page": chapterID,
            "position": chapterID,
            "format": "txt",
            "media_format": "txt",
            "text_url": pageURL.absoluteString,
            "media_url": pageURL.absoluteString,
            "source_url": pageURL.absoluteString,
            "page_url": pageURL.absoluteString,
            "file_url": localURL.absoluteString,
            "artist": author,
            "author": author,
            "creator": author,
            "uploader": author,
            "channel": author,
            "site": "Narou",
            "title": chapterTitle
        ])
    }

    private static func cleanTitle(_ raw: String, fallback: String) -> String {
        var title = decodeHTML(stripTags(raw))
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmed
        for suffix in [" - ncode.syosetu.com", " | ncode.syosetu.com", " - syosetu.com"] {
            if title.lowercased().hasSuffix(suffix.lowercased()) {
                title.removeLast(suffix.count)
                title = title.trimmed
            }
        }
        return title.isEmpty ? fallback : title.sanitizedFilename(maxLength: 120)
    }

    private static func cleanAuthor(_ raw: String) -> String {
        var author = decodeHTML(stripTags(raw))
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmed
        for prefix in ["作者：", "作者:", "Author:", "Author："] {
            if author.hasPrefix(prefix) {
                author.removeFirst(prefix.count)
                author = author.trimmed
            }
        }
        return author.sanitizedFilename(maxLength: 120)
    }

    private static func stripTags(_ text: String) -> String {
        text.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
    }

    private static func decodeHTML(_ text: String) -> String {
        var output = text
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&apos;", with: "'")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&nbsp;", with: " ")

        guard let numericRegex = try? NSRegularExpression(pattern: #"&#(x?[0-9A-Fa-f]+);"#) else {
            return output
        }
        let matches = numericRegex.matches(in: output, range: NSRange(output.startIndex..<output.endIndex, in: output)).reversed()
        for match in matches {
            guard let whole = Range(match.range(at: 0), in: output),
                  let digitsRange = Range(match.range(at: 1), in: output) else {
                continue
            }
            let digits = String(output[digitsRange])
            let radix = digits.lowercased().hasPrefix("x") ? 16 : 10
            let value = radix == 16 ? String(digits.dropFirst()) : digits
            if let scalarValue = UInt32(value, radix: radix),
               let scalar = UnicodeScalar(scalarValue) {
                output.replaceSubrange(whole, with: String(Character(scalar)))
            }
        }
        return output
    }

    private static func isSupportedHost(_ host: String) -> Bool {
        host == "ncode.syosetu.com" ||
            host == "novel18.syosetu.com" ||
            host == "ncode.syosetu.test" ||
            host == "novel18.syosetu.test"
    }
}

import Foundation

final class HamelnResolver {
    private static let defaultUserAgent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/72.0.3626.119 Safari/537.36"

    func canResolve(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased(),
              Self.isSupportedHost(host),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            return false
        }
        return Self.novelID(from: url) != nil
    }

    func resolve(
        _ url: URL,
        headers: HTTPRequestOptions = HTTPRequestOptions(),
        assetLimit: Int? = nil
    ) async throws -> ResolvedDownload {
        let userAgent = headers.userAgent ?? Self.defaultUserAgent
        let html = try await HTTPClient.shared.string(from: url, referer: headers.referer, userAgent: userAgent)

        if Self.pageNumber(from: url) != nil {
            return try Self.resolvedEpisodeDownload(fromHTML: html, pageURL: url)
        }

        guard let novelID = Self.novelID(from: url) else {
            throw NativeDownloadError.invalidURL(url.absoluteString)
        }

        let title = Self.seriesTitle(fromHTML: html, pageURL: url, novelID: novelID)
        let author = Self.authorName(fromHTML: html)
        let outputTitle = Self.seriesOutputTitle(title: title, author: author)
        let synopsis = Self.seriesSynopsis(fromHTML: html)
        let listedEpisodeURLs = Self.episodeURLs(fromHTML: html, novelID: novelID, baseURL: url)
        let finiteAssetLimit = assetLimit.flatMap { $0 > 0 ? $0 : nil }
        let episodeURLs = finiteAssetLimit.map { Array(listedEpisodeURLs.prefix($0)) } ?? listedEpisodeURLs
        guard !episodeURLs.isEmpty else {
            return try Self.resolvedEpisodeDownload(fromHTML: html, pageURL: url, seriesTitle: title, index: 1)
        }

        let temporaryDirectory = try Self.makeTemporaryTextDirectory()
        var assets: [ResolvedAsset] = []
        do {
            for (offset, episodeURL) in episodeURLs.enumerated() {
                try Task.checkCancellation()
                let episodeHTML = try await HTTPClient.shared.string(from: episodeURL, referer: url.absoluteString, userAgent: userAgent)
                let asset = try Self.episodeAsset(
                    fromHTML: episodeHTML,
                    pageURL: episodeURL,
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

        return ResolvedDownload(
            title: outputTitle,
            folderName: outputTitle,
            assets: assets,
            metadata: Self.hamelnMetadata(
                seriesTitle: title,
                novelID: novelID,
                author: author,
                episodeCount: assets.count,
                textCount: assets.count,
                listedEpisodeCount: listedEpisodeURLs.count
            ),
            textMergePlan: Self.mergedTextPlan(
                title: title,
                author: author,
                synopsis: synopsis,
                outputTitle: outputTitle
            ),
            temporaryAssetDirectories: [temporaryDirectory]
        )
    }

    static func resolvedEpisodeDownload(fromHTML html: String, pageURL: URL, seriesTitle: String? = nil, index: Int? = nil) throws -> ResolvedDownload {
        let novelID = novelID(from: pageURL) ?? "novel"
        let title = seriesTitle ?? Self.seriesTitle(fromHTML: html, pageURL: pageURL, novelID: novelID)
        let asset = try episodeAsset(fromHTML: html, pageURL: pageURL, seriesTitle: title, index: index)
        let episode = episodeTitle(fromHTML: html, pageURL: pageURL)

        return ResolvedDownload(
            title: "\(title) - \(episode)".sanitizedFilename(maxLength: 120),
            folderName: "Hameln \(title)".sanitizedFilename(maxLength: 120),
            assets: [asset],
            metadata: hamelnMetadata(seriesTitle: title, novelID: novelID, author: authorName(fromHTML: html), episodeCount: 1, textCount: 1),
            temporaryAssetDirectories: [asset.remoteURL.deletingLastPathComponent()]
        )
    }

    static func episodeAsset(
        fromHTML html: String,
        pageURL: URL,
        seriesTitle: String,
        index: Int? = nil,
        temporaryDirectory: URL? = nil
    ) throws -> ResolvedAsset {
        let episode = episodeTitle(fromHTML: html, pageURL: pageURL)
        let body = episodeBodyText(fromHTML: html)
        guard !body.trimmed.isEmpty else {
            throw NativeDownloadError.noFiles
        }

        let author = authorName(fromHTML: html)
        let number = index ?? pageNumber(from: pageURL) ?? 1
        let heading = index == nil ? episode : String(format: "[%04d] %@", number, episode)
        let content = episodeText(heading: heading, story: body)
        let filename = "\(heading).txt".sanitizedFilename(maxLength: 180)
        let localURL = try writeTemporaryTextFile(
            filename: filename,
            content: content,
            directory: temporaryDirectory
        )
        return ResolvedAsset(
            remoteURL: localURL,
            filename: filename,
            metadata: episodeMetadata(
                seriesTitle: seriesTitle,
                episodeTitle: episode,
                novelID: novelID(from: pageURL) ?? "",
                author: author,
                pageURL: pageURL,
                localURL: localURL,
                number: number
            ),
            referer: pageURL.absoluteString
        )
    }

    static func novelID(from url: URL) -> String? {
        let parts = pathParts(from: url)
        guard let index = parts.firstIndex(where: { $0.lowercased() == "novel" }),
              index + 1 < parts.count else {
            return nil
        }
        let novelID = parts[index + 1]
        return novelID.isEmpty ? nil : novelID
    }

    static func pageNumber(from url: URL) -> Int? {
        let parts = pathParts(from: url)
        guard let index = parts.firstIndex(where: { $0.lowercased() == "novel" }),
              index + 2 < parts.count else {
            return nil
        }
        let raw = parts[index + 2]
        let cleaned = raw.replacingOccurrences(of: #"\.html?$"#, with: "", options: [.regularExpression, .caseInsensitive])
        return Int(cleaned)
    }

    static func episodeURLs(fromHTML html: String, novelID: String, baseURL: URL) -> [URL] {
        var results: [URL] = []
        var seen = Set<String>()

        for href in anchorHREFs(fromHTML: html) {
            guard let url = absoluteURL(href, baseURL: baseURL),
                  Self.novelID(from: url) == novelID,
                  pageNumber(from: url) != nil else {
                continue
            }
            let normalized = URLIdentity.normalize(url.absoluteString)
            guard !seen.contains(normalized) else { continue }
            seen.insert(normalized)
            results.append(url)
        }

        return results.sorted { lhs, rhs in
            (pageNumber(from: lhs) ?? 0) < (pageNumber(from: rhs) ?? 0)
        }
    }

    static func seriesTitle(fromHTML html: String, pageURL: URL, novelID: String) -> String {
        let title = elementText(pattern: #"<span\b[^>]*\bitemprop\s*=\s*["']name["'][^>]*>(.*?)</span>"#, in: html) ??
            elementText(pattern: #"<(?:h1|h2|div|span)\b[^>]*\bclass\s*=\s*["'][^"']*(?:novel_title|section3|title)[^"']*["'][^>]*>(.*?)</(?:h1|h2|div|span)>"#, in: html) ??
            metaContent(from: html, names: ["og:title", "twitter:title"]) ??
            titleTag(fromHTML: html) ??
            novelID
        return cleanTitle(title, fallback: "Hameln \(novelID)")
    }

    static func episodeTitle(fromHTML html: String, pageURL: URL) -> String {
        let title = elementText(pattern: #"<(?:h1|h2|div|span)\b[^>]*\bclass\s*=\s*["'][^"']*(?:novel_subtitle|subtitle|chapter_title|ss)[^"']*["'][^>]*>(.*?)</(?:h1|h2|div|span)>"#, in: html) ??
            metaContent(from: html, names: ["og:title", "twitter:title"]) ??
            titleTag(fromHTML: html) ??
            pageNumber(from: pageURL).map { "Episode \($0)" } ??
            pageURL.lastPathComponent
        return cleanTitle(title, fallback: "Episode \(pageNumber(from: pageURL) ?? 1)")
    }

    static func episodeBodyText(fromHTML html: String) -> String {
        let parts = [
            bodySection(fromHTML: html, idOrClass: "maegaki"),
            bodySection(fromHTML: html, idOrClass: "honbun"),
            bodySection(fromHTML: html, idOrClass: "atogaki")
        ].compactMap { section -> String? in
            guard let section, !section.trimmed.isEmpty else { return nil }
            return section
        }

        if !parts.isEmpty {
            return parts.joined(separator: "\n\n────────────────────────────────\n\n")
        }

        return bodySection(fromHTML: html, idOrClass: "novel_ex") ??
            bodySection(fromHTML: html, idOrClass: "story") ??
            ""
    }

    static func episodeText(heading: String, story: String) -> String {
        """
        ────────────────────────────────

          ◆  \(heading)

        ────────────────────────────────


        \(story)
        """
    }

    static func seriesOutputTitle(title: String, author: String) -> String {
        let authorPrefix = author.isEmpty ? "" : "[\(author)] "
        return "\(authorPrefix)\(title)".sanitizedFilename(maxLength: 120)
    }

    static func seriesSynopsis(fromHTML html: String) -> String {
        if let explicit = bodySection(fromHTML: html, idOrClass: "novel_ex"), !explicit.isEmpty {
            return explicit
        }

        guard let regex = try? NSRegularExpression(
            pattern: #"<div\b([^>]*)>(.*?)</div>"#,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        ) else {
            return ""
        }
        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        let sections = regex.matches(in: html, range: range).compactMap { match -> String? in
            guard let attributesRange = Range(match.range(at: 1), in: html),
                  let bodyRange = Range(match.range(at: 2), in: html) else {
                return nil
            }
            let attributes = attributeValues(from: String(html[attributesRange]))
            let classes = Set((attributes["class"] ?? "").split(whereSeparator: \.isWhitespace).map(String.init))
            guard classes.contains("ss"), attributes["id"]?.lowercased() != "fmenu" else {
                return nil
            }
            let text = normalizedText(fromHTMLFragment: String(html[bodyRange]))
            return text.isEmpty ? nil : text
        }
        guard !sections.isEmpty else { return "" }
        return sections.count >= 2 ? sections[sections.count - 2] : sections[0]
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

    private static func bodySection(fromHTML html: String, idOrClass: String) -> String? {
        let raw = firstCapture(patterns: [
            #"<(?:div|section|article)\b[^>]*\bid\s*=\s*["']\#(idOrClass)["'][^>]*>(.*?)</(?:div|section|article)>"#,
            #"<(?:div|section|article)\b[^>]*\bclass\s*=\s*["'][^"']*\#(idOrClass)[^"']*["'][^>]*>(.*?)</(?:div|section|article)>"#
        ], in: html)
        guard let raw else { return nil }
        return normalizedText(fromHTMLFragment: raw)
    }

    private static func normalizedText(fromHTMLFragment raw: String) -> String {
        let cleaned = raw
            .replacingOccurrences(of: #"<script\b[^>]*>.*?</script>"#, with: "", options: [.regularExpression, .caseInsensitive], range: nil)
            .replacingOccurrences(of: #"<style\b[^>]*>.*?</style>"#, with: "", options: [.regularExpression, .caseInsensitive], range: nil)
            .replacingOccurrences(of: #"<rt\b[^>]*>.*?</rt>"#, with: "", options: [.regularExpression, .caseInsensitive], range: nil)
            .replacingOccurrences(of: #"<rp\b[^>]*>.*?</rp>"#, with: "", options: [.regularExpression, .caseInsensitive], range: nil)
            .replacingOccurrences(of: #"(?i)</?ruby\b[^>]*>"#, with: "", options: .regularExpression)

        let withBreaks = cleaned
            .replacingOccurrences(of: #"(?i)<br\s*/?>"#, with: "\n", options: .regularExpression)
            .replacingOccurrences(of: #"(?i)</p>"#, with: "\n\n", options: .regularExpression)
            .replacingOccurrences(of: #"(?i)</div>"#, with: "\n", options: .regularExpression)
            .replacingOccurrences(of: #"(?i)</li>"#, with: "\n", options: .regularExpression)

        let stripped = decodeHTML(stripTags(withBreaks))
        let lines = stripped
            .components(separatedBy: .newlines)
            .map { $0.replacingOccurrences(of: "[\\t ]+", with: " ", options: .regularExpression).trimmed }

        var output: [String] = []
        var previousBlank = false
        for line in lines {
            if line.isEmpty {
                if !previousBlank && !output.isEmpty {
                    output.append("")
                }
                previousBlank = true
            } else {
                output.append(line)
                previousBlank = false
            }
        }
        while output.last == "" {
            output.removeLast()
        }
        return output.joined(separator: "\n")
    }

    private static func authorName(fromHTML html: String) -> String {
        let author = firstCapture(patterns: [
            #"<[^>]+\bitemprop\s*=\s*["']author["'][^>]*>.*?<[^>]+\bitemprop\s*=\s*["']name["'][^>]*>(.*?)</[^>]+>.*?</[^>]+>"#,
            #"<[^>]+\bitemprop\s*=\s*["']author["'][^>]*>(.*?)</[^>]+>"#,
            #"<[^>]+\bclass\s*=\s*["'][^"']*(?:author|writer)[^"']*["'][^>]*>(.*?)</[^>]+>"#
        ], in: html) ?? ""
        return cleanTitle(author, fallback: "")
    }

    private static func hamelnMetadata(
        seriesTitle: String,
        novelID: String,
        author: String,
        episodeCount: Int? = nil,
        textCount: Int? = nil,
        listedEpisodeCount: Int? = nil
    ) -> [String: String] {
        DownloadMetadata.clean([
            "series": seriesTitle,
            "category": seriesTitle,
            "type": "text",
            "media_type": "text",
            "work_id": novelID,
            "novel_id": novelID,
            "gallery_id": novelID,
            "episode_count": episodeCount.map(String.init) ?? "",
            "listed_episode_count": (listedEpisodeCount ?? episodeCount).map(String.init) ?? "",
            "resolved_episode_count": episodeCount.map(String.init) ?? "",
            "media_count": textCount.map(String.init) ?? "",
            "resolved_media_count": textCount.map(String.init) ?? "",
            "text_count": textCount.map(String.init) ?? "",
            "artist": author,
            "author": author,
            "creator": author,
            "uploader": author,
            "channel": author
        ])
    }

    private static func episodeMetadata(seriesTitle: String, episodeTitle: String, novelID: String, author: String, pageURL: URL, localURL: URL, number: Int) -> [String: String] {
        let page = String(number)
        return DownloadMetadata.clean([
            "series": seriesTitle,
            "category": seriesTitle,
            "episode": episodeTitle,
            "chapter": episodeTitle,
            "type": "text",
            "media_type": "text",
            "work_id": novelID,
            "novel_id": novelID,
            "episode_id": page,
            "chapter_id": page,
            "gallery_id": novelID,
            "id": page,
            "page": page,
            "position": page,
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
            "site": "Hameln",
            "title": episodeTitle
        ])
    }

    private static func makeTemporaryTextDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("HitomiBadayo-Hameln-\(UUID().uuidString)", isDirectory: true)
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

    private static func cleanTitle(_ raw: String, fallback: String = "Hameln") -> String {
        var title = decodeHTML(stripTags(raw))
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmed
        for suffix in [" - ハーメルン", " | ハーメルン", " - Hameln", " | Hameln"] {
            if title.lowercased().hasSuffix(suffix.lowercased()) {
                title.removeLast(suffix.count)
                title = title.trimmed
            }
        }
        return title.isEmpty ? fallback : title.sanitizedFilename(maxLength: 120)
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

        guard let regex = try? NSRegularExpression(pattern: #"&#(x?[0-9A-Fa-f]+);"#) else {
            return output
        }
        let matches = regex.matches(in: output, range: NSRange(output.startIndex..<output.endIndex, in: output)).reversed()
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
        host == "syosetu.org" ||
            host == "www.syosetu.org" ||
            host == "syosetu.test" ||
            host == "www.syosetu.test"
    }
}

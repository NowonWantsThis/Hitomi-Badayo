import Foundation

struct KakuyomuEpisode {
    var id: String
    var title: String?
    var publishedAt: String?
}

private struct KakuyomuListedEpisode {
    var url: URL
    var id: String
    var title: String?
    var date: String?
}

final class KakuyomuResolver {
    func canResolve(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased(),
              Self.isSupportedHost(host),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            return false
        }
        return Self.workID(from: url) != nil
    }

    func resolve(
        _ url: URL,
        headers: HTTPRequestOptions = HTTPRequestOptions(),
        assetLimit: Int? = nil
    ) async throws -> ResolvedDownload {
        let html = try await HTTPClient.shared.string(from: url, referer: headers.referer, userAgent: headers.userAgent)

        if Self.episodeID(from: url) != nil {
            return try Self.resolvedEpisodeDownload(fromHTML: html, pageURL: url)
        }

        guard let workID = Self.workID(from: url) else {
            throw NativeDownloadError.invalidURL(url.absoluteString)
        }

        let title = Self.seriesTitle(fromHTML: html, pageURL: url, workID: workID)
        let author = Self.authorName(fromHTML: html, workID: workID)
        let outputTitle = Self.seriesOutputTitle(title: title, author: author)
        let description = Self.seriesDescription(fromHTML: html, workID: workID)
        let listedEpisodes = Self.listedEpisodes(fromHTML: html, workID: workID, baseURL: url)
        let finiteAssetLimit = assetLimit.flatMap { $0 > 0 ? $0 : nil }
        let episodes = finiteAssetLimit.map { Array(listedEpisodes.prefix($0)) } ?? listedEpisodes
        guard !episodes.isEmpty else {
            return try Self.resolvedEpisodeDownload(fromHTML: html, pageURL: url, seriesTitle: title, index: 1)
        }

        let temporaryDirectory = try Self.makeTemporaryTextDirectory()
        var assets: [ResolvedAsset] = []
        do {
            for (offset, episode) in episodes.enumerated() {
                try Task.checkCancellation()
                let episodeHTML = try await HTTPClient.shared.string(from: episode.url, referer: url.absoluteString, userAgent: headers.userAgent)
                let asset = try Self.episodeAsset(
                    fromHTML: episodeHTML,
                    pageURL: episode.url,
                    seriesTitle: title,
                    index: offset + 1,
                    listedTitle: episode.title,
                    publishedDate: episode.date,
                    seriesAuthor: author,
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
            metadata: Self.kakuyomuMetadata(
                seriesTitle: title,
                workID: workID,
                author: author,
                episodeCount: assets.count,
                textCount: assets.count,
                listedEpisodeCount: listedEpisodes.count
            ),
            textMergePlan: Self.mergedTextPlan(
                title: title,
                author: author,
                description: description,
                outputTitle: outputTitle
            ),
            temporaryAssetDirectories: [temporaryDirectory]
        )
    }

    static func resolvedEpisodeDownload(fromHTML html: String, pageURL: URL, seriesTitle: String? = nil, index: Int? = nil) throws -> ResolvedDownload {
        let workID = workID(from: pageURL) ?? "work"
        let title = seriesTitle ?? Self.seriesTitle(fromHTML: html, pageURL: pageURL, workID: workID)
        let asset = try episodeAsset(fromHTML: html, pageURL: pageURL, seriesTitle: title, index: index)
        let episode = episodeTitle(fromHTML: html, pageURL: pageURL)

        return ResolvedDownload(
            title: "\(title) - \(episode)".sanitizedFilename(maxLength: 120),
            folderName: "Kakuyomu \(title)".sanitizedFilename(maxLength: 120),
            assets: [asset],
            metadata: kakuyomuMetadata(seriesTitle: title, workID: workID, author: authorName(fromHTML: html, workID: workID), episodeCount: 1, textCount: 1),
            temporaryAssetDirectories: [asset.remoteURL.deletingLastPathComponent()]
        )
    }

    static func episodeAsset(
        fromHTML html: String,
        pageURL: URL,
        seriesTitle: String,
        index: Int? = nil,
        listedTitle: String? = nil,
        publishedDate: String? = nil,
        seriesAuthor: String? = nil,
        temporaryDirectory: URL? = nil
    ) throws -> ResolvedAsset {
        let episode = cleanTitle(listedTitle ?? episodeTitle(fromHTML: html, pageURL: pageURL), fallback: episodeID(from: pageURL) ?? "Episode")
        let body = episodeBodyText(fromHTML: html)
        guard !body.trimmed.isEmpty else {
            throw NativeDownloadError.noFiles
        }

        let author = seriesAuthor ?? authorName(fromHTML: html, workID: workID(from: pageURL))
        let number = index ?? episodeNumber(from: pageURL) ?? 1
        let heading = index == nil ? episode : String(format: "[%04d] %@", number, episode)
        let date = publishedDate ?? episodePublishedDate(fromHTML: html, episodeID: episodeID(from: pageURL))
        let content = episodeText(heading: heading, date: date, story: body)
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
                workID: workID(from: pageURL) ?? "",
                episodeID: episodeID(from: pageURL) ?? String(number),
                author: author,
                pageURL: pageURL,
                localURL: localURL,
                number: number,
                publishedDate: date
            ),
            referer: pageURL.absoluteString
        )
    }

    static func workID(from url: URL) -> String? {
        let parts = pathParts(from: url)
        guard let index = parts.firstIndex(where: { $0.lowercased() == "works" }),
              index + 1 < parts.count else {
            return nil
        }
        let workID = parts[index + 1]
        return workID.isEmpty ? nil : workID
    }

    static func episodeID(from url: URL) -> String? {
        let parts = pathParts(from: url)
        guard let index = parts.firstIndex(where: { $0.lowercased() == "episodes" }),
              index + 1 < parts.count else {
            return nil
        }
        let episodeID = parts[index + 1]
        return episodeID.isEmpty ? nil : episodeID
    }

    static func episodeNumber(from url: URL) -> Int? {
        guard let episodeID = episodeID(from: url) else { return nil }
        return Int(episodeID.suffix(6))
    }

    static func episodeURLs(fromHTML html: String, workID: String, baseURL: URL) -> [URL] {
        listedEpisodes(fromHTML: html, workID: workID, baseURL: baseURL).map(\.url)
    }

    private static func listedEpisodes(fromHTML html: String, workID: String, baseURL: URL) -> [KakuyomuListedEpisode] {
        var results: [KakuyomuListedEpisode] = []
        var indicesByIdentity: [String: Int] = [:]

        func append(_ episode: KakuyomuListedEpisode, replacingDetails: Bool = false) {
            guard Self.workID(from: episode.url) == workID,
                  episodeID(from: episode.url) != nil else {
                return
            }
            let identity = URLIdentity.normalize(episode.url.absoluteString)
            if let index = indicesByIdentity[identity] {
                if replacingDetails {
                    if let title = episode.title, !title.trimmed.isEmpty {
                        results[index].title = title
                    }
                    if let date = episode.date, !date.trimmed.isEmpty {
                        results[index].date = date
                    }
                }
                return
            }
            indicesByIdentity[identity] = results.count
            results.append(episode)
        }

        if let nextData = nextDataObject(fromHTML: html) {
            for episode in orderedEpisodeRecords(from: nextData, workID: workID) {
                guard let episodeURL = URL(
                    string: "/works/\(workID)/episodes/\(episode.id)",
                    relativeTo: baseURL
                )?.absoluteURL else {
                    continue
                }
                append(KakuyomuListedEpisode(
                    url: episodeURL,
                    id: episode.id,
                    title: episode.title,
                    date: episode.publishedAt
                ))
            }
        }

        for episode in legacyListedEpisodes(fromHTML: html, workID: workID, baseURL: baseURL) {
            append(episode, replacingDetails: true)
        }

        for href in anchorHREFs(fromHTML: html) {
            guard let episodeURL = absoluteURL(href, baseURL: baseURL),
                  let id = episodeID(from: episodeURL) else {
                continue
            }
            append(KakuyomuListedEpisode(url: episodeURL, id: id, title: nil, date: nil))
        }

        return results
    }

    private static func legacyListedEpisodes(fromHTML html: String, workID: String, baseURL: URL) -> [KakuyomuListedEpisode] {
        guard let regex = try? NSRegularExpression(
            pattern: #"<a\b([^>]*)>(.*?)</a>"#,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        ) else {
            return []
        }

        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        return regex.matches(in: html, range: range).compactMap { match in
            guard let attributesRange = Range(match.range(at: 1), in: html),
                  let bodyRange = Range(match.range(at: 2), in: html) else {
                return nil
            }
            let attributes = attributeValues(from: String(html[attributesRange]))
            guard let href = attributes["href"],
                  let episodeURL = absoluteURL(href, baseURL: baseURL),
                  Self.workID(from: episodeURL) == workID,
                  let id = episodeID(from: episodeURL) else {
                return nil
            }

            let body = String(html[bodyRange])
            let titleFragment = firstCapture(patterns: [
                #"<span\b[^>]*\bclass\s*=\s*["'][^"']*widget-toc-episode-titleLabel[^"']*["'][^>]*>(.*?)</span>"#
            ], in: body)
            let dateFragment = firstCapture(patterns: [
                #"<time\b[^>]*\bclass\s*=\s*["'][^"']*widget-toc-episode-datePublished[^"']*["'][^>]*>(.*?)</time>"#,
                #"<time\b[^>]*>(.*?)</time>"#
            ], in: body)
            let title = titleFragment.map(normalizedInlineText).flatMap { $0.isEmpty ? nil : $0 }
            let date = dateFragment.map(normalizedInlineText).flatMap { $0.isEmpty ? nil : $0 }
            return KakuyomuListedEpisode(url: episodeURL, id: id, title: title, date: date)
        }
    }

    static func seriesTitle(fromHTML html: String, pageURL: URL, workID: String) -> String {
        let title = workTitleFromNextData(html: html, workID: workID) ??
            elementText(pattern: #"<(?:h1|div|span)\b[^>]*\bclass\s*=\s*["'][^"']*(?:widget-workTitle|workTitle|heading_title)[^"']*["'][^>]*>(.*?)</(?:h1|div|span)>"#, in: html) ??
            metaContent(from: html, names: ["og:title", "twitter:title"]) ??
            titleTag(fromHTML: html) ??
            workID
        return cleanTitle(title, fallback: "Kakuyomu \(workID)")
    }

    static func episodeTitle(fromHTML html: String, pageURL: URL) -> String {
        let title = episodeID(from: pageURL).flatMap { episodeTitleFromNextData(html: html, episodeID: $0) } ??
            elementText(pattern: #"<(?:h1|p|div|span)\b[^>]*\bclass\s*=\s*["'][^"']*(?:widget-episodeTitle|episodeTitle|chapterTitle)[^"']*["'][^>]*>(.*?)</(?:h1|p|div|span)>"#, in: html) ??
            elementText(pattern: #"<h1\b[^>]*>(.*?)</h1>"#, in: html) ??
            episodeID(from: pageURL) ??
            pageURL.lastPathComponent
        return cleanTitle(title, fallback: "Episode \(episodeID(from: pageURL) ?? "1")")
    }

    static func episodeBodyText(fromHTML html: String) -> String {
        let bodyHTML = firstCapture(patterns: [
            #"<div\b[^>]*\bclass\s*=\s*["'][^"']*widget-episodeBody[^"']*["'][^>]*>(.*?)</div>"#,
            #"<section\b[^>]*\bclass\s*=\s*["'][^"']*(?:widget-episodeBody|episodeBody)[^"']*["'][^>]*>(.*?)</section>"#,
            #"<article\b[^>]*>(.*?)</article>"#
        ], in: html) ?? ""

        let cleaned = bodyHTML
            .replacingOccurrences(of: #"<script\b[^>]*>.*?</script>"#, with: "", options: [.regularExpression, .caseInsensitive], range: nil)
            .replacingOccurrences(of: #"<style\b[^>]*>.*?</style>"#, with: "", options: [.regularExpression, .caseInsensitive], range: nil)
            .replacingOccurrences(of: #"<rt\b[^>]*>.*?</rt>"#, with: "", options: [.regularExpression, .caseInsensitive], range: nil)
            .replacingOccurrences(of: #"<rp\b[^>]*>.*?</rp>"#, with: "", options: [.regularExpression, .caseInsensitive], range: nil)
            .replacingOccurrences(of: #"(?i)</?ruby\b[^>]*>"#, with: "", options: .regularExpression)

        let withBreaks = cleaned
            .replacingOccurrences(of: #"(?i)<br\s*/?>"#, with: "\n", options: .regularExpression)
            .replacingOccurrences(of: #"(?i)</p>"#, with: "\n", options: .regularExpression)
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

    static func episodeText(heading: String, date: String?, story: String) -> String {
        let trimmedDate = date?.trimmed ?? ""
        let headingLine = trimmedDate.isEmpty ? heading : "\(heading)        \(trimmedDate)"
        return """
        ────────────────────────────────

          ◆  \(headingLine)

        ────────────────────────────────


        \(story)
        """
    }

    static func seriesOutputTitle(title: String, author: String) -> String {
        let authorPrefix = author.isEmpty ? "" : "[\(author)] "
        return "\(authorPrefix)\(title)".sanitizedFilename(maxLength: 120)
    }

    static func seriesDescription(fromHTML html: String, workID: String) -> String {
        if let work = workDictionary(fromHTML: html, workID: workID) {
            let catchphrase = stringValue(work["catchphrase"]) ?? ""
            let introduction = stringValue(work["introduction"]) ?? ""
            return "  \(catchphrase)\(introduction.isEmpty ? "" : "\n\n\n\(introduction)")"
        }

        let catchphrase = firstCapture(patterns: [
            #"<span\b[^>]*\bid\s*=\s*["']catchphrase-body["'][^>]*>(.*?)</span>"#
        ], in: html).map(normalizedInlineText) ?? ""
        let introduction = firstCapture(patterns: [
            #"<p\b[^>]*\bid\s*=\s*["']introduction["'][^>]*>(.*?)</p>"#
        ], in: html).map(normalizedText) ?? ""
        guard !catchphrase.isEmpty || !introduction.isEmpty else { return "" }
        return "  \(catchphrase)\(introduction.isEmpty ? "" : "\n\n\n\(introduction)")"
    }

    static func mergedTextPlan(title: String, author: String, description: String, outputTitle: String) -> ResolvedTextMergePlan {
        var header = "    \(title)\n\n"
        if !author.isEmpty {
            header += "    作者：\(author)\n\n\n"
        }
        header += description
        return ResolvedTextMergePlan(
            outputFilename: "[merged] \(outputTitle).txt",
            header: header,
            separator: "\n\n\n\n"
        )
    }

    private static func episodePublishedDate(fromHTML html: String, episodeID: String?) -> String? {
        if let episodeID,
           let nextData = nextDataObject(fromHTML: html),
           let date = episodeRecords(from: nextData).first(where: { $0.id == episodeID })?.publishedAt {
            return date
        }
        if let date = metaContent(from: html, names: ["article:published_time", "datepublished"]) {
            return date
        }
        return firstCapture(patterns: [
            #"<time\b[^>]*\bclass\s*=\s*["'][^"']*(?:datePublished|published)[^"']*["'][^>]*>(.*?)</time>"#
        ], in: html).map(normalizedInlineText).flatMap { $0.isEmpty ? nil : $0 }
    }

    static func nextDataObject(fromHTML html: String) -> [String: Any]? {
        guard let raw = firstCapture(patterns: [
            #"<script\b[^>]*\bid\s*=\s*["']__NEXT_DATA__["'][^>]*>(.*?)</script>"#
        ], in: html) else {
            return nil
        }
        let json = decodeHTML(raw).trimmed
        guard let data = json.data(using: .utf8) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    static func episodeRecords(from value: Any) -> [KakuyomuEpisode] {
        var records: [KakuyomuEpisode] = []
        collectEpisodeRecords(in: value, keyHint: nil, results: &records)

        var seen = Set<String>()
        return records.filter { episode in
            guard !seen.contains(episode.id) else { return false }
            seen.insert(episode.id)
            return true
        }
    }

    private static func orderedEpisodeRecords(from nextData: [String: Any], workID: String) -> [KakuyomuEpisode] {
        let fallback = episodeRecords(from: nextData).sorted(by: episodeSort)
        guard let state = apolloState(from: nextData),
              let work = workDictionary(from: state, workID: workID),
              let tableOfContents = work["tableOfContents"] as? [Any] else {
            return fallback
        }

        var records: [KakuyomuEpisode] = []
        var seen = Set<String>()
        for tableReference in tableOfContents {
            guard let table = referencedDictionary(from: tableReference, state: state) else { continue }
            let references = (table["episodes"] as? [Any]) ?? (table["episodeUnions"] as? [Any]) ?? []
            for episodeReference in references {
                guard let dictionary = referencedDictionary(from: episodeReference, state: state),
                      let record = episodeRecord(from: dictionary, keyHint: referenceName(from: episodeReference)),
                      seen.insert(record.id).inserted else {
                    continue
                }
                records.append(record)
            }
        }
        return records.isEmpty ? fallback : records
    }

    private static func apolloState(from nextData: [String: Any]) -> [String: Any]? {
        guard let props = nextData["props"] as? [String: Any],
              let pageProps = props["pageProps"] as? [String: Any] else {
            return nil
        }
        return pageProps["__APOLLO_STATE__"] as? [String: Any]
    }

    private static func workDictionary(fromHTML html: String, workID: String) -> [String: Any]? {
        guard let nextData = nextDataObject(fromHTML: html),
              let state = apolloState(from: nextData) else {
            return nil
        }
        return workDictionary(from: state, workID: workID)
    }

    private static func workDictionary(from state: [String: Any], workID: String) -> [String: Any]? {
        if let work = state["Work:\(workID)"] as? [String: Any] {
            return work
        }
        return findDictionary(in: state, keyHint: nil, matching: { key, dictionary in
            if key == "Work:\(workID)" { return true }
            return stringValue(dictionary["id"]) == workID &&
                (dictionary["__typename"] as? String == "Work" || dictionary["title"] != nil)
        })
    }

    private static func referencedDictionary(from value: Any, state: [String: Any]) -> [String: Any]? {
        guard let dictionary = value as? [String: Any] else { return nil }
        if let reference = stringValue(dictionary["__ref"]),
           let referenced = state[reference] as? [String: Any] {
            return referenced
        }
        return dictionary
    }

    private static func referenceName(from value: Any) -> String? {
        (value as? [String: Any]).flatMap { stringValue($0["__ref"]) }
    }

    private static func workTitleFromNextData(html: String, workID: String) -> String? {
        guard let work = workDictionary(fromHTML: html, workID: workID) else {
            return nil
        }
        return stringValue(work["title"]) ??
            stringValue(work["activityName"]) ??
            stringValue(work["catchphrase"])
    }

    private static func episodeTitleFromNextData(html: String, episodeID: String) -> String? {
        guard let nextData = nextDataObject(fromHTML: html),
              let episode = findDictionary(in: nextData, keyHint: nil, matching: { key, dictionary in
                  if key == "Episode:\(episodeID)" { return true }
                  return stringValue(dictionary["id"]) == episodeID &&
                      (dictionary["__typename"] as? String == "Episode" || dictionary["title"] != nil || dictionary["subtitle"] != nil)
              }) else {
            return nil
        }
        return stringValue(episode["title"]) ?? stringValue(episode["subtitle"])
    }

    private static func authorName(fromHTML html: String, workID: String? = nil) -> String {
        if let nextData = nextDataObject(fromHTML: html) {
            let state = apolloState(from: nextData)
            let work: [String: Any]?
            if let workID, let state {
                work = workDictionary(from: state, workID: workID)
            } else {
                work = findDictionary(in: nextData, keyHint: nil, matching: { key, dictionary in
                    key.hasPrefix("Work:") || dictionary["__typename"] as? String == "Work"
                })
            }

            if let author = work?["author"] as? [String: Any] {
                let authorDictionary: [String: Any]
                if let reference = stringValue(author["__ref"]),
                   let referenced = state?[reference] as? [String: Any] {
                    authorDictionary = referenced
                } else {
                    authorDictionary = author
                }
                let name = stringValue(authorDictionary["activityName"]) ?? stringValue(authorDictionary["name"]) ?? ""
                if !name.isEmpty {
                    return cleanTitle(name, fallback: "")
                }
            }

            if let user = findDictionary(in: nextData, keyHint: nil, matching: { _, dictionary in
                dictionary["__typename"] as? String == "User" &&
                    (dictionary["activityName"] != nil || dictionary["name"] != nil)
            }) {
                return cleanTitle(stringValue(user["activityName"]) ?? stringValue(user["name"]) ?? "", fallback: "")
            }
        }

        let legacyAuthor = elementText(
            pattern: #"<(?:span|a)\b[^>]*\bid\s*=\s*["']workAuthor-activityName["'][^>]*>(.*?)</(?:span|a)>"#,
            in: html
        ) ?? ""
        return cleanTitle(legacyAuthor, fallback: "")
    }

    private static func kakuyomuMetadata(
        seriesTitle: String,
        workID: String,
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
            "work_id": workID,
            "gallery_id": workID,
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

    private static func episodeMetadata(
        seriesTitle: String,
        episodeTitle: String,
        workID: String,
        episodeID: String,
        author: String,
        pageURL: URL,
        localURL: URL,
        number: Int,
        publishedDate: String?
    ) -> [String: String] {
        return DownloadMetadata.clean([
            "series": seriesTitle,
            "category": seriesTitle,
            "episode": episodeTitle,
            "chapter": episodeTitle,
            "type": "text",
            "media_type": "text",
            "work_id": workID,
            "episode_id": episodeID,
            "chapter_id": episodeID,
            "gallery_id": episodeID.isEmpty ? workID : episodeID,
            "id": episodeID,
            "page": String(number),
            "position": String(number),
            "published_at": publishedDate ?? "",
            "date": publishedDate ?? "",
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
            "site": "Kakuyomu",
            "title": episodeTitle
        ])
    }

    private static func collectEpisodeRecords(in value: Any, keyHint: String?, results: inout [KakuyomuEpisode]) {
        if let dictionary = value as? [String: Any] {
            if let record = episodeRecord(from: dictionary, keyHint: keyHint) {
                results.append(record)
            }
            for (key, child) in dictionary {
                collectEpisodeRecords(in: child, keyHint: key, results: &results)
            }
        } else if let array = value as? [Any] {
            for child in array {
                collectEpisodeRecords(in: child, keyHint: nil, results: &results)
            }
        }
    }

    private static func episodeRecord(from dictionary: [String: Any], keyHint: String?) -> KakuyomuEpisode? {
        var id: String?
        if let keyHint, keyHint.hasPrefix("Episode:") {
            id = String(keyHint.dropFirst("Episode:".count))
        }
        id = id ?? stringValue(dictionary["id"]) ?? stringValue(dictionary["episodeId"])

        guard let id, !id.isEmpty else { return nil }
        let type = stringValue(dictionary["__typename"])
        let looksLikeEpisode = type == "Episode" ||
            keyHint?.hasPrefix("Episode:") == true ||
            dictionary["publishedAt"] != nil && (dictionary["title"] != nil || dictionary["subtitle"] != nil)
        guard looksLikeEpisode else { return nil }

        return KakuyomuEpisode(
            id: id,
            title: stringValue(dictionary["title"]) ?? stringValue(dictionary["subtitle"]),
            publishedAt: stringValue(dictionary["publishedAt"])
        )
    }

    private static func episodeSort(_ lhs: KakuyomuEpisode, _ rhs: KakuyomuEpisode) -> Bool {
        switch (lhs.publishedAt, rhs.publishedAt) {
        case let (left?, right?) where left != right:
            return left < right
        default:
            return lhs.id.localizedStandardCompare(rhs.id) == .orderedAscending
        }
    }

    private static func findDictionary(in value: Any, keyHint: String?, matching: (String, [String: Any]) -> Bool) -> [String: Any]? {
        if let dictionary = value as? [String: Any] {
            if let keyHint, matching(keyHint, dictionary) {
                return dictionary
            }
            if matching("", dictionary) {
                return dictionary
            }
            for (key, child) in dictionary {
                if let found = findDictionary(in: child, keyHint: key, matching: matching) {
                    return found
                }
            }
        } else if let array = value as? [Any] {
            for child in array {
                if let found = findDictionary(in: child, keyHint: keyHint, matching: matching) {
                    return found
                }
            }
        }
        return nil
    }

    private static func normalizedText(_ raw: String) -> String {
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
        let lines = decodeHTML(stripTags(withBreaks))
            .components(separatedBy: .newlines)
            .map { $0.replacingOccurrences(of: "[\\t ]+", with: " ", options: .regularExpression).trimmed }

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

    private static func normalizedInlineText(_ raw: String) -> String {
        decodeHTML(stripTags(raw))
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmed
    }

    private static func makeTemporaryTextDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("HitomiBadayo-Kakuyomu-\(UUID().uuidString)", isDirectory: true)
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

    private static func cleanTitle(_ raw: String, fallback: String = "Kakuyomu") -> String {
        var title = decodeHTML(stripTags(raw))
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmed
        for suffix in [" - カクヨム", " - Kakuyomu", " | カクヨム", " | Kakuyomu"] {
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

    private static func stringValue(_ value: Any?) -> String? {
        if let string = value as? String, !string.isEmpty { return string }
        if let int = value as? Int { return String(int) }
        if let double = value as? Double { return String(Int(double)) }
        return nil
    }

    private static func isSupportedHost(_ host: String) -> Bool {
        host == "kakuyomu.jp" ||
            host == "www.kakuyomu.jp" ||
            host == "kakuyomu.test" ||
            host == "www.kakuyomu.test"
    }
}

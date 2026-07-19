import Foundation

final class WaybackMachineResolver {
    private let maxConcurrentSnapshots = 5

    func canResolve(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased(),
              Self.isSupportedHost(host),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            return false
        }
        return Self.targetURL(from: url) != nil
    }

    func resolve(_ url: URL, headers: HTTPRequestOptions = HTTPRequestOptions()) async throws -> ResolvedDownload {
        guard let target = Self.targetURL(from: url) else {
            throw NativeDownloadError.unsupported("Unsupported Wayback Machine URL.")
        }

        let cdxData = try await HTTPClient.shared.data(
            from: Self.cdxAPIURL(targetURL: target, sourceURL: url),
            referer: headers.referer ?? url.absoluteString,
            userAgent: headers.userAgent
        )
        let snapshots = try Self.snapshots(fromCDXData: cdxData)
        guard !snapshots.isEmpty else {
            throw NativeDownloadError.noFiles
        }

        let snapshotHTMLs = try await Self.loadSnapshotHTMLs(
            snapshots,
            sourceURL: url,
            userAgent: headers.userAgent,
            maxConcurrent: maxConcurrentSnapshots
        )

        var resolved = try Self.resolvedDownload(fromSnapshots: snapshotHTMLs, targetURL: target, sourceURL: url)
        resolved.metadata["listed_snapshot_count"] = String(snapshots.count)
        resolved.metadata["resolved_snapshot_count"] = String(snapshotHTMLs.count)
        resolved.metadata["resolved_media_count"] = String(resolved.assets.count)
        return resolved
    }

    static func loadSnapshotHTMLs(
        _ snapshots: [(timestamp: String, original: URL)],
        sourceURL: URL,
        userAgent: String?,
        maxConcurrent: Int = 5
    ) async throws -> [(timestamp: String, original: URL, html: String)] {
        guard !snapshots.isEmpty else { return [] }
        let workerCount = min(max(1, maxConcurrent), snapshots.count)

        return try await withThrowingTaskGroup(of: (Int, String?).self) { group in
            for index in 0..<workerCount {
                let snapshot = snapshots[index]
                group.addTask {
                    try Task.checkCancellation()
                    let snapshotURL = archivedHTMLURL(
                        timestamp: snapshot.timestamp,
                        originalURL: snapshot.original,
                        sourceURL: sourceURL
                    )
                    do {
                        let html = try await HTTPClient.shared.string(
                            from: snapshotURL,
                            referer: sourceURL.absoluteString,
                            userAgent: userAgent
                        )
                        return (index, html)
                    } catch {
                        try Task.checkCancellation()
                        return (index, nil)
                    }
                }
            }

            var nextIndex = workerCount
            var loaded: [(index: Int, html: String)] = []
            while let (index, html) = try await group.next() {
                try Task.checkCancellation()
                if let html {
                    loaded.append((index, html))
                }
                if nextIndex < snapshots.count {
                    let scheduledIndex = nextIndex
                    let snapshot = snapshots[scheduledIndex]
                    group.addTask {
                        try Task.checkCancellation()
                        let snapshotURL = archivedHTMLURL(
                            timestamp: snapshot.timestamp,
                            originalURL: snapshot.original,
                            sourceURL: sourceURL
                        )
                        do {
                            let html = try await HTTPClient.shared.string(
                                from: snapshotURL,
                                referer: sourceURL.absoluteString,
                                userAgent: userAgent
                            )
                            return (scheduledIndex, html)
                        } catch {
                            try Task.checkCancellation()
                            return (scheduledIndex, nil)
                        }
                    }
                    nextIndex += 1
                }
            }

            return loaded.sorted { $0.index < $1.index }.map { entry in
                let snapshot = snapshots[entry.index]
                return (snapshot.timestamp, snapshot.original, entry.html)
            }
        }
    }

    static func targetURL(from url: URL) -> URL? {
        guard let host = url.host?.lowercased(), isSupportedHost(host) else { return nil }

        if url.path.lowercased() == "/cdx/search/cdx",
           let raw = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?
                .first(where: { $0.name.lowercased() == "url" })?
                .value {
            return normalizedTargetURL(raw)
        }

        let path = url.path.removingPercentEncoding ?? url.path
        guard path.hasPrefix("/web/") else { return nil }
        let rest = String(path.dropFirst("/web/".count))
        guard let slash = rest.firstIndex(of: "/") else { return nil }
        let raw = String(rest[rest.index(after: slash)...])
        return normalizedTargetURL(raw)
    }

    static func cdxAPIURL(targetURL: URL, sourceURL: URL) -> URL {
        var components = URLComponents()
        components.scheme = sourceURL.scheme ?? "https"
        components.host = canonicalHost(for: sourceURL)
        components.path = "/cdx/search/cdx"
        components.queryItems = [
            URLQueryItem(name: "url", value: targetURL.absoluteString),
            URLQueryItem(name: "output", value: "json"),
            URLQueryItem(name: "fl", value: "timestamp,original"),
            URLQueryItem(name: "filter", value: "mimetype:text/html"),
            URLQueryItem(name: "filter", value: "statuscode:200"),
            URLQueryItem(name: "collapse", value: "urlkey")
        ]
        return components.url!
    }

    static func snapshots(fromCDXData data: Data) throws -> [(timestamp: String, original: URL)] {
        let object = try JSONSerialization.jsonObject(with: data)
        var rows: [(timestamp: String, original: URL)] = []

        if let arrays = object as? [[Any]] {
            for row in arrays.dropFirst() {
                guard row.count >= 2,
                      let timestamp = stringValue(row[0]),
                      let originalRaw = stringValue(row[1]),
                      let original = normalizedTargetURL(originalRaw) else {
                    continue
                }
                rows.append((timestamp, original))
            }
        } else if let dicts = object as? [[String: Any]] {
            for row in dicts {
                guard let timestamp = stringValue(row["timestamp"]),
                      let originalRaw = stringValue(row["original"]),
                      let original = normalizedTargetURL(originalRaw) else {
                    continue
                }
                rows.append((timestamp, original))
            }
        }

        return rows
    }

    static func archivedHTMLURL(timestamp: String, originalURL: URL, sourceURL: URL) -> URL {
        archivedURL(timestamp: timestamp, mode: "id_", originalURL: originalURL, sourceURL: sourceURL)
    }

    static func archivedMediaURL(timestamp: String, originalURL: URL, sourceURL: URL) -> URL {
        archivedURL(timestamp: timestamp, mode: "im_", originalURL: originalURL, sourceURL: sourceURL)
    }

    static func resolvedDownload(
        fromSnapshots snapshots: [(timestamp: String, original: URL, html: String)],
        targetURL: URL,
        sourceURL: URL,
        limit: Int? = nil
    ) throws -> ResolvedDownload {
        var assets: [ResolvedAsset] = []
        var seenArchivedURLs = Set<String>()

        for snapshot in snapshots {
            for originalMedia in imageURLs(fromHTML: snapshot.html, originalPageURL: snapshot.original) {
                if let limit, assets.count >= limit { break }
                let archived = archivedMediaURL(timestamp: snapshot.timestamp, originalURL: originalMedia, sourceURL: sourceURL)
                let normalized = URLIdentity.normalize(archived.absoluteString)
                guard !seenArchivedURLs.contains(normalized) else { continue }
                seenArchivedURLs.insert(normalized)
                let archivedPage = archivedHTMLURL(timestamp: snapshot.timestamp, originalURL: snapshot.original, sourceURL: sourceURL)
                let index = assets.count + 1
                assets.append(ResolvedAsset(
                    remoteURL: archived,
                    filename: filename(for: originalMedia, index: index),
                    metadata: assetMetadata(
                        targetURL: targetURL,
                        sourceURL: sourceURL,
                        snapshotTimestamp: snapshot.timestamp,
                        originalPageURL: snapshot.original,
                        originalMediaURL: originalMedia,
                        archivedMediaURL: archived,
                        archivedPageURL: archivedPage,
                        index: index
                    ),
                    referer: archivedPage.absoluteString
                ))
            }
            if let limit, assets.count >= limit { break }
        }

        guard !assets.isEmpty else {
            throw NativeDownloadError.noFiles
        }

        let title = title(for: targetURL)
        return ResolvedDownload(
            title: title,
            folderName: "Wayback Machine \(title)".sanitizedFilename(maxLength: 120),
            assets: assets,
            metadata: DownloadMetadata.clean([
                "site": "Wayback Machine",
                "title": title,
                "host": targetURL.host ?? "",
                "url": targetURL.absoluteString,
                "target_url": targetURL.absoluteString,
                "source_url": sourceURL.absoluteString,
                "snapshot_count": String(snapshots.count),
                "media_count": String(assets.count),
                "image_count": String(assets.count),
                "type": "archive",
                "media_type": "image"
            ])
        )
    }

    static func imageURLs(fromHTML html: String, originalPageURL: URL) -> [URL] {
        let normalizedHTML = decodeHTML(html).replacingOccurrences(of: #"\/"#, with: "/")
        var candidates: [String] = []
        candidates.append(contentsOf: tagAttributeCandidates(tag: "img", fromHTML: normalizedHTML, keys: [
            "data-original",
            "data-src",
            "data-lazy-src",
            "src"
        ]))
        candidates.append(contentsOf: srcsetCandidates(fromHTML: normalizedHTML))

        var urls: [URL] = []
        var seen = Set<String>()
        for candidate in candidates {
            guard let media = originalMediaURL(from: candidate, originalPageURL: originalPageURL),
                  isDownloadableImage(media) else {
                continue
            }
            let normalized = URLIdentity.normalize(media.absoluteString)
            guard !seen.contains(normalized) else { continue }
            seen.insert(normalized)
            urls.append(media)
        }
        return urls
    }

    private static func archivedURL(timestamp: String, mode: String, originalURL: URL, sourceURL: URL) -> URL {
        var components = URLComponents()
        components.scheme = sourceURL.scheme ?? "https"
        components.host = canonicalHost(for: sourceURL)
        components.path = "/web/\(timestamp)\(mode)/\(originalURL.absoluteString)"
        return components.url!
    }

    private static func originalMediaURL(from raw: String, originalPageURL: URL) -> URL? {
        var value = decodeHTML(raw)
            .replacingOccurrences(of: #"\/"#, with: "/")
            .trimmed
        guard !value.isEmpty,
              !value.lowercased().hasPrefix("data:"),
              !value.lowercased().hasPrefix("javascript:") else {
            return nil
        }

        if value.hasPrefix("//") {
            value = (originalPageURL.scheme ?? "https") + ":" + value
        }

        if let url = URL(string: value),
           let host = url.host?.lowercased(),
           isSupportedHost(host),
           let archivedOriginal = targetURL(from: url) {
            return archivedOriginal
        }

        return URL(string: value, relativeTo: originalPageURL)?.absoluteURL
    }

    private static func tagAttributeCandidates(tag: String, fromHTML html: String, keys: [String]) -> [String] {
        guard let regex = try? NSRegularExpression(
            pattern: #"<\#(tag)\b([^>]*)>"#,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        ) else {
            return []
        }
        var values: [String] = []
        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        for match in regex.matches(in: html, range: range) {
            guard let attrsRange = Range(match.range(at: 1), in: html) else { continue }
            let attributes = attributeValues(from: String(html[attrsRange]))
            for key in keys {
                if let value = attributes[key]?.trimmed, !value.isEmpty {
                    values.append(value)
                }
            }
        }
        return values
    }

    private static func srcsetCandidates(fromHTML html: String) -> [String] {
        tagAttributeCandidates(tag: "img", fromHTML: html, keys: ["data-srcset", "srcset"])
            .compactMap(bestSrcsetCandidate)
    }

    private static func bestSrcsetCandidate(_ srcset: String) -> String? {
        srcset
            .components(separatedBy: ",")
            .compactMap { part -> (url: String, score: Int)? in
                let pieces = part.trimmed.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
                guard let url = pieces.first else { return nil }
                let descriptor = pieces.dropFirst().first ?? ""
                let score: Int
                if descriptor.hasSuffix("w") {
                    score = Int(descriptor.dropLast()) ?? 0
                } else if descriptor.hasSuffix("x") {
                    score = Int((Double(descriptor.dropLast()) ?? 1) * 10_000)
                } else {
                    score = 0
                }
                return (url, score)
            }
            .max { $0.score < $1.score }?
            .url
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

    private static func normalizedTargetURL(_ raw: String) -> URL? {
        var value = decodeHTML(raw)
            .trimmingCharacters(in: CharacterSet(charactersIn: " \n\r\t/"))
        guard !value.isEmpty else { return nil }
        if !value.lowercased().hasPrefix("http://") && !value.lowercased().hasPrefix("https://") {
            value = "https://\(value)"
        }
        return URL(string: value)
    }

    private static func isDownloadableImage(_ url: URL) -> Bool {
        imageExtensions.contains(url.pathExtension.lowercased())
    }

    private static func filename(for url: URL, index: Int) -> String {
        let ext = url.pathExtension.trimmed.isEmpty ? "jpg" : url.pathExtension
        return String(format: "%04d.%@", index, ext).sanitizedFilename(maxLength: 180)
    }

    private static func assetMetadata(
        targetURL: URL,
        sourceURL: URL,
        snapshotTimestamp: String,
        originalPageURL: URL,
        originalMediaURL: URL,
        archivedMediaURL: URL,
        archivedPageURL: URL,
        index: Int
    ) -> [String: String] {
        let format = mediaFormat(for: originalMediaURL)
        return DownloadMetadata.clean([
            "site": "Wayback Machine",
            "series": targetURL.host ?? "",
            "category": "archive",
            "type": "image",
            "media_type": "image",
            "host": targetURL.host ?? "",
            "url": targetURL.absoluteString,
            "target_url": targetURL.absoluteString,
            "snapshot": snapshotTimestamp,
            "snapshot_timestamp": snapshotTimestamp,
            "snapshot_url": archivedPageURL.absoluteString,
            "original_page_url": originalPageURL.absoluteString,
            "archive_url": archivedMediaURL.absoluteString,
            "archived_url": archivedMediaURL.absoluteString,
            "original_url": originalMediaURL.absoluteString,
            "original_media_url": originalMediaURL.absoluteString,
            "source_url": originalMediaURL.absoluteString,
            "image_url": originalMediaURL.absoluteString,
            "media_url": archivedMediaURL.absoluteString,
            "page_url": archivedPageURL.absoluteString,
            "input_url": sourceURL.absoluteString,
            "page": String(index),
            "position": String(index),
            "format": format,
            "media_format": format,
            "title": originalMediaURL.lastPathComponent
        ])
    }

    private static func mediaFormat(for url: URL) -> String {
        let ext = url.pathExtension.lowercased()
        if ext == "jpeg" {
            return "jpg"
        }
        return ext.isEmpty ? "jpg" : ext
    }

    private static func title(for targetURL: URL) -> String {
        let host = targetURL.host ?? "archive"
        let path = targetURL.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let name = path.isEmpty ? host : "\(host) \(targetURL.lastPathComponent)"
        return name.sanitizedFilename(maxLength: 120)
    }

    private static func canonicalHost(for sourceURL: URL) -> String {
        let host = sourceURL.host?.lowercased() ?? "web.archive.org"
        return host.hasSuffix(".test") ? "web.archive.org.test" : "web.archive.org"
    }

    private static func isSupportedHost(_ host: String) -> Bool {
        host == "web.archive.org" ||
            host == "archive.org" ||
            host == "web.archive.org.test" ||
            host == "archive.org.test"
    }

    private static func stringValue(_ value: Any?) -> String? {
        if let string = value as? String {
            return string
        }
        if let number = value as? NSNumber {
            return number.stringValue
        }
        return nil
    }

    private static func decodeHTML(_ raw: String) -> String {
        var text = raw
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#34;", with: "\"")
            .replacingOccurrences(of: "&#x27;", with: "'")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&apos;", with: "'")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&nbsp;", with: " ")
        guard let regex = try? NSRegularExpression(pattern: #"&#(?:x([0-9A-Fa-f]+)|([0-9]+));"#) else {
            return text
        }
        let matches = regex.matches(in: text, range: NSRange(text.startIndex..<text.endIndex, in: text)).reversed()
        for match in matches {
            guard let whole = Range(match.range(at: 0), in: text) else { continue }
            let scalarValue: UInt32?
            if let hexRange = Range(match.range(at: 1), in: text) {
                scalarValue = UInt32(String(text[hexRange]), radix: 16)
            } else if let decimalRange = Range(match.range(at: 2), in: text) {
                scalarValue = UInt32(String(text[decimalRange]), radix: 10)
            } else {
                scalarValue = nil
            }
            if let scalarValue, let scalar = UnicodeScalar(scalarValue) {
                text.replaceSubrange(whole, with: String(Character(scalar)))
            }
        }
        return text
    }

    private static let imageExtensions: Set<String> = [
        "jpg",
        "jpeg",
        "png",
        "gif",
        "webp",
        "bmp"
    ]
}

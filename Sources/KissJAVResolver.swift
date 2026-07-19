import Foundation

struct KissJAVVideoCandidate: Equatable {
    var url: URL
    var resolution: Int
    var label: String
}

final class KissJAVResolver {
    static let originalSegmentSize: Int64 = 512 * 1024
    static let originalDefaultResolution = 4320

    private static let productionRoots = ["kissjav.com", "kissjav.li", "mrjav.net"]
    private static let fixtureRoots = ["kissjav.test", "mrjav.test"]

    func canResolve(_ url: URL) -> Bool {
        Self.canonicalURL(for: url) != nil
    }

    func resolve(
        _ url: URL,
        headers: HTTPRequestOptions = HTTPRequestOptions(),
        preferredResolution: String = ""
    ) async throws -> ResolvedDownload {
        guard let pageURL = Self.canonicalURL(for: url) else {
            throw NativeDownloadError.invalidURL(url.absoluteString)
        }
        let html = try await HTTPClient.shared.string(
            from: pageURL,
            referer: headers.referer,
            userAgent: headers.userAgent
        )
        return try Self.resolvedDownload(
            fromHTML: html,
            pageURL: pageURL,
            preferredResolution: preferredResolution,
            userAgent: headers.userAgent
        )
    }

    static func isSupportedHost(_ rawHost: String) -> Bool {
        let host = rawHost.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
        return (productionRoots + fixtureRoots).contains { root in
            host == root || host.hasSuffix(".\(root)")
        }
    }

    static func canonicalURL(for url: URL) -> URL? {
        guard let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = url.host,
              isSupportedHost(host),
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return nil
        }
        components.queryItems = nil
        components.fragment = nil
        return components.url
    }

    static func resolvedDownload(
        fromHTML html: String,
        pageURL: URL,
        preferredResolution: String = "",
        userAgent: String? = nil
    ) throws -> ResolvedDownload {
        let candidates = videoCandidates(fromHTML: html, pageURL: pageURL)
        guard let candidate = selectedCandidate(candidates, preferredResolution: preferredResolution) else {
            throw NativeDownloadError.noFiles
        }
        guard let title = elementText(named: "h1", in: html),
              let internalID = videoDataID(fromHTML: html),
              let thumbnail = openGraphImage(fromHTML: html, pageURL: pageURL) else {
            throw NativeDownloadError.unsupported("KissJAV page did not contain the original title, data-id, and thumbnail fields.")
        }

        let filename = "\(title) (\(internalID)).mp4".sanitizedFilename(maxLength: 180)
        let resolution = candidate.resolution > 0 ? "\(candidate.resolution)p" : ""
        let commonMetadata = DownloadMetadata.clean([
            "site": "KissJAV",
            "title": title,
            "series": title,
            "category": "video",
            "type": "video",
            "media_type": "video",
            "format": "mp4",
            "media_format": "mp4",
            "host": pageURL.host ?? "",
            "id": internalID,
            "video_id": internalID,
            "media_id": internalID,
            "gallery_id": internalID,
            "media_count": "1",
            "video_count": "1",
            "resolution": resolution,
            "quality": candidate.label,
            "thumbnail": thumbnail.absoluteString,
            "thumbnail_referer_disabled": "true",
            "video_url": candidate.url.absoluteString,
            "media_url": candidate.url.absoluteString,
            "url": pageURL.absoluteString,
            "source_url": pageURL.absoluteString,
            "page_url": pageURL.absoluteString,
            "segment_size": String(originalSegmentSize),
            "transfer": "http-range"
        ])
        var assetMetadata = commonMetadata
        assetMetadata["page"] = "1"
        assetMetadata["position"] = "1"
        assetMetadata["remote_segment_size"] = String(originalSegmentSize)

        return ResolvedDownload(
            title: title,
            folderName: "KissJAV \(title)".sanitizedFilename(maxLength: 120),
            assets: [
                ResolvedAsset(
                    remoteURL: candidate.url,
                    filename: filename,
                    metadata: assetMetadata,
                    referer: pageURL.absoluteString,
                    userAgent: userAgent
                )
            ],
            packageMode: .concatenate(outputFilename: filename),
            metadata: commonMetadata
        )
    }

    static func videoCandidates(fromHTML html: String, pageURL: URL) -> [KissJAVVideoCandidate] {
        guard let player = elementBody(named: "div", attribute: "id", value: "player-container-fluid", in: html) else {
            return []
        }
        return allTags(named: "source", in: player).compactMap { tag in
            guard let source = attributeValue("src", in: tag),
                  let url = absoluteURL(source, baseURL: pageURL) else {
                return nil
            }
            let label = attributeValue("title", in: tag) ?? ""
            let resolution = firstCapture(
                pattern: #"([0-9]+)p"#,
                in: label,
                options: []
            ).flatMap(Int.init) ?? 0
            return KissJAVVideoCandidate(url: url, resolution: resolution, label: label)
        }
    }

    static func selectedCandidate(
        _ candidates: [KissJAVVideoCandidate],
        preferredResolution: String = ""
    ) -> KissJAVVideoCandidate? {
        guard let minimum = candidates.map(\.resolution).min() else { return nil }
        let ceiling = max(preferredHeight(from: preferredResolution), minimum)
        var selected: KissJAVVideoCandidate?
        for candidate in candidates where candidate.resolution <= ceiling {
            if selected == nil || candidate.resolution >= selected!.resolution {
                selected = candidate
            }
        }
        return selected
    }

    static func preferredHeight(from raw: String) -> Int {
        var value = raw.trimmed.uppercased()
        guard !value.isEmpty else { return originalDefaultResolution }
        if value.hasSuffix("P") {
            value.removeLast()
            return Int(value) ?? originalDefaultResolution
        }
        switch value {
        case "2K": return 1440
        case "4K": return 2160
        case "8K": return 4320
        default: return Int(value) ?? originalDefaultResolution
        }
    }

    private static func videoDataID(fromHTML html: String) -> String? {
        for tag in allTags(named: "div", in: html) {
            guard attributeValue("id", in: tag)?.lowercased() == "video",
                  let value = attributeValue("data-id", in: tag)?.trimmed,
                  !value.isEmpty else {
                continue
            }
            return decodeHTML(value)
        }
        return nil
    }

    private static func openGraphImage(fromHTML html: String, pageURL: URL) -> URL? {
        for tag in allTags(named: "meta", in: html) {
            guard attributeValue("property", in: tag)?.lowercased() == "og:image",
                  let content = attributeValue("content", in: tag) else {
                continue
            }
            return absoluteURL(content, baseURL: pageURL)
        }
        return nil
    }

    private static func elementText(named name: String, in html: String) -> String? {
        let escaped = NSRegularExpression.escapedPattern(for: name)
        guard let raw = firstCapture(
            pattern: #"<\#(escaped)\b[^>]*>(.*?)</\#(escaped)\s*>"#,
            in: html,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        ) else {
            return nil
        }
        let text = decodeHTML(raw.replacingOccurrences(of: #"<[^>]+>"#, with: " ", options: .regularExpression))
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmed
        return text.isEmpty ? nil : text
    }

    private static func elementBody(
        named name: String,
        attribute: String,
        value: String,
        in html: String
    ) -> String? {
        let escapedName = NSRegularExpression.escapedPattern(for: name)
        guard let regex = try? NSRegularExpression(
            pattern: #"</?\#(escapedName)\b[^>]*>"#,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        ) else {
            return nil
        }
        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        let matches = regex.matches(in: html, range: range)
        for (index, match) in matches.enumerated() {
            guard let openingRange = Range(match.range(at: 0), in: html) else { continue }
            let opening = String(html[openingRange])
            guard !opening.hasPrefix("</"),
                  attributeValue(attribute, in: opening)?.lowercased() == value.lowercased() else {
                continue
            }

            var depth = 1
            for nested in matches.dropFirst(index + 1) {
                guard let nestedRange = Range(nested.range(at: 0), in: html) else { continue }
                let tag = String(html[nestedRange])
                if tag.hasPrefix("</") {
                    depth -= 1
                    if depth == 0 {
                        return String(html[openingRange.upperBound..<nestedRange.lowerBound])
                    }
                } else if !tag.hasSuffix("/>") {
                    depth += 1
                }
            }
        }
        return nil
    }

    private static func allTags(named name: String, in html: String) -> [String] {
        let escaped = NSRegularExpression.escapedPattern(for: name)
        guard let regex = try? NSRegularExpression(
            pattern: #"<\#(escaped)\b[^>]*>"#,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        ) else {
            return []
        }
        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        return regex.matches(in: html, range: range).compactMap { match in
            Range(match.range(at: 0), in: html).map { String(html[$0]) }
        }
    }

    private static func attributeValue(_ name: String, in tag: String) -> String? {
        let escaped = NSRegularExpression.escapedPattern(for: name)
        guard let regex = try? NSRegularExpression(
            pattern: #"(?:^|\s)\#(escaped)\s*=\s*(?:\"([^\"]*)\"|'([^']*)'|([^\s>\"']+))"#,
            options: [.caseInsensitive]
        ) else {
            return nil
        }
        let range = NSRange(tag.startIndex..<tag.endIndex, in: tag)
        guard let match = regex.firstMatch(in: tag, range: range) else { return nil }
        for index in 1..<match.numberOfRanges {
            if let capture = Range(match.range(at: index), in: tag) {
                return decodeHTML(String(tag[capture])).trimmed
            }
        }
        return nil
    }

    private static func absoluteURL(_ raw: String, baseURL: URL) -> URL? {
        var value = decodeHTML(raw).trimmed
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

    private static func firstCapture(
        pattern: String,
        in text: String,
        options: NSRegularExpression.Options
    ) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              match.numberOfRanges > 1,
              let capture = Range(match.range(at: 1), in: text) else {
            return nil
        }
        return String(text[capture])
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
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        for match in regex.matches(in: text, range: range).reversed() {
            guard let whole = Range(match.range(at: 0), in: text) else { continue }
            let scalarValue: UInt32?
            if let hex = Range(match.range(at: 1), in: text) {
                scalarValue = UInt32(String(text[hex]), radix: 16)
            } else if let decimal = Range(match.range(at: 2), in: text) {
                scalarValue = UInt32(String(text[decimal]), radix: 10)
            } else {
                scalarValue = nil
            }
            if let scalarValue, let scalar = UnicodeScalar(scalarValue) {
                text.replaceSubrange(whole, with: String(Character(scalar)))
            }
        }
        return text
    }
}

import Foundation

struct HitomiSearchResultResolver: SearchResultResolving {
    func supports(_ baseURL: URL) -> Bool {
        guard let host = baseURL.host?.lowercased() else { return false }
        return Self.isSupportedHost(host)
    }

    static func isSupportedHost(_ host: String) -> Bool {
        host == "hitomi.la" || host.hasSuffix(".hitomi.la")
    }

    static func dataAttributeLinkValue(
        in attributes: [String: String],
        baseURL: URL?
    ) -> String? {
        guard let host = baseURL?.host?.lowercased(),
              isSupportedHost(host),
              let id = dataAttributeGalleryID(in: attributes),
              dataAttributeLooksLikeGalleryCard(attributes) else {
            return nil
        }
        return "/reader/\(id).html"
    }

    func extract(from context: SearchResultResolverContext) -> [SearchResultLink] {
        var results: [SearchResultLink] = []
        var indexByGalleryID: [String: Int] = [:]

        for anchor in context.anchors {
            guard results.count < context.limit,
                  let absolute = context.resolvedURL(for: anchor),
                  let galleryID = Self.galleryID(from: absolute),
                  let target = Self.readerURL(
                      galleryID: galleryID,
                      baseURL: context.baseURL
                  ) else {
                continue
            }

            let title = context.title(
                for: anchor,
                fallback: "Hitomi \(galleryID)"
            )
            let metadataText = resultMetadata(
                title: title,
                anchor: anchor,
                context: context
            )
            let metadata = resultMetadataFields(
                anchor: anchor,
                context: context
            )
            if let existingIndex = indexByGalleryID[galleryID] {
                if Self.isWeakTitle(
                    results[existingIndex].title,
                    galleryID: galleryID
                ),
                   !Self.isWeakTitle(title, galleryID: galleryID) {
                    results[existingIndex].title = title
                    results[existingIndex].metadataText = metadataText
                    results[existingIndex].metadata = metadata
                }
                continue
            }

            indexByGalleryID[galleryID] = results.count
            results.append(SearchResultLink(
                title: title,
                url: target.absoluteString,
                siteIdentifier: "hitomi",
                metadataText: metadataText,
                metadata: metadata
            ))
        }

        return results
    }

    private func resultMetadata(
        title: String,
        anchor: AnchorEntry,
        context: SearchResultResolverContext
    ) -> String {
        let textParts = [
            title,
            anchor.attributes["title"],
            anchor.attributes["aria-label"],
            context.embeddedImageTitle(for: anchor),
            context.bodyText(for: anchor),
            anchor.context
        ]
            .compactMap { $0?.trimmed }
            .filter { !$0.isEmpty }
        let dateTokens = Self.metadataDateValues(
            fromHTML: anchor.contextHTML
        ).map { "date:\($0)" }
        let pageTokens = Self.metadataPageCounts(
            fromHTML: anchor.contextHTML
        ).map { "pages:\($0)" }
        let semanticTokens = context.contributorMetadata(for: anchor)
            .filter { !$0.value.isEmpty }
            .map { "\($0.key):\($0.value)" }
        let metadataTokens =
            Self.metadataTokens(fromHTML: anchor.contextHTML) +
            dateTokens +
            pageTokens +
            semanticTokens
        return Self.uniqueStrings(textParts + metadataTokens)
            .joined(separator: " ")
    }

    private func resultMetadataFields(
        anchor: AnchorEntry,
        context: SearchResultResolverContext
    ) -> [String: String] {
        var fields: [String: [String]] = [:]
        for (key, value) in Self.metadataFieldPairs(
            fromHTML: anchor.contextHTML
        ) {
            fields[key, default: []].append(value)
        }
        for value in Self.metadataDateValues(fromHTML: anchor.contextHTML) {
            fields["date", default: []].append(value)
        }
        for value in Self.metadataPageCounts(fromHTML: anchor.contextHTML) {
            fields["pages", default: []].append(value)
        }
        for (key, value) in context.contributorMetadata(for: anchor)
        where !value.isEmpty {
            fields[key, default: []].append(value)
        }
        return fields.reduce(into: [:]) { result, entry in
            let values = Self.uniqueStrings(entry.value)
            guard !values.isEmpty else { return }
            result[entry.key] = values.joined(separator: ", ")
        }
    }

    private static func metadataTokens(fromHTML html: String) -> [String] {
        var tokens: [String] = []
        let pathPattern =
            #"/(tag|artist|group|series|parody|character|type|language)/([^\"'<>\s?#]+)"#
        tokens.append(contentsOf: captures(
            in: html,
            pattern: pathPattern
        ).compactMap { groups in
            guard groups.count == 2 else { return nil }
            return metadataToken(kind: groups[0], rawValue: groups[1])
        })
        tokens.append(contentsOf: matches(
            in: html,
            pattern: #"index-([A-Za-z][A-Za-z_-]*)\.html"#
        ).map {
            "language:\(metadataValue($0))"
        })
        return uniqueStrings(tokens)
    }

    private static func metadataFieldPairs(
        fromHTML html: String
    ) -> [(String, String)] {
        let pathPattern =
            #"/(tag|artist|group|series|parody|character|type|language)/([^\"'<>\s?#]+)"#
        var pairs = captures(
            in: html,
            pattern: pathPattern
        ).compactMap { groups -> (String, String)? in
            guard groups.count == 2 else { return nil }
            let kind = groups[0].lowercased()
            let value = metadataValue(groups[1])
            guard !value.isEmpty else { return nil }
            switch kind {
            case "series":
                return ("parody", value)
            default:
                return (kind, value)
            }
        }
        pairs.append(contentsOf: matches(
            in: html,
            pattern: #"index-([A-Za-z][A-Za-z_-]*)\.html"#
        ).map {
            ("language", metadataValue($0))
        })
        return pairs
    }

    private static func metadataDateValues(fromHTML html: String) -> [String] {
        let decoded = decodeHTML(html)
        let patterns = [
            #"\b(20[0-9]{2})[-./](0?[1-9]|1[0-2])[-./](0?[1-9]|[12][0-9]|3[01])\b"#,
            #"\b(0?[1-9]|[12][0-9]|3[01])[-./](0?[1-9]|1[0-2])[-./](20[0-9]{2})\b"#
        ]
        var dates: [String] = []
        for pattern in patterns {
            for groups in captures(in: decoded, pattern: pattern) {
                guard groups.count == 3 else { continue }
                let year: Int?
                let month: Int?
                let day: Int?
                if groups[0].count == 4 {
                    year = Int(groups[0])
                    month = Int(groups[1])
                    day = Int(groups[2])
                } else {
                    day = Int(groups[0])
                    month = Int(groups[1])
                    year = Int(groups[2])
                }
                guard let year, let month, let day,
                      (2000...2099).contains(year),
                      (1...12).contains(month),
                      (1...31).contains(day) else {
                    continue
                }
                dates.append(String(
                    format: "%04d-%02d-%02d",
                    year,
                    month,
                    day
                ))
            }
        }
        return uniqueStrings(dates)
    }

    private static func metadataPageCounts(fromHTML html: String) -> [String] {
        let decoded = decodeHTML(html)
        let patterns = [
            #"\b([1-9][0-9]{0,4})\s*(?:pages?|p\.)\b"#,
            #"\b(?:pages?|page_count|pagecount|total_pages)\s*[:=]\s*([1-9][0-9]{0,4})\b"#,
            #"\b([1-9][0-9]{0,4})\s*(?:페이지|쪽)\b"#
        ]
        var counts: [String] = []
        for pattern in patterns {
            counts.append(contentsOf: matches(
                in: decoded,
                pattern: pattern
            ).compactMap { raw in
                guard let value = Int(
                    raw.replacingOccurrences(of: ",", with: "")
                ),
                      value > 0 else {
                    return nil
                }
                return String(value)
            })
        }
        return uniqueStrings(counts)
    }

    private static func metadataToken(
        kind rawKind: String,
        rawValue: String
    ) -> String? {
        let kind = rawKind.lowercased()
        let value = metadataValue(rawValue)
        guard !value.isEmpty else { return nil }
        switch kind {
        case "tag":
            return value
        case "artist", "group", "character", "type", "language":
            return "\(kind):\(value)"
        case "series", "parody":
            return "parody:\(value)"
        default:
            return nil
        }
    }

    private static func metadataValue(_ raw: String) -> String {
        let withoutExtension = raw
            .replacingOccurrences(
                of: #"\.html.*$"#,
                with: "",
                options: .regularExpression
            )
            .replacingOccurrences(
                of: #"-all$"#,
                with: "",
                options: .regularExpression
            )
        let decoded = withoutExtension.removingPercentEncoding ??
            withoutExtension
        return decodeHTML(decoded)
            .replacingOccurrences(of: "_", with: " ")
            .trimmed
    }

    private static func galleryID(from url: URL) -> String? {
        let absolute = url.absoluteString
        let patterns = [
            #"hitomi\.la/(?:reader|galleries)/([0-9]+)"#,
            #"-([0-9]+)\.html(?:[#?].*)?$"#
        ]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(
                pattern: pattern,
                options: [.caseInsensitive]
            ) else {
                continue
            }
            let range = NSRange(
                absolute.startIndex..<absolute.endIndex,
                in: absolute
            )
            if let match = regex.firstMatch(in: absolute, range: range),
               let capture = Range(match.range(at: 1), in: absolute) {
                return String(absolute[capture])
            }
        }
        return nil
    }

    private static func readerURL(
        galleryID: String,
        baseURL: URL
    ) -> URL? {
        var components = URLComponents(
            url: baseURL,
            resolvingAgainstBaseURL: false
        )
        components?.scheme = "https"
        components?.host = "hitomi.la"
        components?.path = "/reader/\(galleryID).html"
        components?.queryItems = nil
        components?.fragment = nil
        return components?.url
    }

    private static func isWeakTitle(
        _ title: String,
        galleryID: String
    ) -> Bool {
        let value = title.trimmed.lowercased()
        return value.isEmpty ||
            value == "download" ||
            value == galleryID ||
            value == "\(galleryID).html" ||
            value == "hitomi \(galleryID)" ||
            value.hasPrefix("reader") ||
            value.contains("/\(galleryID)")
    }

    private static func dataAttributeGalleryID(
        in attributes: [String: String]
    ) -> String? {
        let keys = [
            "data-gallery-id", "data-galleryid", "data-reader-id",
            "data-readerid", "data-work-id", "data-workid",
            "gallery-id", "reader-id"
        ]
        if let value = firstAttributeValue(
            in: attributes,
            keys: keys,
            matching: isNumericID
        ) {
            return value
        }
        if let id = attributes["data-id"]?.trimmed,
           isNumericID(id),
           typeHint(
               in: attributes,
               containsAnyOf: ["gallery", "reader", "doujin", "manga"]
           ) {
            return id
        }
        return nil
    }

    private static func dataAttributeLooksLikeGalleryCard(
        _ attributes: [String: String]
    ) -> Bool {
        let markerKeys = [
            "data-gallery-id", "data-galleryid", "data-reader-id",
            "data-readerid", "data-work-id", "data-workid",
            "gallery-id", "reader-id"
        ]
        if typeHint(
            in: attributes,
            containsAnyOf: ["tag", "search", "nav", "menu", "filter"]
        ) {
            return false
        }
        if markerKeys.contains(
            where: { attributes[$0]?.trimmed.isEmpty == false }
        ) {
            return true
        }
        return typeHint(
            in: attributes,
            containsAnyOf: ["gallery", "reader", "doujin", "manga"]
        )
    }

    private static func firstAttributeValue(
        in attributes: [String: String],
        keys: [String],
        matching predicate: (String) -> Bool
    ) -> String? {
        for key in keys {
            if let value = attributes[key]?.trimmed,
               predicate(value) {
                return value
            }
        }
        return nil
    }

    private static func typeHint(
        in attributes: [String: String],
        containsAnyOf needles: [String]
    ) -> Bool {
        let keys = [
            "data-type", "data-kind", "data-content-type",
            "data-renderer", "class", "role"
        ]
        let values = keys.compactMap { attributes[$0]?.lowercased() }
        return values.contains { value in
            needles.contains { value.contains($0) }
        }
    }

    private static func isNumericID(_ value: String) -> Bool {
        value.range(
            of: #"^[0-9]+$"#,
            options: .regularExpression
        ) != nil
    }

    private static func matches(
        in text: String,
        pattern: String
    ) -> [String] {
        captures(in: text, pattern: pattern).compactMap(\.first)
    }

    private static func captures(
        in text: String,
        pattern: String
    ) -> [[String]] {
        guard let regex = try? NSRegularExpression(
            pattern: pattern,
            options: [.caseInsensitive]
        ) else {
            return []
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.matches(in: text, range: range).compactMap { match in
            guard match.numberOfRanges > 1 else { return nil }
            var groups: [String] = []
            for index in 1..<match.numberOfRanges {
                guard let capture = Range(
                    match.range(at: index),
                    in: text
                ) else {
                    return nil
                }
                groups.append(String(text[capture]))
            }
            return groups
        }
    }

    private static func uniqueStrings(_ values: [String]) -> [String] {
        var seen = Set<String>()
        var output: [String] = []
        for value in values {
            let trimmed = value.trimmed
            guard !trimmed.isEmpty else { continue }
            let key = trimmed.lowercased()
            guard seen.insert(key).inserted else { continue }
            output.append(trimmed)
        }
        return output
    }

    private static func decodeHTML(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
    }
}

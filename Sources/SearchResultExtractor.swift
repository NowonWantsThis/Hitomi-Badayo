import Foundation

enum SearchResultExtractor {
    static func extractLinks(from html: String, baseURL: URL, limit: Int = 50) -> [SearchResultLink] {
        let resolutionBaseURL = documentBaseURL(from: html, fallback: baseURL)
        let anchors = anchorEntries(from: html, baseURL: baseURL, resolutionBaseURL: resolutionBaseURL)
        let resolverContext = SearchResultResolverContext(
            anchors: anchors,
            baseURL: baseURL,
            limit: limit,
            resolveHref: { resolve(href: $0, baseURL: $1) },
            titleProvider: { displayTitle(for: $0, fallbackURL: $1) },
            fallbackTitleProvider: { displayTitle(for: $0, fallback: $1) },
            contributorMetadataProvider: {
                searchContributorMetadata(
                    anchor: $0,
                    fallbackName: $1,
                    fallbackUsername: $2,
                    fallbackUserID: $3
                )
            },
            embeddedImageAttributesProvider: {
                $0.attributes.merging(imageAttributes(from: $0.body)) { current, _ in current }
            },
            semanticAttributesProvider: { semanticSearchAttributes(for: $0) },
            canonicalQueueURLProvider: {
                SearchResultResolverRegistry.canonicalQueueURL(for: $0)
            },
            nestedAnchorsProvider: { anchorEntries(from: $0) },
            bodyTextProvider: { stripTags($0.body) },
            embeddedImageTitleProvider: {
                embeddedImageTitle(from: $0.body)
            },
            tagAttributesProvider: { attributeValues(from: $0) }
        )
        if let resolvedLinks = SearchResultResolverRegistry.standard.extract(from: resolverContext) {
            return resolvedLinks
        }
        if let resolvedLinks =
            SearchResultResolverRegistry.originalMediaFallback.extract(
                from: resolverContext
            ) {
            return resolvedLinks
        }
        var results: [SearchResultLink] = []
        var seen = Set<String>()

        for anchor in anchors {
            guard results.count < limit,
                  let href = anchor.attributes["href"]?.trimmed,
                  let absolute = resolve(href: href, baseURL: baseURL) else {
                continue
            }

            let normalized = URLIdentity.normalize(absolute.absoluteString)
            guard !seen.contains(normalized), isUseful(absolute) else { continue }

            seen.insert(normalized)
            let title = displayTitle(for: anchor, fallbackURL: absolute)
            results.append(SearchResultLink(
                title: title,
                url: absolute.absoluteString,
                metadata: genericFallbackSearchMetadata(searchPageURL: baseURL, target: absolute, title: title, anchor: anchor)
            ))
        }

        return results
    }

    private static func genericFallbackSearchMetadata(searchPageURL: URL, target: URL, title: String, anchor: AnchorEntry) -> [String: String] {
        var metadata = searchContributorMetadata(anchor: anchor)
        let sourceHost = searchPageURL.host ?? ""
        let targetHost = target.host ?? ""
        metadata.merge([
            "source_url": target.absoluteString,
            "page_url": target.absoluteString,
            "search_page_url": searchPageURL.absoluteString,
            "search_site": sourceHost,
            "target_url": target.absoluteString,
            "target_host": targetHost,
            "host": targetHost,
            "category": "link",
            "type": "link",
            "title": title,
            "search_title": title
        ]) { current, _ in current }
        return DownloadMetadata.clean(metadata)
    }

    private static func searchContributorMetadata(
        anchor: AnchorEntry,
        fallbackName: String? = nil,
        fallbackUsername: String? = nil,
        fallbackUserID: String? = nil
    ) -> [String: String] {
        let attributes = semanticSearchAttributes(for: anchor)
        let displayName = firstSemanticAttribute(attributes, keys: [
            "data-channel-name", "channel-name", "channel",
            "data-uploader-name", "data-uploader", "uploader",
            "data-artist-name", "data-artist", "artist",
            "data-author-name", "data-author", "author",
            "data-creator-name", "data-creator", "creator",
            "data-user-name"
        ]) ?? fallbackName
        let username = firstSemanticAttribute(attributes, keys: [
            "data-channel", "data-channel-username",
            "data-username", "username",
            "data-user", "user",
            "data-owner", "owner"
        ]) ?? fallbackUsername
        let userID = firstSemanticAttribute(attributes, keys: [
            "data-channel-id", "channel-id",
            "data-uploader-id", "uploader-id",
            "data-user-id", "user-id",
            "data-uid", "uid"
        ]) ?? fallbackUserID
        var metadata: [String: String] = [:]
        if let displayName, !displayName.isEmpty {
            metadata["artist"] = displayName
            metadata["author"] = displayName
            metadata["creator"] = displayName
            metadata["uploader"] = displayName
            metadata["channel"] = displayName
        }
        if let username, !username.isEmpty {
            metadata["username"] = username
            metadata["user"] = username
        }
        if let userID, !userID.isEmpty {
            metadata["user_id"] = userID
            metadata["uploader_id"] = userID
            metadata["channel_id"] = userID
        }
        if let date = searchDateValue(firstSemanticAttribute(attributes, keys: [
            "data-created-at", "created-at",
            "data-date", "date",
            "data-published-at", "published-at",
            "data-upload-date", "upload-date"
        ])) {
            metadata["date"] = date
            metadata["created"] = date
        }
        return DownloadMetadata.clean(metadata)
    }

    private static func searchDateValue(_ raw: String?) -> String? {
        guard let raw = raw?.trimmed, !raw.isEmpty else { return nil }
        if let match = firstCapture(
            in: raw,
            pattern: #"([0-9]{4}-[0-9]{2}-[0-9]{2})"#
        ) {
            return match
        }
        return raw
    }

    private static func semanticSearchAttributes(for anchor: AnchorEntry) -> [String: String] {
        var attributes = anchor.attributes
        attributes.merge(imageAttributes(from: anchor.body)) { current, _ in current }
        for values in tagAttributeValues(from: anchor.contextHTML) {
            attributes.merge(values) { current, new in current.isEmpty ? new : current }
        }
        return attributes
    }

    private static func tagAttributeValues(from html: String) -> [[String: String]] {
        let pattern = #"<[a-zA-Z0-9:-]+\b([^>]*)>"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return []
        }
        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        return regex.matches(in: html, range: range).compactMap { match in
            guard let attributesRange = Range(match.range(at: 1), in: html) else { return nil }
            let values = attributeValues(from: String(html[attributesRange]))
            return values.isEmpty ? nil : values
        }
    }

    private static func firstSemanticAttribute(_ attributes: [String: String], keys: [String]) -> String? {
        for key in keys {
            guard let value = attributes.first(where: { $0.key.lowercased() == key })?.value.trimmed,
                  !value.isEmpty else {
                continue
            }
            return value
        }
        return nil
    }

    private static func imageAttributes(from html: String) -> [String: String] {
        guard let regex = try? NSRegularExpression(
            pattern: #"<img\b([^>]*)>"#,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        ) else {
            return [:]
        }
        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        guard let match = regex.firstMatch(in: html, range: range),
              let attributesRange = Range(match.range(at: 1), in: html) else {
            return [:]
        }
        return attributeValues(from: String(html[attributesRange]))
    }

    private static func anchorEntries(from html: String, baseURL: URL? = nil, resolutionBaseURL: URL? = nil) -> [AnchorEntry] {
        let linkResolutionBaseURL = resolutionBaseURL ?? baseURL
        let pattern = #"<a\b([^>]*)>(.*?)</a>"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else {
            return jsonLDAnchorEntries(from: html, baseURL: linkResolutionBaseURL)
        }

        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        var entries = regex.matches(in: html, range: range).compactMap { match -> AnchorEntry? in
            guard let attributesRange = Range(match.range(at: 1), in: html),
                  let bodyRange = Range(match.range(at: 2), in: html),
                  let matchRange = Range(match.range, in: html) else {
                return nil
            }
            let contextHTML = contextSlice(around: matchRange, in: html)
            var attributes = attributeValues(from: String(html[attributesRange]))
            if let href = normalizedHref(attributes["href"], baseURL: linkResolutionBaseURL) {
                attributes["href"] = href
            }
            return AnchorEntry(
                attributes: attributes,
                body: String(html[bodyRange]),
                context: decodeHTML(stripTags(contextHTML)),
                contextHTML: contextHTML
            )
        }
        entries.append(contentsOf: dataAttributeAnchorEntries(from: html, baseURL: baseURL, resolutionBaseURL: linkResolutionBaseURL))
        entries.append(contentsOf: microdataAnchorEntries(from: html, baseURL: baseURL, resolutionBaseURL: linkResolutionBaseURL))
        entries.append(contentsOf: rdfaAnchorEntries(from: html, baseURL: baseURL, resolutionBaseURL: linkResolutionBaseURL))
        entries.append(contentsOf: jsonLDAnchorEntries(from: html, baseURL: linkResolutionBaseURL))
        entries.append(contentsOf: jsonStateAnchorEntries(from: html, baseURL: baseURL, resolutionBaseURL: linkResolutionBaseURL))
        return entries
    }

    private static func dataAttributeAnchorEntries(from html: String, baseURL: URL?, resolutionBaseURL: URL?) -> [AnchorEntry] {
        guard let regex = try? NSRegularExpression(
            pattern: #"<([a-zA-Z][A-Za-z0-9:-]*)\b([^>]*)>"#,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        ) else {
            return []
        }

        let skippedTags: Set<String> = [
            "a", "audio", "body", "br", "head", "html", "iframe", "img",
            "input", "link", "meta", "picture", "script", "source", "style",
            "svg", "video"
        ]
        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        var entries: [AnchorEntry] = []
        var seen = Set<String>()

        for match in regex.matches(in: html, range: range) {
            guard let tagRange = Range(match.range(at: 1), in: html),
                  let attributesRange = Range(match.range(at: 2), in: html),
                  let matchRange = Range(match.range, in: html) else {
                continue
            }
            let tagName = String(html[tagRange]).lowercased()
            guard !skippedTags.contains(tagName) else { continue }

            let attributes = attributeValues(from: String(html[attributesRange]))
            guard let href = dataAttributeLinkValue(in: attributes, baseURL: baseURL),
                  !seen.contains(href) else {
                continue
            }

            let resolvedHref = normalizedHref(href, baseURL: resolutionBaseURL) ?? href
            guard !seen.contains(resolvedHref) else { continue }
            seen.insert(resolvedHref)
            let contextHTML = currentElementContext(tagName: tagName, around: matchRange, in: html) ??
                microdataCardContext(around: matchRange, in: html) ??
                contextSlice(around: matchRange, in: html)
            let title = dataAttributeTitleValue(in: attributes) ?? contextualCardTitleValue(fromHTML: contextHTML)
            var linkAttributes = attributes
            linkAttributes["href"] = resolvedHref
            if linkAttributes["title"] == nil,
               let title {
                linkAttributes["title"] = title
            }
            entries.append(AnchorEntry(
                attributes: linkAttributes,
                body: title ?? stripTags(contextHTML),
                context: decodeHTML(stripTags(contextHTML)),
                contextHTML: contextHTML
            ))
        }

        return entries
    }

    private static func microdataAnchorEntries(from html: String, baseURL: URL?, resolutionBaseURL: URL?) -> [AnchorEntry] {
        guard let regex = try? NSRegularExpression(
            pattern: #"<([a-zA-Z][A-Za-z0-9:-]*)\b([^>]*)>"#,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        ) else {
            return []
        }

        let skippedTags: Set<String> = [
            "a", "audio", "body", "br", "head", "html", "iframe", "img",
            "input", "picture", "script", "source", "style", "svg", "video"
        ]
        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        var entries: [AnchorEntry] = []
        var seen = Set<String>()

        for match in regex.matches(in: html, range: range) {
            guard let tagRange = Range(match.range(at: 1), in: html),
                  let attributesRange = Range(match.range(at: 2), in: html),
                  let matchRange = Range(match.range, in: html) else {
                continue
            }
            let tagName = String(html[tagRange]).lowercased()
            guard !skippedTags.contains(tagName),
                  !isInsideHead(around: matchRange, in: html) else {
                continue
            }

            let attributes = attributeValues(from: String(html[attributesRange]))
            guard microdataItemprop(in: attributes, containsAnyOf: ["url", "mainentityofpage", "contenturl"]),
                  let href = microdataLinkValue(in: attributes, baseURL: baseURL),
                  !seen.contains(href) else {
                continue
            }
            let resolvedHref = normalizedHref(href, baseURL: resolutionBaseURL) ?? href
            guard !seen.contains(resolvedHref) else { continue }

            let contextHTML = microdataCardContext(around: matchRange, in: html) ?? contextSlice(around: matchRange, in: html)
            guard let title = microdataTitleValue(in: attributes, contextHTML: contextHTML) else {
                continue
            }

            seen.insert(resolvedHref)
            var linkAttributes = attributes
            linkAttributes["href"] = resolvedHref
            if linkAttributes["title"] == nil {
                linkAttributes["title"] = title
            }
            entries.append(AnchorEntry(
                attributes: linkAttributes,
                body: title,
                context: decodeHTML(stripTags(contextHTML)),
                contextHTML: contextHTML
            ))
        }

        return entries
    }

    private static func microdataItemprop(in attributes: [String: String], containsAnyOf needles: [String]) -> Bool {
        guard let raw = attributes["itemprop"]?.lowercased() else { return false }
        let tokens = raw.split { character in
            character == " " || character == "\t" || character == "\n" || character == "\r" || character == ","
        }.map(String.init)
        return needles.contains { needle in tokens.contains(needle.lowercased()) }
    }

    private static func microdataLinkValue(in attributes: [String: String], baseURL: URL?) -> String? {
        let keys = ["href", "content", "itemid", "data-url", "data-href", "data-permalink"]
        for key in keys {
            guard let raw = attributes[key]?.trimmed,
                  looksLikeDataAttributeLink(raw) else {
                continue
            }
            if let baseURL,
               let absolute = URL(string: raw, relativeTo: baseURL)?.absoluteURL,
               URLIdentity.normalize(absolute.absoluteString) == URLIdentity.normalize(baseURL.absoluteString) {
                continue
            }
            return raw
        }
        return nil
    }

    private static func microdataTitleValue(in attributes: [String: String], contextHTML: String) -> String? {
        let bodyContextHTML = contextHTML.replacingOccurrences(
            of: #"<head\b[^>]*>.*?</head>"#,
            with: " ",
            options: [.regularExpression, .caseInsensitive]
        )
        return dataAttributeTitleValue(in: attributes) ??
            microdataValue(fromHTML: bodyContextHTML, itemprops: ["name", "headline", "title"])
    }

    private static func microdataValue(fromHTML html: String, itemprops: [String]) -> String? {
        let alternation = itemprops.map { NSRegularExpression.escapedPattern(for: $0) }.joined(separator: "|")
        let textPattern = "<[a-zA-Z][A-Za-z0-9:-]*\\b(?=[^>]*\\bitemprop\\s*=\\s*[\"'][^\"']*(?:" +
            alternation +
            ")[^\"']*[\"'])[^>]*>(.*?)</[a-zA-Z][A-Za-z0-9:-]*>"
        if let textRegex = try? NSRegularExpression(
            pattern: textPattern,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        ) {
            let range = NSRange(html.startIndex..<html.endIndex, in: html)
            for match in textRegex.matches(in: html, range: range) {
                guard let matchRange = Range(match.range, in: html),
                      let bodyRange = Range(match.range(at: 1), in: html),
                      !isInsideHead(around: matchRange, in: html) else { continue }
                let value = stripTags(String(html[bodyRange]))
                if !value.isEmpty {
                    return value
                }
            }
        }

        if let regex = try? NSRegularExpression(
            pattern: #"<[a-zA-Z][A-Za-z0-9:-]*\b([^>]*)>"#,
            options: [.caseInsensitive]
        ) {
            let range = NSRange(html.startIndex..<html.endIndex, in: html)
            for match in regex.matches(in: html, range: range) {
                guard let matchRange = Range(match.range, in: html),
                      let attributesRange = Range(match.range(at: 1), in: html),
                      !isInsideHead(around: matchRange, in: html) else { continue }
                let attributes = attributeValues(from: String(html[attributesRange]))
                guard microdataItemprop(in: attributes, containsAnyOf: itemprops) else { continue }
                if let value = dataAttributeTitleValue(in: attributes) ?? attributes["content"]?.trimmed,
                   !value.isEmpty {
                    return value
                }
            }
        }
        return nil
    }

    private static func microdataCardContext(around range: Range<String.Index>, in html: String) -> String? {
        let blockTags = ["article", "li", "section", "div"]
        var bestRange: Range<String.Index>?
        var bestStartDistance = -1
        for tag in blockTags {
            guard let start = lastOpeningTagRange(tag, before: range, in: html),
                  let end = html.range(
                      of: "</\(tag)>",
                      options: [.caseInsensitive],
                      range: range.upperBound..<html.endIndex
                  ) else {
                continue
            }
            let candidate = start.lowerBound..<end.upperBound
            let startDistance = html.distance(from: html.startIndex, to: candidate.lowerBound)
            if startDistance > bestStartDistance {
                bestStartDistance = startDistance
                bestRange = candidate
            }
        }
        return bestRange.map { String(html[$0]) }
    }

    private static func rdfaAnchorEntries(from html: String, baseURL: URL?, resolutionBaseURL: URL?) -> [AnchorEntry] {
        guard let regex = try? NSRegularExpression(
            pattern: #"<([a-zA-Z][A-Za-z0-9:-]*)\b([^>]*)>"#,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        ) else {
            return []
        }

        let skippedTags: Set<String> = [
            "a", "audio", "body", "br", "head", "html", "iframe", "img",
            "input", "link", "meta", "picture", "script", "source", "style",
            "svg", "video"
        ]
        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        var entries: [AnchorEntry] = []
        var seen = Set<String>()

        for match in regex.matches(in: html, range: range) {
            guard let tagRange = Range(match.range(at: 1), in: html),
                  let attributesRange = Range(match.range(at: 2), in: html),
                  let matchRange = Range(match.range, in: html) else {
                continue
            }
            let tagName = String(html[tagRange]).lowercased()
            guard !skippedTags.contains(tagName),
                  !isInsideHead(around: matchRange, in: html) else {
                continue
            }

            let attributes = attributeValues(from: String(html[attributesRange]))
            let contextHTML = currentElementContext(tagName: tagName, around: matchRange, in: html) ??
                microdataCardContext(around: matchRange, in: html) ??
                contextSlice(around: matchRange, in: html)
            guard rdfaLooksLikeResultCard(attributes: attributes, contextHTML: contextHTML),
                  let href = rdfaLinkValue(in: attributes, contextHTML: contextHTML, baseURL: baseURL),
                  !seen.contains(href) else {
                continue
            }
            let resolvedHref = normalizedHref(href, baseURL: resolutionBaseURL) ?? href
            guard !seen.contains(resolvedHref),
                  let title = rdfaTitleValue(in: attributes, contextHTML: contextHTML) else {
                continue
            }

            seen.insert(resolvedHref)
            var linkAttributes = attributes
            linkAttributes["href"] = resolvedHref
            linkAttributes["title"] = title
            linkAttributes.merge(rdfaSemanticAttributes(fromHTML: contextHTML)) { current, _ in current }
            entries.append(AnchorEntry(
                attributes: linkAttributes,
                body: title,
                context: decodeHTML(stripTags(contextHTML)),
                contextHTML: contextHTML
            ))
        }

        return entries
    }

    private static func rdfaLooksLikeResultCard(attributes: [String: String], contextHTML: String) -> Bool {
        let ownText = [
            attributes["typeof"],
            attributes["vocab"],
            attributes["prefix"],
            attributes["property"],
            attributes["rel"]
        ].compactMap { $0?.lowercased() }.joined(separator: " ")
        let text = [
            ownText,
            contextHTML
        ].map { $0.lowercased() }.joined(separator: " ")

        let excludedNeedles = [
            "breadcrumblist", "website", "webpage", "organization", "person",
            "searchresults", "searchaction", "sitenavigationelement", "wpheader", "wpfooter"
        ]
        if excludedNeedles.contains(where: { ownText.contains($0) }) {
            return false
        }

        let contentNeedles = [
            "creativework", "article", "blogposting", "socialmediaposting",
            "imageobject", "videoobject", "audioobject", "mediaobject",
            "product", "comic", "book", "episode", "clip", "gallery", "posting"
        ]
        if contentNeedles.contains(where: { text.contains($0) }) {
            return true
        }

        return rdfaContainsProperty(contextHTML, anyOf: ["url", "mainentityofpage", "contenturl"]) &&
            rdfaContainsProperty(contextHTML, anyOf: ["name", "headline", "title"])
    }

    private static func rdfaLinkValue(in attributes: [String: String], contextHTML: String, baseURL: URL?) -> String? {
        let directKeys = ["resource", "about", "href", "src", "content", "data-url", "data-href", "data-permalink"]
        for key in directKeys {
            guard let raw = attributes[key]?.trimmed,
                  looksLikeDataAttributeLink(raw) else {
                continue
            }
            if let baseURL,
               let absolute = URL(string: raw, relativeTo: baseURL)?.absoluteURL,
               URLIdentity.normalize(absolute.absoluteString) == URLIdentity.normalize(baseURL.absoluteString) {
                continue
            }
            return raw
        }

        return rdfaPropertyValue(
            fromHTML: contextHTML,
            properties: ["url", "mainentityofpage", "contenturl"],
            valueKeys: ["href", "resource", "about", "content", "src", "data-url", "data-href", "data-permalink"],
            allowText: false
        ).flatMap { looksLikeDataAttributeLink($0) ? $0 : nil }
    }

    private static func rdfaTitleValue(in attributes: [String: String], contextHTML: String) -> String? {
        dataAttributeTitleValue(in: attributes).flatMap(cleanContextualTitle) ??
            rdfaPropertyValue(
                fromHTML: contextHTML,
                properties: ["name", "headline", "title"],
                valueKeys: ["content", "title", "aria-label", "data-title", "data-name"],
                allowText: true
            ).flatMap(cleanContextualTitle) ??
            contextualCardTitleValue(fromHTML: contextHTML)
    }

    private static func rdfaSemanticAttributes(fromHTML html: String) -> [String: String] {
        var attributes: [String: String] = [:]
        if let author = rdfaPropertyValue(
            fromHTML: html,
            properties: ["author", "creator", "dc:creator"],
            valueKeys: ["content", "title", "aria-label", "data-author", "data-artist", "data-name"],
            allowText: true
        ).flatMap(cleanContextualTitle) {
            attributes["data-author-name"] = author
            attributes["data-artist"] = author
            attributes["data-creator"] = author
        }
        if let date = rdfaPropertyValue(
            fromHTML: html,
            properties: ["datepublished", "datecreated", "uploaddate", "dc:date", "published"],
            valueKeys: ["datetime", "content", "data-date", "title"],
            allowText: true
        ).flatMap(searchDateValue) {
            attributes["data-date"] = date
        }
        return attributes
    }

    private static func rdfaContainsProperty(_ html: String, anyOf properties: [String]) -> Bool {
        rdfaPropertyValue(fromHTML: html, properties: properties, valueKeys: ["content", "href", "resource", "about"], allowText: true) != nil
    }

    private static func rdfaPropertyValue(fromHTML html: String, properties: [String], valueKeys: [String], allowText: Bool) -> String? {
        let wanted = Set(properties.map { $0.lowercased() })

        if let regex = try? NSRegularExpression(
            pattern: #"<[a-zA-Z][A-Za-z0-9:-]*\b(?=[^>]*\b(?:property|rel)\s*=)([^>]*)/?>"#,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        ) {
            let range = NSRange(html.startIndex..<html.endIndex, in: html)
            for match in regex.matches(in: html, range: range) {
                guard let attributesRange = Range(match.range(at: 1), in: html) else { continue }
                let attributes = attributeValues(from: String(html[attributesRange]))
                guard rdfaPropertyTokens(in: attributes).contains(where: { wanted.contains($0) }) else {
                    continue
                }

                for key in valueKeys {
                    guard let value = attributes[key]?.trimmed,
                          !value.isEmpty else {
                        continue
                    }
                    return value
                }
            }
        }

        guard allowText,
              let textRegex = try? NSRegularExpression(
                  pattern: #"<([a-zA-Z][A-Za-z0-9:-]*)\b(?=[^>]*\b(?:property|rel)\s*=)([^>]*)>(.*?)</\1>"#,
                  options: [.caseInsensitive, .dotMatchesLineSeparators]
              ) else {
            return nil
        }
        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        for match in textRegex.matches(in: html, range: range) {
            guard let attributesRange = Range(match.range(at: 2), in: html),
                  let bodyRange = Range(match.range(at: 3), in: html) else {
                continue
            }
            let attributes = attributeValues(from: String(html[attributesRange]))
            guard rdfaPropertyTokens(in: attributes).contains(where: { wanted.contains($0) }) else {
                continue
            }
            guard let title = cleanContextualTitle(String(html[bodyRange])) else {
                continue
            }
            return title
        }
        return nil
    }

    private static func rdfaPropertyTokens(in attributes: [String: String]) -> [String] {
        let raw = [attributes["property"], attributes["rel"]].compactMap { $0 }.joined(separator: " ").lowercased()
        return raw.split { character in
            character == " " || character == "\t" || character == "\n" || character == "\r" || character == ","
        }.map(String.init)
    }

    private static func currentElementContext(tagName: String, around range: Range<String.Index>, in html: String) -> String? {
        let lowerTagName = tagName.lowercased()
        let voidTags: Set<String> = [
            "area", "base", "br", "col", "embed", "hr", "img", "input",
            "link", "meta", "param", "source", "track", "wbr"
        ]
        guard !voidTags.contains(lowerTagName),
              let end = html.range(
                  of: "</\(lowerTagName)>",
                  options: [.caseInsensitive],
                  range: range.upperBound..<html.endIndex
              ) else {
            return nil
        }
        let candidate = range.lowerBound..<end.upperBound
        guard html.distance(from: candidate.lowerBound, to: candidate.upperBound) <= 6_000 else {
            return nil
        }
        return String(html[candidate])
    }

    private static func lastOpeningTagRange(_ tag: String, before range: Range<String.Index>, in html: String) -> Range<String.Index>? {
        guard let regex = try? NSRegularExpression(
            pattern: #"<\#(tag)\b[^>]*>"#,
            options: [.caseInsensitive]
        ) else {
            return nil
        }
        let searchRange = NSRange(html.startIndex..<range.lowerBound, in: html)
        return regex.matches(in: html, range: searchRange)
            .compactMap { Range($0.range, in: html) }
            .last
    }

    private static func isInsideHead(around range: Range<String.Index>, in html: String) -> Bool {
        let prefix = String(html[..<range.lowerBound]).lowercased()
        guard let headStart = prefix.range(of: "<head", options: .backwards) else {
            guard prefix.range(of: "</head>", options: .backwards) == nil else {
                return false
            }
            let suffix = String(html[range.lowerBound...]).lowercased()
            guard let headEnd = suffix.range(of: "</head>") else {
                return false
            }
            if let bodyStart = suffix.range(of: "<body"),
               bodyStart.lowerBound < headEnd.lowerBound {
                return false
            }
            return true
        }
        if let headEnd = prefix.range(of: "</head>", options: .backwards),
           headEnd.lowerBound > headStart.lowerBound {
            return false
        }
        return true
    }

    private static func dataAttributeLinkValue(in attributes: [String: String], baseURL: URL?) -> String? {
        switch SearchResultResolverRegistry.priorityDataAttributeResolution(
            in: attributes,
            baseURL: baseURL
        ) {
        case .unhandled:
            break
        case .handled(let link):
            return link
        }

        let keys = [
            "data-href", "data-url", "data-permalink", "data-link",
            "data-target-url", "data-target", "data-canonical-url",
            "data-result-url", "data-destination-url",
            "data-post-url", "data-video-url", "data-watch-url",
            "data-page-url", "data-entry-url", "data-uri", "data-path",
            "data-click-url", "data-click-href", "data-open-url",
            "data-action-url", "data-redirect-url", "data-navigate-url"
        ]
        for key in keys {
            guard let raw = attributes[key]?.trimmed,
                  let href = dataAttributeNavigationCandidate(from: raw, baseURL: baseURL) else {
                continue
            }
            return href
        }
        if let eventLink = eventAttributeLinkValue(in: attributes, baseURL: baseURL) {
            return eventLink
        }
        return SearchResultResolverRegistry.dataAttributeLinkValue(
            in: attributes,
            baseURL: baseURL
        )
    }

    private static func eventAttributeLinkValue(in attributes: [String: String], baseURL: URL?) -> String? {
        let keys = ["onclick", "onmousedown", "onmouseup", "onauxclick", "data-onclick"]
        for key in keys {
            guard let script = attributes[key]?.trimmed,
                  let href = eventNavigationURL(in: script, baseURL: baseURL) else {
                continue
            }
            return href
        }
        return nil
    }

    private static func eventNavigationURL(in script: String, baseURL: URL?) -> String? {
        let lowercasedScript = script.lowercased()
        guard lowercasedScript.contains("location") || lowercasedScript.contains("window.open") else {
            return nil
        }

        let patterns = [
            #"(?:window\.)?location(?:\.href)?\s*=\s*(['"])(.*?)\1"#,
            #"document\.location(?:\.href)?\s*=\s*(['"])(.*?)\1"#,
            #"(?:window\.)?location\.(?:assign|replace)\s*\(\s*(['"])(.*?)\1"#,
            #"window\.open\s*\(\s*(['"])(.*?)\1"#
        ]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(
                pattern: pattern,
                options: [.caseInsensitive, .dotMatchesLineSeparators]
            ) else {
                continue
            }
            let range = NSRange(script.startIndex..<script.endIndex, in: script)
            for match in regex.matches(in: script, range: range) {
                guard let rawRange = Range(match.range(at: 2), in: script) else { continue }
                let raw = decodedJavaScriptStringLiteral(String(script[rawRange]))
                if let candidate = eventNavigationCandidate(from: raw, baseURL: baseURL) {
                    return candidate
                }
            }
        }
        return nil
    }

    private static func eventNavigationCandidate(from raw: String, baseURL: URL?) -> String? {
        dataAttributeNavigationCandidate(from: raw, baseURL: baseURL)
    }

    private static func dataAttributeNavigationCandidate(from raw: String, baseURL: URL?) -> String? {
        let candidate = raw.trimmed
        guard looksLikeDataAttributeLink(candidate) else { return nil }
        if let baseURL,
           let absolute = URL(string: candidate, relativeTo: baseURL)?.absoluteURL,
           URLIdentity.normalize(absolute.absoluteString) == URLIdentity.normalize(baseURL.absoluteString) {
            return nil
        }
        return candidate
    }

    private static func decodedJavaScriptStringLiteral(_ raw: String) -> String {
        var value = raw
            .replacingOccurrences(of: #"\/"#, with: "/")
            .replacingOccurrences(of: #"\""#, with: "\"")
            .replacingOccurrences(of: #"\'"#, with: "'")
            .replacingOccurrences(of: #"\\\\"#, with: #"\"#)

        guard let regex = try? NSRegularExpression(pattern: #"\\u([0-9A-Fa-f]{4})"#) else {
            return value
        }
        let range = NSRange(value.startIndex..<value.endIndex, in: value)
        for match in regex.matches(in: value, range: range).reversed() {
            guard let fullRange = Range(match.range, in: value),
                  let hexRange = Range(match.range(at: 1), in: value),
                  let scalarValue = UInt32(value[hexRange], radix: 16),
                  let scalar = UnicodeScalar(scalarValue) else {
                continue
            }
            value.replaceSubrange(fullRange, with: String(scalar))
        }
        return value
    }

    private static func looksLikeDataAttributeLink(_ value: String) -> Bool {
        guard !value.isEmpty,
              !value.hasPrefix("#"),
              !value.hasPrefix("{"),
              !value.hasPrefix("[") else {
            return false
        }
        let lower = value.lowercased()
        guard lower.hasPrefix("http://") ||
              lower.hasPrefix("https://") ||
              lower.hasPrefix("//") ||
              lower.hasPrefix("/") else {
            return false
        }
        let path = (URL(string: value.hasPrefix("//") ? "https:\(value)" : value)?.path ?? value).lowercased()
        let skippedExtensions: Set<String> = [
            "apng", "avif", "bmp", "css", "gif", "ico", "jpeg", "jpg",
            "js", "json", "png", "svg", "webp", "woff", "woff2"
        ]
        if let ext = path.split(separator: ".").last.map(String.init),
           skippedExtensions.contains(ext) {
            return false
        }
        return true
    }

    private static func dataAttributeTitleValue(in attributes: [String: String]) -> String? {
        let keys = [
            "title", "aria-label", "data-title", "data-name", "data-caption",
            "data-label", "data-headline"
        ]
        for key in keys {
            guard let value = attributes[key]?.trimmed,
                  !value.isEmpty else {
                continue
            }
            return value
        }
        return nil
    }

    private static func contextualCardTitleValue(fromHTML html: String) -> String? {
        let headingPattern = #"<h[1-6]\b[^>]*>(.*?)</h[1-6]>"#
        if let title = firstContextualTitle(inHTML: html, pattern: headingPattern) {
            return title
        }

        guard let regex = try? NSRegularExpression(
            pattern: #"<([a-zA-Z][A-Za-z0-9:-]*)\b([^>]*)>(.*?)</\1>"#,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        ) else {
            return nil
        }
        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        for match in regex.matches(in: html, range: range) {
            guard let attributesRange = Range(match.range(at: 2), in: html),
                  let bodyRange = Range(match.range(at: 3), in: html) else {
                continue
            }
            let attributes = attributeValues(from: String(html[attributesRange]))
            guard attributesLookLikeTitleContainer(attributes),
                  let title = cleanContextualTitle(String(html[bodyRange])) else {
                continue
            }
            return title
        }
        return nil
    }

    private static func firstContextualTitle(inHTML html: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(
            pattern: pattern,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        ) else {
            return nil
        }
        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        for match in regex.matches(in: html, range: range) {
            guard let bodyRange = Range(match.range(at: 1), in: html),
                  let title = cleanContextualTitle(String(html[bodyRange])) else {
                continue
            }
            return title
        }
        return nil
    }

    private static func attributesLookLikeTitleContainer(_ attributes: [String: String]) -> Bool {
        if let itemprop = attributes["itemprop"]?.lowercased() {
            let tokens = itemprop.split { $0 == " " || $0 == "\t" || $0 == "\n" || $0 == "\r" || $0 == "," }
            if tokens.contains(where: { ["name", "headline", "title"].contains(String($0)) }) {
                return true
            }
        }
        let keys = ["class", "id", "data-testid", "data-test-id", "data-role", "role"]
        let needles = ["title", "headline", "caption", "subject", "entry-title", "post-title", "result-title", "card-title"]
        return keys.compactMap { attributes[$0]?.lowercased() }.contains { value in
            needles.contains { value.contains($0) }
        }
    }

    private static func cleanContextualTitle(_ raw: String) -> String? {
        let title = decodeHTML(stripTags(raw)).sanitizedFilename(maxLength: 100).trimmed
        guard !title.isEmpty else { return nil }
        let lower = title.lowercased()
        let weakTitles: Set<String> = ["download", "open", "view", "more", "read more", "image", "thumbnail"]
        guard !weakTitles.contains(lower),
              !lower.hasPrefix("http://"),
              !lower.hasPrefix("https://"),
              !lower.contains("://") else {
            return nil
        }
        return title
    }

    private static func jsonLDAnchorEntries(from html: String, baseURL: URL? = nil) -> [AnchorEntry] {
        guard let regex = try? NSRegularExpression(
            pattern: #"<script\b([^>]*)>(.*?)</script>"#,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        ) else {
            return []
        }

        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        var entries: [AnchorEntry] = []
        var seen = Set<String>()

        for match in regex.matches(in: html, range: range) {
            guard let attributesRange = Range(match.range(at: 1), in: html),
                  let bodyRange = Range(match.range(at: 2), in: html) else {
                continue
            }
            let attributes = attributeValues(from: String(html[attributesRange]))
            let type = attributes["type"]?.lowercased() ?? ""
            guard type.contains("ld+json") else { continue }

            let payload = cleanJSONLDPayload(String(html[bodyRange]))
            guard let data = payload.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) else {
                continue
            }

            for candidate in jsonLDLinkCandidates(from: object) {
                let url = normalizedHref(candidate.url, baseURL: baseURL) ?? candidate.url
                guard !seen.contains(url) else { continue }
                seen.insert(url)
                var linkAttributes = candidate.attributes
                linkAttributes["href"] = url
                linkAttributes["title"] = candidate.title
                let context = [
                    candidate.title,
                    candidate.attributes["data-author-name"] ?? "",
                    candidate.attributes["data-date"] ?? ""
                ]
                    .map { $0.trimmed }
                    .filter { !$0.isEmpty }
                    .joined(separator: " ")
                entries.append(AnchorEntry(
                    attributes: linkAttributes,
                    body: candidate.title,
                    context: context,
                    contextHTML: jsonLDContextHTML(title: candidate.title, url: url, attributes: candidate.attributes)
                ))
            }
        }

        return entries
    }

    private static func jsonStateAnchorEntries(from html: String, baseURL: URL?, resolutionBaseURL: URL?) -> [AnchorEntry] {
        guard let regex = try? NSRegularExpression(
            pattern: #"<script\b([^>]*)>(.*?)</script>"#,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        ) else {
            return []
        }

        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        var entries: [AnchorEntry] = []
        var seen = Set<String>()

        for match in regex.matches(in: html, range: range) {
            guard let attributesRange = Range(match.range(at: 1), in: html),
                  let bodyRange = Range(match.range(at: 2), in: html) else {
                continue
            }

            let attributes = attributeValues(from: String(html[attributesRange]))
            guard jsonStateScriptLooksRelevant(attributes) else { continue }

            let payload = cleanJSONStatePayload(String(html[bodyRange]))
            guard !payload.isEmpty,
                  let data = payload.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) else {
                continue
            }

            for candidate in jsonStateLinkCandidates(from: object, baseURL: baseURL) {
                let href = normalizedHref(candidate.href, baseURL: resolutionBaseURL) ?? candidate.href
                guard !seen.contains(href) else { continue }
                seen.insert(href)

                var linkAttributes = candidate.attributes
                linkAttributes["href"] = href
                if linkAttributes["title"] == nil {
                    linkAttributes["title"] = candidate.title
                }
                entries.append(AnchorEntry(
                    attributes: linkAttributes,
                    body: candidate.title,
                    context: candidate.context,
                    contextHTML: candidate.contextHTML
                ))
            }
        }

        return entries
    }

    private static func jsonStateScriptLooksRelevant(_ attributes: [String: String]) -> Bool {
        let type = attributes["type"]?.lowercased() ?? ""
        if type.contains("ld+json") {
            return false
        }
        if type.contains("json") {
            return true
        }
        let id = attributes["id"]?.lowercased() ?? ""
        return id.contains("__next_data__") ||
            id.contains("__nuxt") ||
            id.contains("initial-state") ||
            id.contains("initial_state") ||
            id.contains("app-state") ||
            id.contains("app_state")
    }

    private static func cleanJSONStatePayload(_ raw: String) -> String {
        cleanJSONLDPayload(raw)
    }

    private static func jsonStateLinkCandidates(from value: Any, baseURL: URL?) -> [JSONStateLinkCandidate] {
        var candidates: [JSONStateLinkCandidate] = []
        jsonStateCollectCandidates(from: value, baseURL: baseURL, candidates: &candidates)
        return candidates
    }

    private static func jsonStateCollectCandidates(from value: Any, baseURL: URL?, candidates: inout [JSONStateLinkCandidate]) {
        if let array = value as? [Any] {
            for item in array {
                jsonStateCollectCandidates(from: item, baseURL: baseURL, candidates: &candidates)
            }
            return
        }

        guard let object = value as? [String: Any] else {
            return
        }

        if let candidate = jsonStateCandidate(from: object, baseURL: baseURL) {
            candidates.append(candidate)
        }

        for child in object.values {
            jsonStateCollectCandidates(from: child, baseURL: baseURL, candidates: &candidates)
        }
    }

    private static func jsonStateCandidate(from object: [String: Any], baseURL: URL?) -> JSONStateLinkCandidate? {
        let attributes = jsonStateAttributes(from: object)
        let title = jsonStateTitleValue(in: object, attributes: attributes)
        let href = jsonStateHrefValue(in: object, attributes: attributes, baseURL: baseURL)

        guard let href,
              let title,
              !title.isEmpty else {
            return nil
        }

        var linkAttributes = attributes
        linkAttributes["title"] = title
        let contextHTML = jsonStateContextHTML(title: title, href: href, attributes: linkAttributes)
        let context = [
            title,
            linkAttributes["data-author-name"] ?? "",
            linkAttributes["data-uploader-name"] ?? "",
            linkAttributes["data-date"] ?? "",
            linkAttributes["data-created-at"] ?? ""
        ]
            .map { $0.trimmed }
            .filter { !$0.isEmpty }
            .joined(separator: " ")

        return JSONStateLinkCandidate(
            href: href,
            title: title,
            attributes: linkAttributes,
            context: context,
            contextHTML: contextHTML
        )
    }

    private static func jsonStateHrefValue(in object: [String: Any], attributes: [String: String], baseURL: URL?) -> String? {
        let keys = [
            "url", "href", "link", "permalink", "canonicalURL", "canonicalUrl",
            "canonical_url", "webUrl", "webURL", "web_url", "pageUrl", "pageURL",
            "page_url", "resultUrl", "resultURL", "result_url", "destinationUrl",
            "destinationURL", "destination_url", "path", "pathname", "slug"
        ]
        for key in keys {
            guard let raw = jsonStateStringValue(object[key])?.trimmed,
                  let href = dataAttributeNavigationCandidate(from: raw, baseURL: baseURL) else {
                continue
            }
            return href
        }

        return dataAttributeLinkValue(in: attributes, baseURL: baseURL)
    }

    private static func jsonStateTitleValue(in object: [String: Any], attributes: [String: String]) -> String? {
        let keys = [
            "title", "name", "headline", "caption", "label", "displayTitle",
            "display_title", "alt", "text"
        ]
        for key in keys {
            guard let raw = jsonStateStringValue(object[key])?.trimmed,
                  let title = cleanContextualTitle(raw) else {
                continue
            }
            return title
        }
        return dataAttributeTitleValue(in: attributes).flatMap(cleanContextualTitle)
    }

    private static func jsonStateAttributes(from object: [String: Any]) -> [String: String] {
        var attributes: [String: String] = [:]
        for (key, value) in object {
            guard let string = jsonStateStringValue(value)?.trimmed,
                  !string.isEmpty,
                  string.count <= 500 else {
                continue
            }

            let normalized = jsonStateAttributeName(from: key)
            guard !normalized.isEmpty else { continue }
            attributes[normalized] = string
            if normalized.hasPrefix("data-") {
                attributes[String(normalized.dropFirst("data-".count))] = string
            } else {
                attributes["data-\(normalized)"] = string
            }
        }

        jsonStateAliasPairs.forEach { alias, keys in
            guard attributes[alias] == nil else { return }
            for key in keys {
                if let value = attributes[key]?.trimmed, !value.isEmpty {
                    attributes[alias] = value
                    break
                }
            }
        }

        return DownloadMetadata.clean(attributes)
    }

    private static let jsonStateAliasPairs: [(String, [String])] = [
        ("data-id", ["id", "data-id", "post-id", "data-post-id", "gallery-id", "data-gallery-id", "video-id", "data-video-id", "artwork-id", "data-artwork-id", "illust-id", "data-illust-id", "project-id", "data-project-id"]),
        ("data-title", ["title", "data-title", "name", "data-name", "headline", "data-headline", "caption", "data-caption", "display-title", "data-display-title"]),
        ("data-name", ["name", "data-name", "title", "data-title"]),
        ("data-type", ["type", "data-type", "kind", "data-kind", "content-type", "data-content-type"]),
        ("data-url", ["url", "data-url", "href", "data-href", "permalink", "data-permalink", "canonical-url", "data-canonical-url", "page-url", "data-page-url", "result-url", "data-result-url"]),
        ("data-href", ["href", "data-href", "url", "data-url"]),
        ("data-artist-name", ["artist-name", "data-artist-name", "artist", "data-artist", "author", "data-author", "author-name", "data-author-name", "user-name", "data-user-name", "username", "data-username"]),
        ("data-uploader-name", ["uploader-name", "data-uploader-name", "uploader", "data-uploader", "author-name", "data-author-name", "channel-name", "data-channel-name"]),
        ("data-channel-name", ["channel-name", "data-channel-name", "channel", "data-channel", "uploader-name", "data-uploader-name"]),
        ("data-user-id", ["user-id", "data-user-id", "uid", "data-uid", "uploader-id", "data-uploader-id", "author-id", "data-author-id"]),
        ("data-created-at", ["created-at", "data-created-at", "date", "data-date", "published-at", "data-published-at", "upload-date", "data-upload-date"]),
        ("data-date", ["date", "data-date", "created-at", "data-created-at", "published-at", "data-published-at", "upload-date", "data-upload-date"]),
        ("data-thumbnail", ["thumbnail", "data-thumbnail", "thumbnail-url", "data-thumbnail-url", "image", "data-image"])
    ]

    private static func jsonStateAttributeName(from key: String) -> String {
        let kebab = key
            .replacingOccurrences(of: #"([a-z0-9])([A-Z])"#, with: "$1-$2", options: .regularExpression)
            .replacingOccurrences(of: "_", with: "-")
            .replacingOccurrences(of: ".", with: "-")
            .lowercased()
            .filter { character in
                character.isLetter || character.isNumber || character == "-"
            }
        return String(kebab)
            .replacingOccurrences(of: #"-+"#, with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }

    private static func jsonStateStringValue(_ value: Any?) -> String? {
        if let string = value as? String {
            return decodeHTML(string)
        }
        if let number = value as? NSNumber {
            return number.stringValue
        }
        if let urlObject = value as? [String: Any] {
            for key in ["url", "href", "path", "slug", "name", "title", "text"] {
                if let string = jsonStateStringValue(urlObject[key])?.trimmed,
                   !string.isEmpty {
                    return string
                }
            }
        }
        return nil
    }

    private static func jsonStateContextHTML(title: String, href: String, attributes: [String: String]) -> String {
        var parts = [#"data-json-state="1""#, #"href="\#(href)""#, #"title="\#(title)""#]
        for key in attributes.keys.sorted() {
            guard let value = attributes[key], !value.isEmpty else { continue }
            parts.append(#"\#(key)="\#(value)""#)
        }
        return "<a \(parts.joined(separator: " "))>\(title)</a>"
    }

    private static func cleanJSONLDPayload(_ raw: String) -> String {
        decodeHTML(raw)
            .replacingOccurrences(of: "<!--", with: "")
            .replacingOccurrences(of: "-->", with: "")
            .replacingOccurrences(of: "//<![CDATA[", with: "")
            .replacingOccurrences(of: "//]]>", with: "")
            .trimmed
    }

    private static func jsonLDLinkCandidates(
        from value: Any,
        blocked: Bool = false,
        inListContext: Bool = false
    ) -> [JSONLDLinkCandidate] {
        if let array = value as? [Any] {
            return array.flatMap { jsonLDLinkCandidates(from: $0, blocked: blocked, inListContext: inListContext) }
        }

        guard let object = value as? [String: Any] else {
            return []
        }

        let typeNames = jsonLDTypeNames(object["@type"]).map { $0.lowercased() }
        let currentBlocked = blocked || typeNames.contains("breadcrumblist") || typeNames.contains("searchaction")
        let childListContext = inListContext || typeNames.contains("itemlist") || object.keys.contains { $0.caseInsensitiveCompare("itemListElement") == .orderedSame }
        var candidates: [JSONLDLinkCandidate] = []

        if !currentBlocked,
           jsonLDShouldEmitCandidate(types: typeNames, inListContext: inListContext),
           let url = jsonLDURLValue(in: object),
           let title = jsonLDTitleValue(in: object) {
            candidates.append(JSONLDLinkCandidate(
                url: url,
                title: title,
                attributes: jsonLDSemanticAttributes(from: object),
                contextHTML: jsonLDContextHTML(title: title, url: url, attributes: jsonLDSemanticAttributes(from: object))
            ))
        }

        for child in object.values {
            candidates.append(contentsOf: jsonLDLinkCandidates(from: child, blocked: currentBlocked, inListContext: childListContext))
        }

        return candidates
    }

    private static func jsonLDShouldEmitCandidate(types: [String], inListContext: Bool) -> Bool {
        let blockedTypes = [
            "website", "searchaction", "breadcrumblist", "organization",
            "person", "place", "brand", "aggregateoffer", "offer"
        ]
        if types.contains(where: { blockedTypes.contains($0) }) {
            return false
        }
        let contentTypes = [
            "article", "blogposting", "creativework", "comicissue", "comicstory",
            "episode", "imagegallery", "imageobject", "mediaobject", "movie",
            "musicrecording", "newsarticle", "photograph", "product",
            "socialmediaposting", "videoobject", "webpage"
        ]
        return types.contains(where: { contentTypes.contains($0) }) ||
            (inListContext && !types.contains("itemlist"))
    }

    private static func jsonLDTypeNames(_ value: Any?) -> [String] {
        if let string = value as? String {
            return [string]
        }
        if let array = value as? [Any] {
            return array.compactMap { $0 as? String }
        }
        return []
    }

    private static func jsonLDURLValue(in object: [String: Any]) -> String? {
        for key in ["url", "mainEntityOfPage", "@id"] {
            guard let value = jsonLDStringValue(object[key])?.trimmed,
                  !value.isEmpty,
                  !value.hasPrefix("#"),
                  !value.lowercased().contains("schema.org") else {
                continue
            }
            return value
        }
        return nil
    }

    private static func jsonLDTitleValue(in object: [String: Any]) -> String? {
        for key in ["name", "headline", "title", "caption"] {
            guard let value = jsonLDStringValue(object[key])?.trimmed,
                  !value.isEmpty else {
                continue
            }
            return decodeHTML(value).sanitizedFilename(maxLength: 100)
        }
        return nil
    }

    private static func jsonLDStringValue(_ value: Any?) -> String? {
        if let string = value as? String {
            return string
        }
        if let object = value as? [String: Any] {
            for key in ["url", "@id", "name"] {
                if let string = object[key] as? String,
                   !string.trimmed.isEmpty {
                    return string
                }
            }
        }
        if let array = value as? [Any] {
            for item in array {
                if let string = jsonLDStringValue(item),
                   !string.trimmed.isEmpty {
                    return string
                }
            }
        }
        return nil
    }

    private static func jsonLDNameValue(_ value: Any?) -> String? {
        if let string = value as? String {
            return string.trimmed.isEmpty ? nil : string
        }
        if let object = value as? [String: Any] {
            return jsonLDStringValue(object["name"])
        }
        if let array = value as? [Any] {
            return array.compactMap { jsonLDNameValue($0) }.first
        }
        return nil
    }

    private static func jsonLDSemanticAttributes(from object: [String: Any]) -> [String: String] {
        var attributes: [String: String] = [:]
        if let author = jsonLDNameValue(object["author"]) {
            attributes["data-author-name"] = author
            attributes["data-uploader-name"] = author
            attributes["data-channel-name"] = author
        }
        if let creator = jsonLDNameValue(object["creator"]) {
            attributes["data-creator-name"] = creator
        }
        if let publisher = jsonLDNameValue(object["publisher"]) {
            attributes["data-publisher-name"] = publisher
        }
        if let date = jsonLDStringValue(object["datePublished"] ?? object["uploadDate"] ?? object["dateCreated"] ?? object["dateModified"]) {
            attributes["data-date"] = date
            attributes["data-created-at"] = date
        }
        if let image = jsonLDStringValue(object["thumbnailUrl"] ?? object["image"]) {
            attributes["data-thumbnail"] = image
        }
        return DownloadMetadata.clean(attributes)
    }

    private static func jsonLDContextHTML(title: String, url: String, attributes: [String: String]) -> String {
        var parts = [#"data-jsonld="1""#, #"href="\#(url)""#, #"title="\#(title)""#]
        for key in attributes.keys.sorted() {
            guard let value = attributes[key], !value.isEmpty else { continue }
            parts.append(#"\#(key)="\#(value)""#)
        }
        return "<a \(parts.joined(separator: " "))>\(title)</a>"
    }

    private static func contextSlice(around range: Range<String.Index>, in html: String) -> String {
        let prefixDistance = html.distance(from: html.startIndex, to: range.lowerBound)
        let suffixDistance = html.distance(from: range.upperBound, to: html.endIndex)
        let before = min(600, prefixDistance)
        let after = min(600, suffixDistance)
        let start = html.index(range.lowerBound, offsetBy: -before)
        let end = html.index(range.upperBound, offsetBy: after)
        return String(html[start..<end])
    }

    private static func documentBaseURL(from html: String, fallback: URL) -> URL {
        guard let regex = try? NSRegularExpression(
            pattern: #"<base\b([^>]*)>"#,
            options: [.caseInsensitive]
        ) else {
            return fallback
        }
        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        for match in regex.matches(in: html, range: range) {
            guard let attributesRange = Range(match.range(at: 1), in: html) else { continue }
            let attributes = attributeValues(from: String(html[attributesRange]))
            guard let href = attributes["href"]?.trimmed,
                  let url = URL(string: href, relativeTo: fallback)?.absoluteURL,
                  let scheme = url.scheme?.lowercased(),
                  scheme == "http" || scheme == "https" else {
                continue
            }
            return url
        }
        return fallback
    }

    private static func normalizedHref(_ href: String?, baseURL: URL?) -> String? {
        guard let href = href?.trimmed,
              let baseURL,
              let absolute = resolve(href: href, baseURL: baseURL) else {
            return nil
        }
        return absolute.absoluteString
    }

    private static func resolve(href: String, baseURL: URL) -> URL? {
        guard !href.isEmpty,
              !href.hasPrefix("#"),
              !href.lowercased().hasPrefix("javascript:"),
              !href.lowercased().hasPrefix("mailto:") else {
            return nil
        }
        return URL(string: href, relativeTo: baseURL)?.absoluteURL
    }

    private static func isUseful(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
            return false
        }
        return true
    }

    private static func displayTitle(for anchor: AnchorEntry, fallbackURL: URL) -> String {
        displayTitle(for: anchor, fallback: fallbackURL.lastPathComponentOrHost)
    }

    private static func displayTitle(for anchor: AnchorEntry, fallback: String) -> String {
        let raw = [
            anchor.attributes["title"],
            anchor.attributes["aria-label"],
            embeddedImageTitle(from: anchor.body),
            stripTags(anchor.body),
            contextualCardTitleValue(fromHTML: anchor.contextHTML)
        ]
            .compactMap { $0?.trimmed }
            .first { !$0.isEmpty } ?? fallback

        let title = decodeHTML(raw).sanitizedFilename(maxLength: 100)
        return title == "download" ? fallback.sanitizedFilename(maxLength: 100) : title
    }

    private static func firstCapture(in text: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              match.numberOfRanges > 1,
              let capture = Range(match.range(at: 1), in: text) else {
            return nil
        }
        return String(text[capture])
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

    private static func stripTags(_ text: String) -> String {
        text.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmed
    }

    private static func embeddedImageTitle(from html: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: #"<img\b([^>]*)>"#, options: [.caseInsensitive]) else {
            return nil
        }
        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        for match in regex.matches(in: html, range: range) {
            guard let attributesRange = Range(match.range(at: 1), in: html) else { continue }
            let attributes = attributeValues(from: String(html[attributesRange]))
            if let title = attributes["alt"]?.trimmed, !title.isEmpty {
                return title
            }
            if let title = attributes["title"]?.trimmed, !title.isEmpty {
                return title
            }
        }
        return nil
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

struct AnchorEntry {
    var attributes: [String: String]
    var body: String
    var context: String
    var contextHTML: String
}

private struct JSONLDLinkCandidate {
    var url: String
    var title: String
    var attributes: [String: String]
    var contextHTML: String
}

private struct JSONStateLinkCandidate {
    var href: String
    var title: String
    var attributes: [String: String]
    var context: String
    var contextHTML: String
}

private extension URL {
    var lastPathComponentOrHost: String {
        if !lastPathComponent.isEmpty {
            return lastPathComponent
        }
        return host ?? absoluteString
    }
}

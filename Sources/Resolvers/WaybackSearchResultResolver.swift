import Foundation

struct WaybackSearchResultResolver: SearchResultResolving {
    func supports(_ baseURL: URL) -> Bool {
        guard let host = baseURL.host?.lowercased() else { return false }
        return Self.isSupportedHost(host)
    }

    static func isSupportedHost(_ host: String) -> Bool {
        host == "web.archive.org" ||
            host == "archive.org" ||
            host == "web.archive.org.test" ||
            host == "archive.org.test"
    }

    static func dataAttributeLinkValue(
        in attributes: [String: String],
        baseURL: URL?
    ) -> String? {
        guard let baseURL,
              let host = baseURL.host?.lowercased(),
              isSupportedHost(host),
              let targetURL = dataAttributeTargetURL(in: attributes),
              dataAttributeLooksLikeArchiveCard(attributes),
              !dataAttributeLooksLikeNavigation(attributes) else {
            return nil
        }

        if let token = dataAttributeTimestamp(in: attributes) {
            return "/web/\(token)/\(targetURL.absoluteString)"
        }

        return cdxRelativeURL(targetURL: targetURL)
    }

    func extract(from context: SearchResultResolverContext) -> [SearchResultLink] {
        var results: [SearchResultLink] = []
        var indexByTarget: [String: Int] = [:]

        for anchor in context.anchors {
            guard results.count < context.limit,
                  let absolute = context.resolvedURL(for: anchor),
                  let target = WaybackMachineResolver.targetURL(from: absolute),
                  let queueURL = Self.queueURL(
                      from: absolute,
                      targetURL: target
                  ) else {
                continue
            }

            let title = context.title(for: anchor, fallbackURL: target)
            SearchResultResolverSupport.appendUniqueResult(
                title: title,
                url: queueURL,
                id: URLIdentity.normalize(target.absoluteString),
                sitePrefix: "wayback",
                results: &results,
                indexByID: &indexByTarget,
                metadata: metadata(
                    originalURL: target,
                    sourceURL: absolute,
                    queueURL: queueURL,
                    title: title,
                    contributorMetadata: context.contributorMetadata(
                        for: anchor
                    )
                )
            )
        }

        return results
    }

    private func metadata(
        originalURL: URL,
        sourceURL: URL,
        queueURL: URL,
        title: String,
        contributorMetadata: [String: String]
    ) -> [String: String] {
        let timestamp = Self.timestamp(from: sourceURL) ??
            Self.timestamp(from: queueURL)
        let normalizedTarget = URLIdentity.normalize(originalURL.absoluteString)
        var metadata = contributorMetadata
        metadata.merge([
            "id": timestamp ?? normalizedTarget,
            "original_url": originalURL.absoluteString,
            "target_url": originalURL.absoluteString,
            "target_host": originalURL.host ?? "",
            "host": originalURL.host ?? "",
            "archive_url": queueURL.absoluteString,
            "category": "wayback",
            "type": timestamp == nil ? "cdx" : "snapshot",
            "title": title,
            "search_title": title
        ]) { current, _ in current }
        if let timestamp {
            metadata["post_id"] = timestamp
            metadata["snapshot_id"] = timestamp
            metadata["timestamp"] = timestamp
            metadata["archive_timestamp"] = timestamp
            metadata["media_id"] = timestamp
            metadata["date"] = Self.date(from: timestamp)
        } else {
            metadata["gallery_id"] = normalizedTarget
        }
        return DownloadMetadata.clean(metadata)
    }

    private static func dataAttributeTargetURL(
        in attributes: [String: String]
    ) -> URL? {
        let keys = [
            "data-original-url", "data-original", "data-target-url",
            "data-target", "data-page-url", "data-source-url",
            "data-url", "original-url", "target-url"
        ]
        for key in keys {
            guard let raw = attributes[key]?.trimmed,
                  let url = dataAttributeTargetURL(from: raw) else {
                continue
            }
            return url
        }
        return nil
    }

    private static func dataAttributeTargetURL(from raw: String) -> URL? {
        let decoded = raw.removingPercentEncoding?.trimmed ?? raw.trimmed
        guard decoded.lowercased().hasPrefix("http://") ||
                decoded.lowercased().hasPrefix("https://"),
              let url = URL(string: decoded),
              let host = url.host?.lowercased(),
              url.scheme?.lowercased().hasPrefix("http") == true else {
            return nil
        }
        if isSupportedHost(host),
           let target = WaybackMachineResolver.targetURL(from: url) {
            return target
        }
        return url
    }

    private static func dataAttributeTimestamp(
        in attributes: [String: String]
    ) -> String? {
        firstAttributeValue(
            in: attributes,
            keys: [
                "data-timestamp", "data-snapshot-timestamp",
                "data-archive-timestamp", "data-wayback-timestamp",
                "data-snapshot-id", "timestamp", "snapshot-id"
            ],
            matching: isArchiveToken
        )
    }

    private static func dataAttributeLooksLikeArchiveCard(
        _ attributes: [String: String]
    ) -> Bool {
        let markerKeys = [
            "data-original-url", "data-original", "data-target-url",
            "data-target", "data-timestamp", "data-snapshot-timestamp",
            "data-archive-timestamp", "data-wayback-timestamp"
        ]
        if markerKeys.contains(where: {
            attributes[$0]?.trimmed.isEmpty == false
        }) {
            return true
        }
        return typeHint(
            in: attributes,
            containsAnyOf: ["wayback", "archive", "snapshot", "cdx"]
        )
    }

    private static func dataAttributeLooksLikeNavigation(
        _ attributes: [String: String]
    ) -> Bool {
        typeHint(
            in: attributes,
            containsAnyOf: [
                "save", "navigation", "nav", "toolbar", "button"
            ]
        )
    }

    private static func isArchiveToken(_ value: String) -> Bool {
        value.range(
            of: #"^[0-9]{1,14}[A-Za-z_]*$"#,
            options: .regularExpression
        ) != nil
    }

    private static func cdxRelativeURL(targetURL: URL) -> String? {
        var components = URLComponents()
        components.path = "/cdx/search/cdx"
        components.queryItems = [
            URLQueryItem(name: "url", value: targetURL.absoluteString)
        ]
        return components.string
    }

    private static func queueURL(from url: URL, targetURL: URL) -> URL? {
        let path = url.path.removingPercentEncoding ?? url.path
        if path.lowercased() == "/cdx/search/cdx" {
            return WaybackMachineResolver.cdxAPIURL(
                targetURL: targetURL,
                sourceURL: url
            )
        }

        guard path.hasPrefix("/web/") else { return nil }
        let rest = String(path.dropFirst("/web/".count))
        guard let slash = rest.firstIndex(of: "/") else { return nil }
        let token = String(rest[..<slash])
        guard token == "*" || isArchiveToken(token) else {
            return nil
        }

        var components = URLComponents()
        components.scheme = url.scheme ?? "https"
        components.host = url.host?.lowercased().hasSuffix(".test") == true
            ? "web.archive.org.test"
            : "web.archive.org"
        components.path = "/web/\(token)/\(targetURL.absoluteString)"
        return components.url
    }

    private static func timestamp(from url: URL) -> String? {
        let path = url.path.removingPercentEncoding ?? url.path
        guard path.hasPrefix("/web/") else { return nil }
        let rest = String(path.dropFirst("/web/".count))
        guard let slash = rest.firstIndex(of: "/") else { return nil }
        let token = String(rest[..<slash])
        guard let match = token.range(
            of: #"^[0-9]{1,14}"#,
            options: .regularExpression
        ) else {
            return nil
        }
        return String(token[match])
    }

    private static func date(from timestamp: String) -> String? {
        guard timestamp.count >= 8 else { return nil }
        let year = String(timestamp.prefix(4))
        let monthStart = timestamp.index(timestamp.startIndex, offsetBy: 4)
        let monthEnd = timestamp.index(monthStart, offsetBy: 2)
        let dayEnd = timestamp.index(monthEnd, offsetBy: 2)
        return "\(year)-\(timestamp[monthStart..<monthEnd])-" +
            "\(timestamp[monthEnd..<dayEnd])"
    }

    private static func firstAttributeValue(
        in attributes: [String: String],
        keys: [String],
        matching predicate: (String) -> Bool
    ) -> String? {
        for key in keys {
            if let value = attributes[key]?.trimmed, predicate(value) {
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
}

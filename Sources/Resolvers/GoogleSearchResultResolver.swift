import Foundation

struct GoogleSearchResultResolver: SearchResultResolving {
    func supports(_ baseURL: URL) -> Bool {
        guard let host = baseURL.host?.lowercased() else { return false }
        return Self.isGoogleHost(host)
    }

    static func dataAttributeLinkValue(
        in attributes: [String: String],
        baseURL: URL?
    ) -> String? {
        guard let baseURL,
              let host = baseURL.host?.lowercased(),
              isGoogleHost(host),
              !dataAttributeLooksLikeNavigation(attributes) else {
            return nil
        }

        let keys = [
            "data-rw", "data-amp-cur", "data-result-url",
            "data-destination-url", "data-target-url", "data-target",
            "data-href", "data-url", "data-link"
        ]
        for key in keys {
            guard let raw = attributes[key]?.trimmed,
                  looksLikeDataAttributeLink(raw),
                  let absolute = URL(
                      string: raw,
                      relativeTo: baseURL
                  )?.absoluteURL,
                  targetURL(from: absolute) != nil else {
                continue
            }
            return raw
        }
        return nil
    }

    func extract(from context: SearchResultResolverContext) -> [SearchResultLink] {
        var results: [SearchResultLink] = []
        var seen = Set<String>()

        for anchor in context.anchors {
            guard results.count < context.limit,
                  let redirectURL = context.resolvedURL(for: anchor),
                  let targetURL = Self.targetURL(from: redirectURL) else {
                continue
            }

            let queueURL = context.canonicalQueueURL(for: targetURL)
            let normalized = URLIdentity.normalize(queueURL.absoluteString)
            guard seen.insert(normalized).inserted else { continue }

            let title = context.title(for: anchor, fallbackURL: queueURL)
            results.append(SearchResultLink(
                title: title,
                url: queueURL.absoluteString,
                siteIdentifier: "google",
                metadata: metadata(
                    context: context,
                    anchor: anchor,
                    redirectURL: redirectURL,
                    targetURL: targetURL,
                    queueURL: queueURL,
                    title: title
                )
            ))
        }

        return results
    }

    static func targetURL(from url: URL) -> URL? {
        guard let host = url.host?.lowercased() else { return nil }
        guard isGoogleHost(host) else {
            return isUseful(url) ? url : nil
        }

        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return nil
        }
        for name in ["q", "url", "u", "imgurl"] {
            guard let raw = queryValue(name, in: components.queryItems ?? [])?.trimmed,
                  !raw.isEmpty else {
                continue
            }
            let decoded = raw.removingPercentEncoding ?? raw
            for candidate in [decoded, raw] {
                let target: URL?
                if candidate.hasPrefix("//") {
                    target = URL(string: "\(url.scheme ?? "https"):\(candidate)")
                } else if candidate.contains("://") {
                    target = URL(string: candidate)
                } else {
                    target = nil
                }
                guard let target,
                      isUseful(target),
                      let targetHost = target.host?.lowercased(),
                      !isGoogleHost(targetHost) else {
                    continue
                }
                return target
            }
        }
        return nil
    }

    static func isGoogleHost(_ host: String) -> Bool {
        host == "google.com" ||
            host.hasSuffix(".google.com") ||
            host.hasPrefix("google.") ||
            host.hasPrefix("www.google.")
    }

    private func metadata(
        context: SearchResultResolverContext,
        anchor: AnchorEntry,
        redirectURL: URL,
        targetURL: URL,
        queueURL: URL,
        title: String
    ) -> [String: String] {
        var metadata = context.contributorMetadata(for: anchor)
        let targetHost = targetURL.host ?? ""
        metadata.merge([
            "site": "google",
            "search_site": "google",
            "source_url": queueURL.absoluteString,
            "page_url": queueURL.absoluteString,
            "search_page_url": context.baseURL.absoluteString,
            "redirect_url": redirectURL.absoluteString,
            "target_url": targetURL.absoluteString,
            "target_host": targetHost,
            "host": targetHost,
            "queue_url": queueURL.absoluteString,
            "category": "search_redirect",
            "type": "link",
            "title": title,
            "search_title": title
        ]) { current, _ in current }
        if queueURL.absoluteString != targetURL.absoluteString {
            metadata["canonical_url"] = queueURL.absoluteString
        }
        return DownloadMetadata.clean(metadata)
    }

    private static func queryValue(_ name: String, in items: [URLQueryItem]) -> String? {
        items.first { $0.name.lowercased() == name.lowercased() }?.value
    }

    private static func isUseful(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased() else { return false }
        return scheme == "http" || scheme == "https"
    }

    private static func dataAttributeLooksLikeNavigation(
        _ attributes: [String: String]
    ) -> Bool {
        typeHint(
            in: attributes,
            containsAnyOf: [
                "settings", "preference", "navigation", "nav", "menu",
                "login", "account"
            ]
        )
    }

    private static func looksLikeDataAttributeLink(
        _ value: String
    ) -> Bool {
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
        let candidate = value.hasPrefix("//") ? "https:\(value)" : value
        let path = (URL(string: candidate)?.path ?? value).lowercased()
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

    private static func typeHint(
        in attributes: [String: String],
        containsAnyOf needles: [String]
    ) -> Bool {
        let keys = [
            "data-type", "data-kind", "data-content-type",
            "data-renderer", "class", "role"
        ]
        let values = keys.compactMap {
            attributes[$0]?.lowercased()
        }
        return values.contains { value in
            needles.contains { value.contains($0) }
        }
    }
}

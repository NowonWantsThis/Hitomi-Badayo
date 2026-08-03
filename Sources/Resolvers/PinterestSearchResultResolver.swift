import Foundation

struct PinterestSearchResultResolver: SearchResultResolving {
    func supports(_ baseURL: URL) -> Bool {
        guard let host = baseURL.host?.lowercased() else { return false }
        return Self.isSupportedHost(host)
    }

    static func isSupportedHost(_ host: String) -> Bool {
        if host == "pinterest.test" || host.hasSuffix(".pinterest.test") {
            return true
        }

        let labels = host.split(separator: ".").map(String.init)
        guard let index = labels.lastIndex(of: "pinterest") else {
            return false
        }
        let suffix = Array(labels.dropFirst(index + 1))
        if suffix.count == 1 {
            let tld = suffix[0]
            return tld == "com" ||
                (tld.count == 2 && tld.allSatisfy(\.isLetter))
        }
        if suffix.count == 2 {
            let service = suffix[0]
            let country = suffix[1]
            return ["co", "com", "net", "org"].contains(service) &&
                country.count == 2 &&
                country.allSatisfy(\.isLetter)
        }
        return false
    }

    static func dataAttributeLinkValue(
        in attributes: [String: String],
        baseURL: URL?
    ) -> String? {
        guard let host = baseURL?.host?.lowercased(),
              isSupportedHost(host),
              let id = dataAttributePinID(in: attributes),
              dataAttributeLooksLikePinCard(attributes) else {
            return nil
        }
        return "/pin/\(id)/"
    }

    func extract(from context: SearchResultResolverContext) -> [SearchResultLink] {
        var results: [SearchResultLink] = []
        var indexByPinID: [String: Int] = [:]

        for anchor in context.anchors {
            guard results.count < context.limit,
                  let absolute = context.resolvedURL(for: anchor),
                  case .pin(let pinID) = PinterestResolver.kind(
                      from: absolute
                  ),
                  let target = Self.cleanedURL(
                      absolute,
                      path: "/pin/\(pinID)/"
                  ) else {
                continue
            }

            let title = context.title(
                for: anchor,
                fallback: "Pinterest \(pinID)"
            )
            SearchResultResolverSupport.appendUniqueResult(
                title: title,
                url: target,
                id: pinID,
                sitePrefix: "pinterest",
                results: &results,
                indexByID: &indexByPinID,
                metadata: metadata(
                    pinID: pinID,
                    title: title,
                    anchor: anchor,
                    target: target,
                    context: context
                )
            )
        }

        return results
    }

    private func metadata(
        pinID: String,
        title: String,
        anchor: AnchorEntry,
        target: URL,
        context: SearchResultResolverContext
    ) -> [String: String] {
        var metadata = [
            "id": pinID,
            "pin_id": pinID,
            "media_id": pinID,
            "gallery_id": pinID,
            "category": "pinterest",
            "type": "pin",
            "title": title,
            "search_title": title
        ]
        let attributes = context.semanticAttributes(for: anchor)
        let profileInfo = userInfo(
            from: anchor.contextHTML,
            baseURL: target,
            context: context
        )
        let displayName = Self.firstSemanticAttribute(
            attributes,
            keys: [
                "data-pinner-name", "data-pinner", "pinner",
                "data-owner-name", "data-owner", "owner",
                "data-creator-name", "data-creator", "creator"
            ]
        ) ?? profileInfo?.name
        let username = Self.firstSemanticAttribute(
            attributes,
            keys: [
                "data-username", "username", "data-user", "data-user-name"
            ]
        ) ?? profileInfo?.username
        let artist = displayName ?? username
        if let artist {
            metadata["artist"] = artist
            metadata["author"] = artist
            metadata["creator"] = artist
            metadata["uploader"] = artist
            metadata["pinner"] = artist
        }
        if let username {
            metadata["user"] = username
            metadata["username"] = username
        }
        return DownloadMetadata.clean(metadata)
    }

    private func userInfo(
        from html: String,
        baseURL: URL,
        context: SearchResultResolverContext
    ) -> (username: String, name: String?)? {
        let reserved: Set<String> = [
            "about", "business", "categories", "explore", "ideas", "login",
            "pin", "privacy", "search", "settings", "today"
        ]
        for entry in context.nestedAnchors(in: html) {
            guard let url = context.resolvedURL(
                for: entry,
                relativeTo: baseURL
            ),
                  let host = url.host?.lowercased(),
                  Self.isSupportedHost(host) else {
                continue
            }
            let parts = url.path
                .split(separator: "/", omittingEmptySubsequences: true)
                .map(String.init)
            guard parts.count == 1,
                  let username = parts.first?.trimmed,
                  !username.isEmpty,
                  !reserved.contains(username.lowercased()) else {
                continue
            }
            let name = context.title(for: entry, fallback: "").trimmed
            return (username, name.isEmpty ? nil : name)
        }
        return nil
    }

    private static func dataAttributePinID(
        in attributes: [String: String]
    ) -> String? {
        let keys = [
            "data-pin-id", "data-pinid", "data-pin",
            "pin-id", "pinid", "pin"
        ]
        if let value = firstAttributeValue(
            in: attributes,
            keys: keys,
            matching: isPinID
        ) {
            return value
        }
        if let id = attributes["data-id"]?.trimmed,
           isPinID(id),
           typeHint(in: attributes, containsAnyOf: ["pin"]) {
            return id
        }
        return nil
    }

    private static func dataAttributeLooksLikePinCard(
        _ attributes: [String: String]
    ) -> Bool {
        let markerKeys = [
            "data-pin-id", "data-pinid", "data-pin",
            "pin-id", "pinid", "pin"
        ]
        if markerKeys.contains(
            where: { attributes[$0]?.trimmed.isEmpty == false }
        ) {
            return true
        }
        if typeHint(
            in: attributes,
            containsAnyOf: ["board", "profile", "user", "account"]
        ) {
            return false
        }
        return typeHint(in: attributes, containsAnyOf: ["pin"])
    }

    private static func isPinID(_ value: String) -> Bool {
        value.range(
            of: #"^[0-9]{4,30}$"#,
            options: .regularExpression
        ) != nil
    }

    private static func firstSemanticAttribute(
        _ attributes: [String: String],
        keys: [String]
    ) -> String? {
        for key in keys {
            guard let value = attributes.first(
                where: { $0.key.lowercased() == key }
            )?.value.trimmed,
                  !value.isEmpty else {
                continue
            }
            return value
        }
        return nil
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

    private static func cleanedURL(
        _ url: URL,
        path: String
    ) -> URL? {
        guard var components = URLComponents(
            url: url,
            resolvingAgainstBaseURL: false
        ) else {
            return nil
        }
        components.path = path
        components.queryItems = nil
        components.fragment = nil
        return components.url
    }
}

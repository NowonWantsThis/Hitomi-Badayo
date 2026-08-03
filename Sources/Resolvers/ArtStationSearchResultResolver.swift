import Foundation

struct ArtStationSearchResultResolver: SearchResultResolving {
    func supports(_ baseURL: URL) -> Bool {
        guard let host = baseURL.host?.lowercased() else { return false }
        return Self.isSupportedHost(host)
    }

    static func isSupportedHost(_ host: String) -> Bool {
        host == "artstation.com" ||
            host == "www.artstation.com" ||
            host == "artstation.test"
    }

    static func dataAttributeLinkValue(
        in attributes: [String: String],
        baseURL: URL?
    ) -> String? {
        guard let host = baseURL?.host?.lowercased(),
              isSupportedHost(host),
              let id = dataAttributeProjectID(in: attributes),
              dataAttributeLooksLikeProjectCard(attributes) else {
            return nil
        }
        return "/artwork/\(id)"
    }

    func extract(from context: SearchResultResolverContext) -> [SearchResultLink] {
        var results: [SearchResultLink] = []
        var indexByProjectID: [String: Int] = [:]

        for anchor in context.anchors {
            guard results.count < context.limit,
                  let absolute = context.resolvedURL(for: anchor),
                  let projectID = Self.projectID(from: absolute),
                  let target = Self.cleanedURL(
                      absolute,
                      path: "/artwork/\(projectID)"
                  ) else {
                continue
            }

            let title = context.title(
                for: anchor,
                fallback: "ArtStation \(projectID)"
            )
            SearchResultResolverSupport.appendUniqueResult(
                title: title,
                url: target,
                id: projectID,
                sitePrefix: "artstation",
                results: &results,
                indexByID: &indexByProjectID,
                metadata: metadata(
                    projectID: projectID,
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
        projectID: String,
        title: String,
        anchor: AnchorEntry,
        target: URL,
        context: SearchResultResolverContext
    ) -> [String: String] {
        var metadata = [
            "id": projectID,
            "project_id": projectID,
            "artwork_id": projectID,
            "media_id": projectID,
            "gallery_id": projectID,
            "category": "artstation",
            "type": "project",
            "title": title,
            "search_title": title
        ]
        let attributes = context.semanticAttributes(for: anchor)
        if let artist = Self.firstSemanticAttribute(
            attributes,
            keys: [
                "data-artist", "data-artist-name", "artist",
                "data-author", "data-author-name", "author",
                "data-user-name", "data-username", "username",
                "data-owner", "owner", "data-creator", "creator"
            ]
        ) ?? profileInfo(
            from: anchor.contextHTML,
            baseURL: target,
            context: context
        )?.name {
            metadata["artist"] = artist
            metadata["author"] = artist
            metadata["creator"] = artist
            metadata["uploader"] = artist
            metadata["username"] = artist
        }
        if let username = Self.firstSemanticAttribute(
            attributes,
            keys: [
                "data-profile", "data-profile-name", "data-user",
                "data-username", "username"
            ]
        ) ?? profileInfo(
            from: anchor.contextHTML,
            baseURL: target,
            context: context
        )?.username {
            metadata["user"] = username
            metadata["username"] = username
        }
        return DownloadMetadata.clean(metadata)
    }

    private func profileInfo(
        from html: String,
        baseURL: URL,
        context: SearchResultResolverContext
    ) -> (username: String, name: String?)? {
        let reserved: Set<String> = [
            "about", "artwork", "blogs", "channels", "community",
            "contests", "jobs", "marketplace", "projects", "search", "store"
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

            if host.hasSuffix(".artstation.com"),
               let username = host.split(separator: ".").first.map(
                   String.init
               ),
               !["www", "magazine", "cdna"].contains(
                   username.lowercased()
               ) {
                let name = context.title(
                    for: entry,
                    fallback: ""
                ).trimmed
                return (username, name.isEmpty ? nil : name)
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

    private static func projectID(from url: URL) -> String? {
        let parts = url.path
            .split(separator: "/", omittingEmptySubsequences: true)
            .map(String.init)
        guard parts.count >= 2,
              ["artwork", "projects"].contains(
                  parts[0].lowercased()
              ) else {
            return nil
        }
        let cleaned = (parts[1] as NSString)
            .deletingPathExtension
            .trimmed
        return cleaned.isEmpty ? nil : cleaned
    }

    private static func dataAttributeProjectID(
        in attributes: [String: String]
    ) -> String? {
        let keys = [
            "data-project-id", "data-projectid", "data-artwork-id",
            "data-artworkid", "project-id", "artwork-id"
        ]
        if let value = firstAttributeValue(
            in: attributes,
            keys: keys,
            matching: isValidPathSlug
        ) {
            return value
        }
        if let id = attributes["data-id"]?.trimmed,
           isValidPathSlug(id),
           typeHint(
               in: attributes,
               containsAnyOf: ["project", "artwork"]
           ) {
            return id
        }
        return nil
    }

    private static func dataAttributeLooksLikeProjectCard(
        _ attributes: [String: String]
    ) -> Bool {
        let markerKeys = [
            "data-project-id", "data-projectid", "data-artwork-id",
            "data-artworkid", "project-id", "artwork-id"
        ]
        if markerKeys.contains(
            where: { attributes[$0]?.trimmed.isEmpty == false }
        ) {
            return true
        }
        return typeHint(
            in: attributes,
            containsAnyOf: ["project", "artwork"]
        )
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

    private static func isValidPathSlug(_ value: String) -> Bool {
        !value.isEmpty &&
            value.range(
                of: #"^[A-Za-z0-9][A-Za-z0-9_-]*$"#,
                options: .regularExpression
            ) != nil
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

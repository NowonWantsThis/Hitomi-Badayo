import Foundation

struct FediverseSearchResultResolver: SearchResultResolving {
    func supports(_ baseURL: URL) -> Bool {
        FediverseResolver.service(for: baseURL) != nil
    }

    static func dataAttributeLinkValue(
        in attributes: [String: String],
        baseURL: URL?
    ) -> String? {
        guard let baseURL,
              let service = FediverseResolver.service(for: baseURL) else {
            return nil
        }

        switch service {
        case .mastodon:
            if let id = mastodonDataAttributeStatusID(in: attributes),
               mastodonDataAttributeLooksLikeStatusCard(attributes) {
                return "/web/statuses/\(id)"
            }
            if let id = mastodonDataAttributeAccountID(in: attributes),
               mastodonDataAttributeLooksLikeAccountCard(attributes) {
                return "/web/accounts/\(id)"
            }
            if let username = dataAttributeUsername(in: attributes),
               dataAttributeLooksLikeProfileCard(attributes) {
                return "/@\(username)"
            }

        case .misskey:
            if let id = misskeyDataAttributeNoteID(in: attributes),
               misskeyDataAttributeLooksLikeNoteCard(attributes) {
                return "/notes/\(id)"
            }
            if let username = dataAttributeUsername(in: attributes),
               dataAttributeLooksLikeProfileCard(attributes) {
                return "/@\(username)"
            }
        }

        return nil
    }

    func extract(from context: SearchResultResolverContext) -> [SearchResultLink] {
        var results: [SearchResultLink] = []
        var indexByKey: [String: Int] = [:]

        for anchor in context.anchors {
            guard results.count < context.limit,
                  let absolute = context.resolvedURL(for: anchor),
                  let target = Self.canonicalURL(from: absolute) else {
                continue
            }

            let title = context.title(
                for: anchor,
                fallbackURL: target
            )
            SearchResultResolverSupport.appendUniqueResult(
                title: title,
                url: target,
                id: Self.resultKey(for: target),
                sitePrefix: "fediverse",
                results: &results,
                indexByID: &indexByKey,
                metadata: metadata(
                    target: target,
                    title: title,
                    anchor: anchor,
                    context: context
                )
            )
        }

        return results
    }

    private func metadata(
        target: URL,
        title: String,
        anchor: AnchorEntry,
        context: SearchResultResolverContext
    ) -> [String: String] {
        guard let service = FediverseResolver.service(for: target) else {
            return DownloadMetadata.clean([
                "title": title,
                "search_title": title
            ])
        }
        var metadata = context.contributorMetadata(for: anchor)
        metadata.merge([
            "category": service == .mastodon ? "mastodon" : "misskey",
            "site": service == .mastodon ? "mastodon" : "misskey",
            "title": title,
            "search_title": title
        ]) { current, _ in current }

        switch service {
        case .mastodon:
            if let statusID = FediverseResolver.mastodonStatusID(
                from: target
            ) {
                metadata["id"] = statusID
                metadata["post_id"] = statusID
                metadata["status_id"] = statusID
                metadata["media_id"] = statusID
                metadata["gallery_id"] = statusID
                metadata["type"] = "status"
            } else if let accountID =
                FediverseResolver.mastodonAccountID(from: target) {
                metadata["id"] = accountID
                metadata["account_id"] = accountID
                metadata["user_id"] = accountID
                metadata["uploader_id"] = accountID
                metadata["gallery_id"] = accountID
                metadata["type"] = "account"
            } else if let username =
                FediverseResolver.mastodonUsername(from: target) {
                metadata["id"] = username
                metadata["username"] = username
                metadata["user"] = username
                metadata["uploader"] = metadata["uploader"] ?? username
                metadata["uploader_id"] = username
                metadata["channel_id"] = username
                metadata["gallery_id"] = username
                metadata["type"] = "profile"
            }

        case .misskey:
            if let noteID = FediverseResolver.misskeyNoteID(from: target) {
                metadata["id"] = noteID
                metadata["post_id"] = noteID
                metadata["note_id"] = noteID
                metadata["media_id"] = noteID
                metadata["gallery_id"] = noteID
                metadata["type"] = "note"
            } else if let username =
                FediverseResolver.misskeyUsername(from: target) {
                metadata["id"] = username
                metadata["username"] = username
                metadata["user"] = username
                metadata["uploader"] = metadata["uploader"] ?? username
                metadata["uploader_id"] = username
                metadata["channel_id"] = username
                metadata["gallery_id"] = username
                metadata["type"] = "profile"
            }
        }

        return DownloadMetadata.clean(metadata)
    }

    private static func canonicalURL(from url: URL) -> URL? {
        guard let service = FediverseResolver.service(for: url),
              let host = url.host?.lowercased() else {
            return nil
        }

        var components = URLComponents()
        components.scheme = url.scheme ?? "https"
        components.host = host

        switch service {
        case .mastodon:
            if let statusID = FediverseResolver.mastodonStatusID(from: url) {
                components.path = "/web/statuses/\(statusID)"
                return components.url
            }
            if let accountID = FediverseResolver.mastodonAccountID(
                from: url
            ) {
                components.path = "/web/accounts/\(accountID)"
                return components.url
            }
            guard let username = normalizedUsername(
                FediverseResolver.mastodonUsername(from: url)
            ) else {
                return nil
            }
            components.path = "/@\(username)"
            return components.url

        case .misskey:
            if let noteID = FediverseResolver.misskeyNoteID(from: url) {
                components.path = "/notes/\(noteID)"
                return components.url
            }
            guard let username = normalizedUsername(
                FediverseResolver.misskeyUsername(from: url)
            ) else {
                return nil
            }
            components.path = "/@\(username)"
            return components.url
        }
    }

    private static func resultKey(for url: URL) -> String {
        let host = url.host?.lowercased() ?? ""
        if let statusID = FediverseResolver.mastodonStatusID(from: url) {
            return "\(host):mastodon-status:\(statusID)"
        }
        if let accountID = FediverseResolver.mastodonAccountID(from: url) {
            return "\(host):mastodon-account:\(accountID)"
        }
        if let noteID = FediverseResolver.misskeyNoteID(from: url) {
            return "\(host):misskey-note:\(noteID)"
        }
        if let username =
            FediverseResolver.mastodonUsername(from: url) ??
            FediverseResolver.misskeyUsername(from: url) {
            return "\(host):user:\(username.lowercased())"
        }
        return url.absoluteString.lowercased()
    }

    private static func normalizedUsername(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let username = raw.trimmed
            .trimmingCharacters(
                in: CharacterSet(charactersIn: "@/ ")
            )
            .replacingOccurrences(
                of: "\\s+",
                with: "",
                options: .regularExpression
            )
        let reserved = [
            "about", "api", "auth", "deck", "explore", "filters",
            "home", "notifications", "public", "search", "settings",
            "share", "tags", "web"
        ]
        guard !username.isEmpty,
              !reserved.contains(username.lowercased()) else {
            return nil
        }
        return username
    }

    private static func mastodonDataAttributeStatusID(
        in attributes: [String: String]
    ) -> String? {
        let explicitKeys = [
            "data-status-id", "data-statusid", "data-toot-id",
            "data-tootid", "status-id", "toot-id"
        ]
        if let value = firstAttributeValue(
            in: attributes,
            keys: explicitKeys,
            matching: isNumericID
        ) {
            return value
        }

        let typedKeys = [
            "data-post-id", "data-postid", "post-id", "data-id"
        ]
        guard typeHint(
            in: attributes,
            containsAnyOf: ["status", "post", "toot"]
        ) else {
            return nil
        }
        return firstAttributeValue(
            in: attributes,
            keys: typedKeys,
            matching: isNumericID
        )
    }

    private static func mastodonDataAttributeAccountID(
        in attributes: [String: String]
    ) -> String? {
        let explicitKeys = [
            "data-account-id", "data-accountid", "data-profile-id",
            "data-profileid", "account-id", "profile-id"
        ]
        if let value = firstAttributeValue(
            in: attributes,
            keys: explicitKeys,
            matching: isNumericID
        ) {
            return value
        }

        let typedKeys = [
            "data-user-id", "data-userid", "user-id", "data-id"
        ]
        guard typeHint(
            in: attributes,
            containsAnyOf: ["account", "profile", "user"]
        ) else {
            return nil
        }
        return firstAttributeValue(
            in: attributes,
            keys: typedKeys,
            matching: isNumericID
        )
    }

    private static func misskeyDataAttributeNoteID(
        in attributes: [String: String]
    ) -> String? {
        let explicitKeys = [
            "data-note-id", "data-noteid", "note-id"
        ]
        if let value = firstAttributeValue(
            in: attributes,
            keys: explicitKeys,
            matching: isNoteID
        ) {
            return value
        }

        let typedKeys = [
            "data-post-id", "data-postid", "post-id", "data-id"
        ]
        guard typeHint(
            in: attributes,
            containsAnyOf: ["note", "post"]
        ) else {
            return nil
        }
        return firstAttributeValue(
            in: attributes,
            keys: typedKeys,
            matching: isNoteID
        )
    }

    private static func dataAttributeUsername(
        in attributes: [String: String]
    ) -> String? {
        let keys = [
            "data-acct", "data-account", "data-profile",
            "data-username", "data-user-name", "data-user",
            "username", "user", "acct"
        ]
        for key in keys {
            guard let value = attributes[key]?.trimmed,
                  let username = normalizedUsername(value),
                  isProfileUsername(username) else {
                continue
            }
            return username
        }
        return nil
    }

    private static func mastodonDataAttributeLooksLikeStatusCard(
        _ attributes: [String: String]
    ) -> Bool {
        let markerKeys = [
            "data-status-id", "data-statusid", "data-toot-id",
            "data-tootid", "status-id", "toot-id"
        ]
        if markerKeys.contains(
            where: { attributes[$0]?.trimmed.isEmpty == false }
        ) {
            return true
        }
        return typeHint(
            in: attributes,
            containsAnyOf: ["status", "post", "toot"]
        )
    }

    private static func mastodonDataAttributeLooksLikeAccountCard(
        _ attributes: [String: String]
    ) -> Bool {
        let markerKeys = [
            "data-account-id", "data-accountid", "data-profile-id",
            "data-profileid", "account-id", "profile-id"
        ]
        if markerKeys.contains(
            where: { attributes[$0]?.trimmed.isEmpty == false }
        ) {
            return true
        }
        return typeHint(
            in: attributes,
            containsAnyOf: ["account", "profile", "user"]
        )
    }

    private static func misskeyDataAttributeLooksLikeNoteCard(
        _ attributes: [String: String]
    ) -> Bool {
        let markerKeys = [
            "data-note-id", "data-noteid", "note-id"
        ]
        if markerKeys.contains(
            where: { attributes[$0]?.trimmed.isEmpty == false }
        ) {
            return true
        }
        return typeHint(
            in: attributes,
            containsAnyOf: ["note", "post"]
        )
    }

    private static func dataAttributeLooksLikeProfileCard(
        _ attributes: [String: String]
    ) -> Bool {
        let markerKeys = [
            "data-acct", "data-account", "data-profile",
            "data-username", "data-user-name", "data-user",
            "username", "user", "acct"
        ]
        if markerKeys.contains(
            where: { attributes[$0]?.trimmed.isEmpty == false }
        ) {
            return true
        }
        return typeHint(
            in: attributes,
            containsAnyOf: ["account", "profile", "user"]
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
        !value.isEmpty &&
            value.allSatisfy { $0 >= "0" && $0 <= "9" }
    }

    private static func isNoteID(_ value: String) -> Bool {
        value.range(
            of: #"^[0-9A-Za-z_-]{3,128}$"#,
            options: .regularExpression
        ) != nil
    }

    private static func isProfileUsername(_ value: String) -> Bool {
        value.range(
            of: #"^[0-9A-Za-z_.@-]{1,120}$"#,
            options: .regularExpression
        ) != nil
    }
}
